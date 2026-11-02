<!-- claude-workflow:detailed-design -->
<!-- claude-workflow:design-status=reviewing -->

## 詳細設計

### 1. 概要・根拠

Issue #69 本文を要求の正本とする。PayPayの個人向け公式CSVを利用者が選択・送信し、構文の検証後に既存 #67/#68 の候補・分類・重複防止・訂正処理へ渡す。外部AIへ送信しない。CSVの取得操作は残る。

調査基点は `origin/main=81123fa8f054e2f5f1686cd242e34f06338c9737`（2026-10-30）。#66/#67/#68はマージ・close済み。`docs/明細取得方式調査_66.md` は同refで参照し、取得方式の調査と採用・有効化を区別する。作業HEAD `a103bc0` と同refのアプリ・スキーマ・specは同一。詳細設計・レビュー記録だけを `docs/issue_69/` へ保存し、本セッションで実装・branch作成・commit/pushを行わない。

2026-10-30に次の公式一次資料を再確認した。

- [現行CSVヘルプ](https://paypay.ne.jp/help/c0447/)：個人向けの項目一覧、UTF-8読込案内、返金収録・取消等の非収録、ポイント用ID接頭辞。
- [取引履歴の種類](https://paypay.ne.jp/help/c0141/)：支払い、給与、チャージ、送受金等の区別。これは画面の種類説明であり、CSVの全セル値を網羅する辞書とは断定しない。
- [Issue記載の旧告知](https://paypay.ne.jp/notice/20250206/f-transactionhistory/)：項目の根拠。相違があれば現行ヘルプ優先。

公開資料では全列挙値・実CSVの全バリエーションは確定できない。本設計でサポートする厳密な入力条件を第4章に定め、未知値は保留する。実ファイルの提出は必須にせず、公式情報から作った架空データで検証する。

### 2. 対象・影響範囲

- CSVアップロード、PayPay取引方法ごとの口座・支払方法設定、CSV用の確認済み分類ルール、共通候補への投入、履歴・集計・エラー表示を追加する。
- `ImportDocument(channel: "paypay_csv")` は1ファイル1文書。`ImportSource` はPayPay利用者の取込元を識別する固定namespaceで、行の反映口座とは区別する。同じPayPay利用者の再取込には同じ取込元を使う。service_keyは本経路で `paypay` に限定し、legacy不可。既存source.accountは識別のアンカーとして維持する。
- 複数経路を単一のsource.accountへ流さない。新設 `ImportPaymentRoute` に原文の取引方法→反映口座・支払方法を保存する。取引番号のidentityはrouteで分割せずsource内で一意にするため、方法が変わった同番号も訂正候補になる。
- 画像のルール・自動化設定・digest・既存終端状態・類似判定幅は維持する。Excel移行、通常取引・集計・クレカ精算の業務仕様は変更しない。
- 自動ダウンロード、金融API、Job、全銀行・全カード対応、実残高取込、銀行引落と利用明細の自動精算は対象外。

### 3. 現状処理と再利用先

| 現物 | 現状と本変更との関係 |
| --- | --- |
| `ImageReceiver.call(source:, images:, manual_date:)` | 画像検証→Gemini→候補保存→Applier。CSVは別Receiver・Parserとし画像抽出を経由しない |
| `EntryRecorder.call(document:, row_number:, payload:, draft_attributes:, trusted_external_id: nil)` | 同一文書行は再利用。外部IDのSHA-256と原文バイト比較でidentityを確定。同一identity・同内容は代表を参照。signature維持 |
| `ImageImportDraft` | 名前は画像だが共通候補として利用。全CSV行にも1対1で生成し、不正な値はnil、原文はpayloadへ保持 |
| `RuleResolver.call` / `.automatic_reasons` | 現状は画像フラグ・source.account前提。channelごとの許可と経路解決を共通サービスへ分離 |
| `Matcher.call` / `.classify!` | 同じ口座・収支・金額、日付±7日の取引と未処理候補を比較。候補ありは保留、外部IDの別版はcorrection。範囲・優先順位は維持 |
| `Applier.call(**arguments)` | Guard内で再検査→新規実績/対応/却下等を確定。auto_applyはHTTPから受け付けない。CSVも同じ経路 |
| `ReviewToken` / `OperationToken` / `TransactionCorrection` | 差分プレビュー・設定変更検知・訂正nonceを再利用。CSV経路snapshotを確認contextへ含める |
| `ImportGuard.synchronize` | DBのledgerロック→文書→entry→実績。設定・master更新との競合制御を維持 |

### 4. CSV入力契約・正規化・候補化

#### 4.1 ファイル全体の検証

1回につき1ファイル、最大8MiB・ヘッダーを除く1,000論理レコード。上限を超えれば分割を案内し無反映。これはアプリの上限でありPayPay公式の上限ではない。`size` を信頼するだけでなく `read(MAX_BYTES + 1)` で実bytesも検証する。空ファイルは422、妥当な見出しのみは0件の完了文書とする。

文字コードはUTF-8、先頭BOMは許可し解析時のみ除去。バイト列全体のUTF-8妥当性を検査し、推測変換・不正バイト置換をしない。NULは拒否。Ruby標準 `csv` を明示requireし、カンマ区切り、通常の二重引用符escape、LF/CRLFを扱う。セル内のカンマ・引用符・改行はCSV parserで処理し、splitで行や列を分割しない。フィールド文字数の独自切捨てはしない。全体サイズが保管量の上限でもある。

以下の13見出しを重複なく過不足なく受け付ける。見出しの順序は任意で名前で対応する。BOM以外の見出し変換・類似名推測を行わない。

`取引日` / `出金金額（円）` / `入金金額（円）` / `海外出金金額` / `通貨` / `変換レート（円）` / `利用国` / `取引内容` / `取引先` / `取引方法` / `支払い区分` / `利用者` / `取引番号`

読めない文字コード、不正見出し、閉じない引用符、レコードの列数≠13、行数上限超過はファイル全体エラー。最後までparse・列数検証を完了してからDBへ進み、有効に見える先頭行も反映しない。エラーには安全な固定文言、論理行番号（ヘッダー=1、データ=2以降）、取得できればparserの物理行番号を併記し、例外原文やセル内容をログへ出さない。空の中間レコードも列ずれとして拒否。末尾の通常改行をデータ行と数えない。

#### 4.2 原文と値の保存

parserは自動型変換なし。13列すべてをキー付き文字列（空欄は空文字へ統一）として `payload["csv_raw"]` に保存する。取引日時・金額・内容・先・方法・番号を省略せず、支払い区分・利用者・外貨欄も保持する。rawセルはtrim/Unicode正規化/数値化しない。比較用の値と分離する。

- 日時：前後ASCII空白を除いた `YYYY/MM/DD HH:MM` を厳密に解釈する（例の桁数、実在日・時分を検証）。秒あり `YYYY/MM/DD HH:MM:SS` も受け付ける。JST固定で `occurred_at` にoffset付きISO8601、`date` にJST日付を保存し、今日・月・年を補完しない。既存StrictDateと同じ2000〜2099年に限定。日時不正/欠落は行エラー、date=nil/date_origin=unresolved。
- 円金額：前後ASCII空白を除き、空文字・`-`・`ー`・`0` は取引なし。値は `[1-9][0-9]*` または桁区切りの正しい `[1-9][0-9]{0,2}(,[0-9]{3})+` を許可、カンマのみを除いてInteger化する。負数・小数・指数・通貨記号・全角数値・不正カンマを丸めない。両方が取引なし、両方が正額、片方でも不正なら行エラー。出金だけ正額ならexpense、入金だけならincome。draftへは1〜2^31−1のみ設定し、範囲外はamount=nilで行エラー。rawとパース可能な任意精度整数はpayloadに保持し、DBのintegerへ押し込まない。
- 通貨：外貨欄（海外出金金額・変換レート・利用国）のいずれかが空/上記取引なし記号以外、または通貨が空/`JPY`以外なら外貨/判定不能として対象外保留。JPYの識別には見えない文字を認めず、コードはASCII完全一致。通貨空で外貨情報なしは円列に基づきJPY。換算・為替計算をしない。
- 取引番号：空白のみ/空/制御文字は行エラー。それ以外は大文字小文字・先頭ゼロ・ハイフン等を保持した元の文字列を `trusted_external_id` に渡す。整数へ変換せず、全角→半角やstripもしない。長い識別子もtextへ無損失保存する。入力の8MiB上限内で桁数の独自打切りをしない。
- `merchant` は取引先原文。既存MerchantKeyによる検索用正規化だけ別に行う。255文字超はルール未適用保留で原文を維持。CSVの取引内容からメモ候補を作る場合は255文字までの表示用要約とし、raw欄で全文を閲覧できる。`source_method` は原文の取引方法、`source_status` は原文の取引内容。空の取引内容・取引先・方法は行エラーとし、通常収支としない。

`Fingerprint::SOURCE_KEYS` に `csv_raw` と `source_method` を追加し、PAYLOAD_KEYSにparser版、論理行・物理行情報、`csv_errors`・`csv_holds`を追加する。原文の13項目すべてが版の同一性に寄与し、行番号・設定・分類結果はdigestに含めない。既存image payloadに追加キーを作らず、既存のdigestは再計算しない。同じCSVをBOM/CRLF/引用方法/列順だけ変えても解釈後の同じセルならidentityの同版となる。

#### 4.3 通常収支と保留の判断

自動化候補のallowlistは、取引内容のASCII前後空白除去後が `支払い` かつexpense、または `給与` かつincome。通常入金の代表として公式で説明される給与を対象とし、入金列に金額があるだけでは通常収入にしない。既知の語でも以下の保留条件を先に適用する。

- 内容のチャージ、送金（譲渡）/受け取り/銀行口座への出金、カード引落・精算、返金、取消/キャンセル、手数料は既存kindへ対応（送受金はtransfer）。ポイント、外貨、支払い受付、未知の内容はunknown。該当理由を `csv_holds` に複数記録し、state=held、実績化しない。
- 方法または内容にポイントを含む、番号が `lp-` で始まる、複数方法の併用と判る表記はポイント/混合経路保留。方法のあいまい一致・部分一致・先頭の1口座だけ採用はしない。未知の方法はroute未設定として保留。
- 支払い区分は空/`-`/`ー`/`一回払い`/`1回払い`以外を要確認。利用者は空/`本人`以外を要確認。いずれも全列挙値の保証ではなく本アプリの対応条件とする。
- 既存TransactionKindClassifierが原文のmemo・merchant・evidenceから特殊語を検知した場合も優先して保留する。CSV側の通常判定で特殊kindを上書きしない。矛盾する収支と内容は行エラー。

正常な通常行は `transaction_kind=normal`、`source_kind=normal`、date_origin=source、metadata version=1、evidenceに原文のamount/direction/transaction_kind/merchant、uncertain_fields=[]を保存する。不正/対象外行は適切なunknown/特殊kindと不確実項目を持たせ、機械的な支出既定値を置かない。共通CandidateValidatorの手動・自動の要件を満たさない行を自動化しない。手動の種別訂正は既存の理由・確認フラグ・差分確認による明示操作でのみ行う。

### 5. 詳細フロー・設定・再実行

#### 5.1 支払経路と分類設定

`ImportPaymentRoute` はsourceと取引方法原文の完全一致（UTF-8バイト列のSHA-256＋原文比較）で1件解決する。sourceはservice_key=paypay、方法は1〜255文字・制御文字不可。空白・大文字小文字等のあいまい変換をしない。ポイント/混合方法を有効な通常routeとして登録できない。単独の未知方法は利用者が意味を確認して登録できるが、通常判定やその他のgateは省略されない。

routeはaccount/payment_method/credit_card_statusの3出力、enabled（初期false）、versionを持つ。e_money/bank/cashはaccount.kindとpayment.import_kindが一致しstatus=not_applicable、credit_cardはcredit_pending口座・credit_card方法・status=unpaidだけ許可。unknown/other/securitiesは拒否。route作成・編集には明示確認checkbox必須、Guard内で保存、lock_versionによるstale検知、キーは作成後不変、削除しない（停止のみ）。設定の一覧・追加・編集導線を取込元画面/CSVフォームへ置く。

新設 `Imports::SourceRoute` に解決と検証を集約する。imageはsource.accountの既存ルールを返し、paypay_csvは当該raw methodから現在のrouteと3出力を返す。自動判定用に初回snapshot（id/version/enabled/原文キー/3出力/関連master更新時刻）をdraft.confirmation_metadataへ保存し、後から上書きしない。後続の設定変更で未処理候補へ再割当て・自動反映をしない。

CSV用分類ルールはchannel=paypay_csv、import_payment_route_id必須。既存のsource・merchant・directionにroute IDを加えた一致条件を使う。ルール3出力はrouteと同一必須、カテゴリは収支に整合。画像ルールはroute ID=nilを必須とし、両channel間で自動転用しない。通常候補を明示確認して登録した実績からルールを作れるほか、既存と同じ明示設定フォームからも作れる。履歴起点のnewでchannel/route IDをentryから設定する。RuleWriterのorigin検証もSourceRouteを使う。ルール変更で将来の新規候補だけに作用する契約を維持する。

CSV自動反映の許可は、既存一般設定 `Setting.image_import_requires_approval=false`（取込全体の承認必須設定として画面文言を明確化）かつ `source.csv_auto_apply_enabled=true`。新フラグはfalse導入。画像の `image_auto_apply_enabled` と分離する。加えてroute初回/現在snapshot一致、route有効、確認済みルール1件・初回/現在snapshot一致、無編集、全validator正常、類似/訂正なしを要求する。

`SourceRoute.reasons(entry:, draft:, mode:)` は、imageで従来のsource口座検査、CSVでroute存在・有効・出力整合を返す。CSVの自動modeではcsv_errors/csv_holdsが空・初回route snapshot一致も要求する。manual modeでは現在routeと入力3出力の整合を確認する。新規実績を作るapprove/distinct/adopt_revisionにこの検査を通し、CSVの不明routeをdistinctで回避しない。画像distinct等の既存の差分確認付き口座不一致許可は維持する。手動link・反映済み実績訂正は既存の差分確認を維持し、自動設定を緩めない。route設定後も旧候補を自動再分類せず、候補を手動編集して確認する。

#### 5.2 受付・保存・反映

1. `CsvImportsController#create` はservice_key=paypay・非legacyの取込元を必須にし、ファイル1件をReceiverへ渡す。filename/MIMEは入力内容判定の根拠にしない。HTTPからpayload・external ID・routeの出力・自動actionを直接受け付けない。
2. Receiverがbytesを有界読込し、Parserでファイル全体を検証、全Row値オブジェクトを得る。失敗なら422で固定理由、取引0件・文書/entryも0件。行の値不正はRow.errorsとして保持し有効行も継続する。
3. Guard内でsource/channel/raw bytes SHA-256のImportDocumentをfind-or-create、同一ファイルは既存文書を利用。pipeline_version=paypay-csv-v1、received_at・batch_id・byte_sizeを初回保存（original filenameは保存しない）。既にextractedなら再抽出・ルール再評価・auto_applyを行わず結果へ戻る。
4. 新規/未完了文書は同じGuard transactionで全行をEntryRecorderへ渡す。row_numberはCSV論理行番号（2から）。全行にdraftを作り、円額・dateなど正常な部分だけ設定し、route出力は初回snapshotとともに候補へ設定する。外部IDが行として妥当ならtrusted_external_idを渡す。不正なIDはnil。Row.errors/holdsをpayloadに残し、reasonを日本語表示できる固定codeで記録する。
5. 全行保存後、非reference行をRuleResolver→Matcherの順に評価する。先に全候補が存在するので同一CSV内の類似も検出できる。ingestのerrors/holdsはMatcherの正常判定より優先して保留（ただしidentity訂正優先は維持）し、自動gateも必ず検査する。documentをextracted、error_code=nil、行数イベントを保存してcommit。途中の予期せぬ例外ではこの保存全体をrollbackする。
6. 保存後の新規非reference entryをID順にApplier(auto_apply)で個別確定。実績と確定イベントは同じtransaction。1件のfailed/例外でも他の行を続け、entryにprocessing_failedイベント・held理由を別Guardで記録し、文書のエラー件数/警告で検知可能にする。ログはclass名/内部ID/固定codeのみ。DB接続断で記録不可なら後続自動処理を中止し、既に確定した履歴と未確定分を案内する。
7. 文書showへredirectし、結果・全行・理由・共通確認画面へのリンクを表示する。全自動成功なら個別承認操作不要。承認必須時は候補を確認し既存の手動承認を使う。

#### 5.3 冪等性・訂正・部分失敗

- 同source同bytesはdocument unique、同document/rowはrow unique、同source/IDはidentity unique。同ID・同source payloadは代表を参照し、代表が未処理なら保留、終端なら重複として表示する。参照側から実績を新造しない。
- 期間重複/行順/列順/改行形式の違いもrawセルの内容と外部IDで比較。同じ番号の原文変更はcorrection。異なる番号の同内容も類似として保留し、勝手に別取引としない。
- 訂正前に未反映なら既存adopt_revision、反映済みなら既存の差分プレビュー・linkとTransactionCorrection、削除/編集検知と確認を使う。反映済みIDへ再度createせず、取消の非収録やCSVからの行消失を実績削除の指示とみなさない。
- 画像/手入力の重なりは共通Matcherの口座・収支・金額・日付±7日で保留。自動で二重登録しない。誤差がこの比較条件外の別データを同一と断定する保証はない。保留時は比較先と差分を示し利用者が同一/別を確認する。
- DB保存前のファイルエラーでは何も保存しない。候補保存途中失敗はrow/draft/eventsを全rollbackし、既存の受付文書をfailed（processing_failed）へ更新する。再送で同文書を再処理できる。新規文書の受付自体もrollbackした場合はその旨を返して再送を案内する。
- 候補保存後のauto_apply部分失敗・応答喪失では、同CSV再送は既存の現在結果を返す。確定済み行を再実行せず、未確定は手動確認へ送る。停止後の設定ONでも旧候補を遡及自動化しない。
- 不正行を修正した別CSVは新文書。妥当だった同番号の同版はreference、修正した同番号はcorrection。番号欠落行も旧候補との類似比較を行い、元行は履歴として維持する。
- Guard先行を必須にして並行CSV・画像・手動反映・route/ルール停止を直列化する。最終再検査と実績確定の間に設定変更を挟めない。

#### 5.4 結果・金額表示

CSV文書は専用 `CsvSummary.call(document:)` で、全論理行を排他的に次の順序で分類する。手動解決後も原文エラー/対象外理由は別欄に残す。

1. applied：appliedイベントmode=automaticなら「自動反映」、それ以外は「正常（手動反映）」
2. linked、またはreferenceの代表が終端： 「重複・対応済み」。reference元のrejected等は実績重複と誤解しない内訳も表示
3. 未解決でcsv_errorsあり、またはprocessing_failed： 「エラー」
4. 未解決でcsv_holdsあり、またはrejected/superseded/deletion_acknowledged： 「対象外・保留」（却下等の内訳付き）
5. その他（類似・訂正・ルール/route不明・承認必須・未解決reference・conflict）： 「承認待ち・要確認」

6区分（正常/自動/承認待ち/重複/対象外/エラー）の件数合計は全行数と一致させる。正常＋自動は実績化件数、対象外は「原文を保存したまま手動確認する」という意味で無視や削除ではない。訂正・類似・未解決reference・却下・競合の内訳を併記する。

区分ごとに**出金円/入金円を別々に**合計し相殺しない。未確定行/重複はraw円列から正しく算出可能な整数のみ合計し、金額不明件数も表示。外貨は換算せず円合計へ混ぜない。appliedは確定イベントのamount/directionを使い、後の編集で確定時集計が変わらないようにする。「CSV記載額（重複を含む）」と「今回の実績化額」を分け、元データと手修正の差を隠さない。これらは台帳の収支集計ではなく取込結果の集計である。

文書showで論理行番号、日時、取引先、元の円額、内容/方法/番号、結果、全理由、対応実績/代表候補を表示する。ページは100行単位、pageを保持し、全体集計をページ内集計にしない。長い原文の詳細はentry showで全長をescape表示。画像用「元画像未保存」等の文言をchannelで分岐する。既存未処理候補一覧/差分比較にもCSVの原文・route・日付出典を表示する。

### 6. 対象ファイル・クラス・メソッド

| ファイル（新規は「新」） | 実装契約・参照先 |
| --- | --- |
| `app/services/imports/paypay_csv_parser.rb`（新） | `.call(bytes:)` → Parsed(rows:, header:) / FileError(code:, row_number:, physical_line:)。Rowはraw、payload、draft_attributes、errors、holds、external_id。ファイル全体parseと値検査、DBへアクセスしない |
| `app/services/imports/csv_receiver.rb`（新） | `.call(source:, file:)` → Result(document:, file_error:, processing_errors:, applied_count:)。ImageReceiverのdocument冪等性とGuard構造を参照。Parser/Recorder/Applierを実クラスで接続 |
| `app/services/imports/source_route.rb`（新） | `.resolve(entry:)` → route/snapshot/reasons/expected outputs、`.reasons(entry:, draft:, mode:)`、`.auto_enabled?(source:, channel:)`。source/channel前提を集約、unknown channelは許可false |
| `app/models/import_payment_route.rb`（新） | 原文キーimmutable・SHA照合、整合validation、version/lock_version、snapshot、Guard、停止のみ |
| `app/controllers/import_payment_routes_controller.rb`、`app/views/import_payment_routes/{index,new,edit,_form}.html.erb`（新） | source配下index/new/create/edit/update、確認checkbox、stale/validationを422。未確認で保存しない |
| `app/controllers/csv_imports_controller.rb`、`app/views/csv_imports/new.html.erb`（新） | new/create。source選択と1ファイル送信、上限・対応書式・残るDL操作・設定導線、エラー理由を422表示 |
| `app/services/imports/csv_summary.rb`（新） | `.call(document:)` → 各区分counts/outgoing/incoming/unknown_amount_count、現在処理結果と原文額。controller/helperへ判定を重複させない |
| `app/services/imports/{fingerprint,entry_recorder}.rb` | public signature維持。payload許可追加。SOURCE_KEYSへの追加はCSVキーだけ、imageの意味は不変。既存Recorderへ信頼済IDを渡す |
| `app/services/imports/{rule_resolver,matcher,applier}.rb` | public signatures維持。SourceRouteを参照しchannel別許可、route追加照合と自動snapshot再検査、ingestの保留理由維持。Matcherの±7日等は変更しない |
| `app/models/import_classification_rule.rb` | channelにpaypay_csv、csv route条件、EDITABLE_ATTRIBUTES/INPUT_KEYS/snapshotにroute ID追加、出力検証。画像nil route必須 |
| `app/services/imports/rule_writer.rb`、`app/controllers/import_classification_rules_controller.rb`、同views | origin_contextのchannel/route検証、履歴起点のchannel/route初期値、csv選択/route選択と日本語の適用条件。nonce・明示確認維持 |
| `app/services/imports/{review_token,operation_token}.rb` | `.context`/`.configuration_context` に現在CSV route snapshotを追加。date一括変更とTransactionCorrectionはconfiguration_contextを通じ変更検知 |
| `app/models/{import_source,account,payment_method}.rb` | routesの関連・inverse_of・削除restrict。sourceにcsv_auto_apply_enabled（false）、service=paypay CSV eligibility |
| `app/controllers/import_sources_controller.rb`、`app/views/import_sources/*` | create/updateのpermitにcsvフラグ、画像と別の許可checkboxとroute管理導線。immutableなsourceのキーは維持 |
| `app/controllers/import_documents_controller.rb`、同views/CSV用partial（新） | CSV100行ページング・全行集計・理由表示、image表示維持。showで全payloadを無制限にpreloadしない。summaryの参照に必要な最小列/eventsを使う |
| `app/views/{import_entries,image_import_drafts,import_draft_dates}/*`、`app/helpers/imports_helper.rb` | 原文/route/日時/番号/エラー表示、sourceアンカーと行口座の区別、reason辞書。既存_values比較にcsvフィールドのラベルを追加 |
| `app/views/{more,settings}/*`、`app/views/import_documents/index.html.erb`、必要な共通navigation | CSV入口・全取込共通承認の文言。設定カラム名は互換維持 |
| `config/routes.rb`、`config/initializers/filter_parameter_logging.rb` | resource csv_imports only new/create、source nested payment routes only index/new/create/edit/update。csv_file/csv_raw/source_methodなど原文paramsをfilter |
| `db/migrate/*_add_paypay_csv_import.rb`（新）、`db/schema.rb` | 第7章。既存の#67/#68 migrationを編集しない |
| `spec/{services/imports,models,requests}/*`、`spec/support/import_concurrency.rb` | 第10章。専用#69 DB許可と新表のFK順cleanup |
| `spec/fixtures/files/paypay_csv/*`（新）、`docs/issue_69/取込条件と検証データ.md`（新） | 全件架空。ファイル例・期待結果・公式根拠と未確認条件。実利用者データは含めない |
| `docs/{要件定義書,アプリケーション仕様書}.md` | 実装後にCSV入口、半自動、条件、保留・保持方針を現物へ合わせる |

### 7. DB・トランザクション・移行

新テーブル `import_payment_routes`：import_source_id/account_id/payment_method_idはNOT NULL FK、source_method(string255)・source_method_digest(string64)・credit_card_status(string32)・enabled(boolean false)・version(integer1)・lock_version(integer0)・timestamps。source/digestの複合unique、FK補助index。digestはUTF-8バイトのSHA-256、読出時原文bytes一致を追加検査してMySQL照合順序の影響を避ける。衝突は固定codeで保留/設定エラーとし別キーへフォールバックしない。

`import_sources.csv_auto_apply_enabled` はNOT NULL default=false。`import_classification_rules.import_payment_route_id` はNULL可FK＋index（既存画像ルールはnil）。`ImportPaymentRoute`と各親にinverse_of、dependent: restrict_with_error、route自体destroy禁止。Account/PaymentMethodがrouteだけに参照される場合も削除を理由付きで拒否する。source_method等の必須DB制約はモデルvalidationにも対応させる。

既存payload/digest/取引/候補/画像許可を更新しない。routeは0件・CSV自動許可falseで導入し、seedやschemaロードだけで自動化を有効にしない。JSON列追加は不要。新表/列/index/FKを個別存在確認し、MySQL DDLの途中再開でも欠落制約を補完する。MySQL・PostgreSQLのmigrationからの構築/schemaロードの双方を検証する。履歴と設定を失うdownはIrreversibleMigration。

ファイル読込・parseはtransaction外。候補一括保存は最大1,000行のGuard transaction、実績反映はentry単位。Guard→設定→文書→候補ID順→identity/実績の既存順を守る。route/ルール/関連master/承認設定の保存・削除にも既存ImportConfigurationGuardを使う。route設定変更はversionとupdated_atを同じtransactionで更新する。

### 8. 外部連携・ファイル・機密情報

利用者端末→アプリのmultipart一時ファイル→解釈後のrawセル/候補/イベントDB。CSVをGeminiや金融サービスへ送らず、URL取得・自動DL・メール・Job・課金処理は追加しない。元CSVのバイナリ・filenameはアプリで永続保存しない。requestの一時ファイルはRackのライフサイクルで破棄される。CSVの13列原文は監査/再取込/訂正のためDBに保持し、既存取込履歴同様このIssueで自動削除機能は追加しない。バックアップ/端末/iCloudの保持までアプリ側削除を保証しない。

modelのfilter_attributesとparameter filterにcsv_raw/csv_file/source_method/取引番号を含め、失敗時に例外message/raw CSVをログ出力しない。ERB escapeを使いhtml_safeなし。CSVエクスポート機能は追加しない。テスト/Issue/PR/レビュー記録に実ファイルや個人名・口座番号を入れない。

#66の有効化条件（本人以外の閲覧/操作を防ぐ認証・認可または実効的アクセス制限、HTTPS、DB/バックアップ保持方針の確認）は引き継ぐ。現状認証なしのため、この実装だけで公開先の保護を満たしたと断定しない。設計/ローカル架空データ検証と実データ運用の有効化は区別する。保護未確認の環境へ実データを投入しない。

### 9. 例外系・境界条件

- 空/不正ファイルは無反映、見出しのみは0件、行値エラーは保存して有効行を継続。ファイルの途中で不正quote/列数を発見しても先頭行を反映しない。
- nil/0/小数/負額/overflow/日付欠落・時刻不正は原文を残して保留。反映時に共通validatorで再検査。自動補完・切捨て・float変換はしない。
- routeなし/停止/変更、ルール0/複数/停止/変更、承認必須、CSV許可false、未知channelは自動反映なし。停止後に再有効化しても旧候補を自動化しない。
- 取消/処理中等が公式CSVに含まれないことを空データ/全件反映と混同しない。CSVにない日・番号の台帳を削除・精算しない。
- identity/routeのdigest衝突、DB busy（既存リトライ回数維持）、書込み失敗は固定理由と履歴確認へ。想定外例外はclass/内部IDのみ記録し、成功と報告しない。
- preview後のroute/master/rule/source/setting変更は署名context不一致で無更新、再プレビューへ。改変token/別purpose/期限切れも既存どおり拒否。
- 同一CSV再送後の結果画面は今回新規自動件数と過去を含む文書の累積結果を区別し、「再送で再登録した」と表示しない。

### 10. テスト方針・受入条件との対応

本設計フェーズはアプリ変更なし。以下は実装フェーズの必須検証であり、成功済みではない。外部Gemini/金融APIは呼ばず、CSV→Parser→Recorder→RuleResolver→Matcher→Applier→DBの結合を実クラスで検証する。

| ID / 対応する受入条件 | 入力・試験 | 期待結果 |
| --- | --- | --- |
| T1 / 公式書式・非個人データ | 架空13列fixture、公式URL/確認日、UTF-8 BOM有無、LF/CRLF、順序変更 | 現行項目と条件を文書化、実ファイル不使用、同セルは同版 |
| T2 / ファイル全体異常・境界 | 0bytes、BOMだけ、見出しのみ、欠落/追加/重複見出し、CP932/不正UTF-8/NUL、閉じないquote、列過不足、正常先頭＋不正末尾、8MiB±1、1,000/1,001行、偽size | 見出しのみ0件成功、その他指定異常はdocument/entry/Transaction増加0、422と安全な理由 |
| T3 / 無欠損・整数・日時 | 長い/前ゼロ/大小文字ID、lp-ID、引用符・セル改行・カンマ額、1/2^31−1/2^31、0/両欄正額/小数/負/指数/全角/不正桁区切り、日付なし/不正/閏日/月年境界/秒 | raw13列一致、日時JSTとdate一致、無丸め、読める部分だけ保持、行理由/論理・物理行が対応 |
| T4 / 複数支払経路・対応再利用 | 同一sourceでe_money/credit_card/bank経路混在、同じ店を複数経路、未設定/停止/未知/ポイント混合、SHA衝突stub | 別々の正しい口座・方法・クレカ状態、未設定は保留、raw完全一致、全行をsource.accountへ割当てない |
| T5 / 通常収支・承認・分類 | 支払いexpense/給与income、ルール0/1/複数、別channel/route/source/merchant/direction、承認true/false×CSV許可true/false、画像許可独立 | 全gate成功の新規だけauto、承認必須ではTransaction=0、通常再取込で各行の経路再選択0、画像ruleはCSVへ転用しない |
| T6 / 特殊行の保留 | チャージ/送金/受取/引落/返金/取消/手数料/ポイント/lp-ID/海外通貨/外貨額・レート/支払い受付/未知内容、通常語と矛盾 | 全文・複数理由を表示しauto=0、手動種別訂正の確認を迂回できない、非収録の行消失は台帳変更0 |
| T7 / 重複・訂正 | 同bytes、期間重複、同番号同版/別版、取引方法変更同ID、番号だけ変更、画像/手入力/別CSVの類似、同CSV内同ID/類似、未処理代表の参照 | 同版reference、別版correction、類似held、単純approveで二重登録不可。訂正版採用/対応/反映済訂正/削除確認は既存契約どおり |
| T8 / 部分失敗・再実行 | 正常＋値不正＋特殊行、保存中例外、auto途中失敗/予期せぬ例外/接続断、成功commit後応答喪失、修正CSV再送 | 有効行は処理、書込み中は全候補rollback、確定済実績不変、失敗理由と履歴、再送/設定ONで二重・遡及autoなし |
| T9 / 件数・金額・閲覧 | 6区分混在、円出入混在/不明額/外貨、手動修正後、duplicate代表が却下/未解決、101/1,000行ページング | 区分和=全件、方向別・不明件数と原文/確定額を区別、全件へ到達、確定時集計はイベント由来、XSS文字/長いセルを安全に全長表示 |
| T10 / 設定と署名・運用 | route create/update二重/並行、stale、未確認checkbox、immutable key、master削除/種別変更、抽出→auto間変更、preview→確定間route/ルール/設定変更 | unique/restrict/422が有効、同source以外のroute注入拒否、停止後auto不可、古token拒否、旧候補を再割当てしない |
| T11 / 競合・回帰 | 同CSV並行、重複期間CSV並行、CSV×画像/手動、auto×route停止、別sourceの独立ID、旧画像・旧digest・訂正・クレカ/集計全spec | 実績1件、原文/イベント欠落なし、image同一性と終端不変、既存類似条件・通常編集の仕様維持 |
| T12 / 両DB・移行 | MySQL/PostgreSQL各migration/schema構築、既存fixture投入、migration途中再開、routeだけ参照するmaster削除 | FK/unique/default/version整合、旧値不変、CSV許可false・route0、理由付き削除拒否、全RSpec成功 |

並行specは既存ImportConcurrencyを利用し、専用使い捨て `budget_book_app_test_69` を許可リストへ追加する。新表のcleanupはrule→route→draft/entry等のFK順を守る。thread/barrierと実DBで競合を検証し、共用開発/本番DBを使わない。テスト対象設定以外の秘密値を表示しない。

実装時コマンドは `RAILS_ENV=test bundle exec rspec`（IMPORT_TEST_ADAPTER/IMPORT_TEST_DATABASEは専用値）、変更Rubyの `ruby -c`、`git diff --check`。両DBでmigration/schema構築の4条件の全spec結果を `docs/issue_69/検証結果/` に保存し、既存pendingと新規失敗を区別する。上記T2/T4/T5/T8/T9はrequest→DB/画面まで検証する。

初期設定済みの架空CSV10件（支払い・給与・複数経路）で、毎行の分類/口座/方法再選択0・個別承認0・取引10件を検証する。CSV取得/送信とsource選択・結果閲覧は残る。承認必須時は10件すべて未実績とし、設定切替だけで旧10件を自動化しない。実CSV/実金融接続による検証は完了条件へ含めない。

### 11. 後方互換性・回帰リスク

画像のsource単一口座・フラグ・ルール、#67のID原文比較/終端/訂正、手動の差分確認、既存の実績・集計・精算は維持する。旧digestを更新せず、CSVキーを画像payloadへ付与しない。新規CSVのrouteと許可は明示設定後だけ作用する。

主なリスクはsource.accountを参照する箇所の変更漏れ、route設定変更の競合、ルールとroute出力の食違い、rawの切捨て・implicit integer変換、CSV全体異常の途中反映、集計の参照先/原文/確定額の混同。SourceRouteへの集約、snapshot、parse先行、T3/T4/T7〜T12で検証する。ルール学習や曖昧判定による自動化範囲の拡張はしない。

### 12. レビュー状態

- Technical Reviewer: REVIEWING
- Consistency Reviewer: REVIEWING
- 新規の専用Reviewer 2体を各回並列起動し、指摘を根拠確認・修正後にfreshな2体で再レビューする。指摘0の両PASSで確定し、design-status=approvedへ更新して停止する。
- 本セッションの対象は詳細設計まで。/clearまたは新規セッション後、正本から実装フェーズを再開する。
