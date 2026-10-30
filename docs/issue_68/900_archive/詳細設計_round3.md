<!-- claude-workflow:detailed-design -->
<!-- claude-workflow:design-status=reviewing -->

## 詳細設計

### 1. 概要・正本・設計基点

- 対象: [Issue #68](https://github.com/Murakou15724/budget_book_app/issues/68)。親Issue #65、依存Issue #67。
- 確認日: 2026-10-21。最新mainは `2b0628b34f71c75e2c0b570aa5a29630327d70fb`（PR #78、2026-10-20マージ）。作業場所のHEAD `85e4fed` とorigin/mainの追跡ファイルの差分はない。
- GitHubの本コメントを仕様の正本とし、`docs/issue_68/詳細設計.md` は同期した作業記録とする。このフェーズでアプリ実装・DB適用・commit・pushを行わない。
- 確認済み分類を、取込元・入力経路・元口座・取引先・収支で限定したルールとして明示保存する。一意に適合した確認済みルールと妥当な原文情報がある通常取引だけ、二重の許可設定のもとで自動反映する。
- AIの名称一致や自己申告の確信度だけでは確定しない。分類・支払経路の確定根拠は利用者が保存したルール、または今回の明示確認とする。

### 2. 対象・影響範囲と受入条件の対応

| Issue #68の受入条件（本文順） | 設計・検証 |
|---|---|
| AC1 分類・支払経路の範囲付き再利用、修正からの作成は選択式 | 4.1、5.1、T1/T2 |
| AC2 有効・範囲・優先度・理由、複数一致は保留 | 4.2、5.2、T2/T3 |
| AC3 初期無効・承認必須維持・対象経路の明示許可 | 4.3、5.3、T4 |
| AC4 日付・金額・収支・分類・支払経路・クレカ矛盾を阻止 | 4.4、5.4、T5 |
| AC5 日付の由来と未確定、一括指定の対象・結果確認 | 4.5、5.5、T6 |
| AC6 チャージ等の区別、不明は例外、精算・相殺を推測しない | 4.6、T7 |
| AC7 自動成功の件数・金額・適用ルール、保留だけ確認 | 5.6、T8 |
| AC8 ルール変更は将来のみ、反映後訂正は差分確認の別操作 | 5.7、T9/T10 |
| AC9 同名別口座・競合・未知・欠落・区分不一致・承認・停止・再実行 | T1〜T12 |

対象は現存する画像取込と#67の候補／実績連携。ルール判定・検証は入力経路を引数で分離し、将来のCSV経路でも呼べるが、CSV取込・Job化・サービス接続を本Issueで追加しない。通常の手入力、クイック入力、カード支払済操作の仕様を一括変更しない。

### 3. 現状仕様・確認した実装

- `ImageImportDraftBuilder.build(items, document:, manual_date: nil)` は収入以外を支出に丸め、名称をLOWER完全一致で照合する。`Date.parse` で日付を読み、手動日付→抽出日付→文書の受付日で補う。`resolved?` は主にマスタIDと正の金額しか見ない。
- `Gemini::TransactionExtractor` の必須キーはdate/direction/amount。directionはincome/expenseのみ。取引先専用の値・特殊取引区分・原文根拠・不確実性を要求しない。
- `Imports::EntryRecorder` が許可キーでpayloadを固定し、`Fingerprint.source_payload` のdigestを保存する。元payloadを候補編集で変更しない。
- `ImageReceiver` は文書digestで再送を抑制し、extracted文書は再解析しない。抽出を文書単位で保存した後、承認必須=falseならfresh entriesにApplierのapproveを呼ぶ。
- `Matcher` は同口座・収支・金額・日付±7日の実績／予定／未処理候補、外部ID訂正、元口座不一致を保留する。`Applier` はGuard→文書→候補のロック下で再判定し、終端・参照候補を再登録しない。
- `Transaction` は日付範囲、正の整数金額（10億未満）、参照マスタ等を検証するが、カテゴリkindとdirection、支払方法と口座kindの整合性までは検証しない。
- `PaymentMethod` はname/note/positionのみで種別を持たない。`Account.kind` はbank/e_money/securities/cash/credit_pending。既存のクレカ運用は「利用時=支出・クレカ・credit_pending・未払」「引落時=別の取引を作らず既存実績を支払済に変更」。`docs/要件定義書.md:77` と実装を確認した。
- 一般設定 `image_import_requires_approval` は既定true。取込元単位の自動許可、確認済みルール、日付出典、反映後訂正の差分プレビューは現状ない。
- 参照spec: `image_import_draft_builder_spec.rb`、`image_import_draft_spec.rb`、`services/imports/*`、`requests/import_entry_resolution_spec.rb`、`import_credit_card_integrity_spec.rb`、`import_history_spec.rb`。並行テストのヘルパーはDB名を `budget_book_app_test_67` に限定しているため、#68用に明示した専用DBへの対応が必要。

### 4. データ・判定仕様

#### 4.1 確認済みルール

新規 `ImportClassificationRule`（`import_classification_rules`）に次を保持する。

| カラム | 型・制約・意味 |
|---|---|
| import_source_id | bigint、NOT NULL、FK。元口座はImportSource.account_idで一意・不変 |
| channel | string(32)、NOT NULL、初期はimageのみ許可 |
| merchant_key | string(255)、NOT NULL、正規化した取引先の完全一致条件 |
| direction | string(16)、NOT NULL、income/expenseのみ |
| category_id / payment_method_id / account_id | bigint、NOT NULL、各FK。反映先accountは取込元accountと一致必須 |
| credit_card_status | string(32)、NOT NULL、not_applicable/unpaidのみ |
| enabled | boolean、NOT NULL、default false |
| priority | integer、NOT NULL、default 100、0〜9999（小さい数が先） |
| version | integer、NOT NULL、default 1。変更ごとに加算 |
| confirmation_entry_id | bigint、NULL可、ImportEntryへのFK。手動新規はNULL |
| confirmed_at | datetime、NOT NULL。利用者が内容を確認して保存した日時 |
| creation_nonce | string(36)、NOT NULL、unique index。フォーム発行時のUUIDを保存 |
| creation_request_digest | string(64)、NOT NULL。初回作成で確認した条件・出力・元候補を正規化したdigest |
| timestamps | Rails標準 |

検索indexは `[import_source_id, channel, enabled]`。一致条件のunique制約は設けず、重複ルールも検出して保留する。merchant_keyはNFKC、前後空白除去、連続空白1文字化、downcaseで正規化し、記号や支店名は削らない。正規表現・部分一致・全口座共通・取引先未指定のルールは初期実装に設けない。255文字超過は切り詰めず入力不正／判定保留。

ルールは通常取引用であり、特殊取引をnormalへ書き換えない。金額・日付・memo・entry_typeをルール出力に含めない。出力のdirectionは一致条件と同値、カテゴリkindも一致必須。

変更・停止・再有効化はGuard内でversionを加算し、元候補から `rule_created/rule_changed` イベントを記録する（元候補がある場合）。ルールは物理削除しない。判定時の全出力・条件・名称・versionを候補／イベントへsnapshotするため、後のルール編集や名称変更で履歴表示が書き換わらない。

#### 4.2 一致と優先順位

元文書のsource/channel/source.account_id、原文専用merchant、原文directionが条件。memoを取引先の代替にしない。AIのsuggested_*や利用者が今回直したmemoを一致条件にしない。原文merchantが空、不確実、長さ不正、directionが不明なら一致なし。

有効ルールをpriority、id順で並べ、一致IDと優先度をすべて表示する。一致0件=`rule_missing`、2件以上=`rule_ambiguous` とし、出力が同じ場合や優先度が異なる場合も保留する。優先順位は一覧・説明の順序を定める値であり、多重一致の黙った勝者選択に使わない。利用者が重複ルールを停止／条件変更して解消する。

1件でも、参照マスタ欠落・kind変更・経路矛盾は `rule_invalid`。候補はAI提案とルール出力を区別し、ルールを適用する前の入力と適用後の差分をイベントに残す。

#### 4.3 自動許可と設定

`import_sources.image_auto_apply_enabled` boolean NOT NULL default falseを追加。経路はsource×imageであり、source自体がサービス×元口座に固定される。

自動反映の必要条件は、`Setting.current.image_import_requires_approval == false` **かつ** 対象sourceの新フラグtrue。既存設定値をmigrationで変更しない。旧設定falseでも、新フラグ未許可の取込元は自動化しない。取込元設定フォームでは対象サービス・元口座・image経路・一般承認設定との関係を明記し、有効化チェックは初期未選択。設定更新だけで既存候補を処理しない。

設定読み書き・ルール読み書きと自動反映は同じGuardに直列化する。Setting/ImportSource/ルールの更新経路はGuardを先に取る（コールバック内でも書き込みSQLより先に取得）。Applierは古いcontroller変数を使わず、Guard取得後に最新値を取り直す。停止のcommitより後に実行開始した反映は止まり、停止より先にcommitした実績は維持する。

#### 4.4 共通整合性と自動反映条件

新規 `Imports::CandidateValidator.call(draft:, metadata:, mode:)` はreason_codesを返す。modeはmanual/automatic。取込経路の全新規作成操作（approve/distinct/adopt_revision/auto_apply）、linkの予定→実績変更、反映後訂正に共通検証を置き、distinctやlinkでも矛盾を通過させない。Transactionの一般手入力のvalidationを広げる代わりに、取込の書き込み境界で必ず実行する。

日付範囲・整数金額・収支とcategory.kind・支払方法と口座kind／クレカ状態・to_account・due overrideの組合せは同クラスの `.transaction_reasons(transaction:, context:)` に集約する。CandidateValidator.callはdraftのTransaction投影を渡し、linkと訂正も実際に保存するTransactionの正規化後の値を渡す。contextはnew_import/planned_promotion/correctionで、paid許可等の差を明示する。出典・不確実性・ルール・特殊kind等の元候補に関する検証はcall側に残す。

共通条件:

- dateは明示確認済みまたは原文の完全日付、Transactionの既存範囲内。amountは正の整数かつ10億未満（小数・指数・非数値・マイナスを丸めて通さない）。directionとcategory.kindが一致する。
- 必須マスタの存在を再確認。支払方法の意味は新規 `PaymentMethod.import_kind` string NOT NULL default `unknown` で表す。許可値はunknown/cash/bank/e_money/credit_card/other。既存レコードはすべてunknownにし、名前から移行推定しない。マスタ編集画面で利用者が明示選択する。新規もunknownが初期値。
- cash→cash口座、bank→bank口座、e_money→e_money口座でcredit_card_status=not_applicable。credit_card→expense＋credit_pending口座＋unpaid。income＋credit_card、paidでの新規取込、unknown/other、securities経路は `payment_route_unconfirmed` または `payment_route_mismatch` として保留。通常画像取込の対象外経路は従来の手入力で扱い、自動推定で許容しない。
- 通常取引の反映accountはsource.accountと一致。別口座への手動distinctは#67の比較・差分確認に加え、明示したsource_account_mismatchの確認をReviewTokenに含めた場合のみ許す。自動では常に禁止。
- 支出のcredit_card_payment_due_on_overrideはnilまたは妥当な完全日付。非クレカはoverride=nil。反映後のクレカ支払済訂正は5.7の別検証による。
- transaction_kindはnormalまたは利用者が確認したfee、transfer、investmentのみ新規作成できる。normal/feeはincome/expenseとの整合性必須（feeはexpenseのみ）。transfer/investmentは利用者が指定したdirectionと一致し、draftに追加するto_account_idが存在・元口座と異なり、credit_card_status=not_applicable。移動経路ではbank/e_money/cash/securities間を許容するが、支払方法kindはbank/e_money/cashのいずれかで、source口座kindに対応するもの（securities元口座はbank）を明示指定する。カテゴリはnilとする。

自動ではさらに、ルールが一意かつ現時点でも有効、transaction_kind=normal、direction=income/expense、日付確定、抽出の不確実性なし、分類・経路がそのルール出力から確定、`Matcher` がnew/pending、参照候補・訂正・conflict・user_held・legacyでないことを必須とする。1つでも満たさなければ反映せず、理由を記録する。

`ImageImportDraft#resolved?` は共通整合性のmanual検証を使う表示用判定に変更するが、自動許可・重複チェックの代わりに使わない。draftには不正な組合せも編集途中として保存できる。Transactionへの作成時に阻止する。

#### 4.5 日付と抽出根拠

Geminiのschema/promptに次を追加する。API呼出先・認証方法は変更しない。

- `merchant`（店名の原文、memoとは別）、`transaction_kind`（normal/charge/transfer/card_settlement/refund/cancellation/fee/unknown）、`raw_date`（原文の年月日表記）、`date_year_explicit` boolean。
- `uncertain_fields`（date/amount/direction/merchant/transaction_kindの配列）、`evidence`（amount/direction/transaction_kind/merchantそれぞれの短い原文文字列）。確信度スコアの閾値は使わない。
- 読めない値は空／unknown、不確実性を明示。年を当年で補わない。directionはincome/expense/transfer/investment/unknownへ拡張するがkindと独立に検証する。

サーバは欠落メタデータを確定扱いしない。unknownなenumは保留用unknownへ正規化し、AIの値をRails enumへ直接渡さない。amountはJSON整数のみ有効。不正値はdraft.amount=nil、原文値はpayloadに保持する。必須キーのあるHash行は不完全でも候補として保存し、旧schemaの応答は `extraction_evidence_missing` で手動確認へ送る。Hashでない要素等の既存の形式除外／全件失敗処理は維持する。

日付を原文由来の確定とするのは、raw_dateに4桁の年と月日があり（YYYY-MM-DD、YYYY/MM/DD、YYYY年M月D日だけ対応）、厳密にDate.newで成立し、date_year_explicit=true、不確実性にdateがなく、dateのISO8601値とも一致する場合。年なし・相対日・複数日付・不一致・1900-01-01以下／2100-01-01以上は未確定。`Date.parse` と受付日補完を使わない。`fallback_date` は#67の受付履歴表示用にだけ残す。

これは画像のAI抽出に対する保守的な検証でありOCR誤読の完全検出ではない。自動反映時は上記原文根拠が各項目に存在し、uncertain_fieldsが空で、利用者確定ルールの収支／支払経路と矛盾しないことを求める。kindが特殊・unknown、原文に「チャージ／入金チャージ／振替／口座間移動／カード引落／返金／取消／キャンセル／手数料」等の明示語がある場合はnormalとして反映しない。判定語の一覧と優先順（特殊→normal）を `TransactionKindClassifier` の定数とspecで管理する。AIのマスタ名一致だけではこのゲートを通らない。

draftへ `date_origin` string NOT NULL default unresolved（unresolved/source/user）、`transaction_kind` string NOT NULL default unknown、`confirmation_metadata` json NOT NULL（defaultに依存せず明示初期化）、`rule_decision` json NOT NULLを追加。metadataには原文根拠・不確実性・手動確認項目と日時・自動判定可能性を保持する。rule_decisionは評価日時・候補ID・適用ルールsnapshot・before/after・全理由を保持する。

`EntryRecorder` のpayload許可キーには抽出メタデータを追加するが、既存 `Fingerprint::SOURCE_KEYS` とそのdigest算法は変更しない。追加フィールドを既存外部IDの版比較に混入させず、既存payload/digest/target_snapshotは書き換えない。全抽出根拠はpayloadとmetadataに保存し、画像バイトやAPI応答全体は保存しない。

#### 4.6 特殊取引

| kind | 候補の扱い／利用者が選べる解決 |
|---|---|
| normal | ルールと全ゲートが揃えば自動可。それ以外は手動確認 |
| charge / transfer | 支出にしない。手動でtransfer、移動先、経路を明示して差分プレビュー→distinct等。chargeは確認後も特殊由来として履歴に残す |
| card_settlement | 常に保留。既存のクレカ未払画面へ案内。新規支出・振替・自動支払済を作らない |
| refund / cancellation | 常に保留。対応元の実績を確認する。自動相殺・新規負額取引・推測収入を作らない。必要なら既存実績の訂正を5.7で行い、元候補は保留または却下 |
| fee | 自動不可。利用者がfeeとして確認した支出のみ手動登録。別の金額との自動合算・分割はしない |
| unknown | 自動不可。利用者がkind・directionと必要項目を明示して初めてmanual検証を通せる |

原文に特殊語がある行をnormalに変更する場合は、種別訂正の専用確認欄と理由を必須にし、手動登録だけを許す。ルール作成・自動反映の根拠には転用しない。linkは既存実績への対応だけ許し、特殊取引を予定→実績へ昇格させることは阻止する。カード精算／返金等の解決そのものを本Issueで自動化しない。

### 5. 詳細処理・画面

#### 5.1 ルール管理と確認履歴からの作成

- 新規 `ImportClassificationRulesController#index/new/create/edit/update`。`resources :import_classification_rules, except: [:show, :destroy]`。設定／取込元／候補詳細からリンクする。
- 一覧は有効・無効、sourceのサービス・元口座、channel、取引先、収支、出力、priority、version、確認日時を表示。新規・編集で適用範囲と出力の要約を表示し、「この内容を今後再利用する」を未選択で表示。サーバ側でも明示確認パラメータを必須にする。有効化は別チェック。
- 候補詳細の「この確認内容からルールを作る」は、applied/linkedかつ対応実績が存在しsnapshotと一致、normal由来、原文merchantが有効、元口座一致、通常経路のmanual検証が成立したものだけ表示する。自動反映済み候補も元ルールと同じ根拠として識別する。未反映候補・AI提案から直接確定ルールを作らない。
- 作成フォームに値を初期表示するだけで、元候補ID・lock_version・実績snapshot digestの署名token（purpose=import_rule、30分）を添える。保存時Guard内で再検証。元データ変更・削除なら再プレビューを求める。
- 候補由来・手動新規の両フォームに、サーバ発行のUUID nonceを署名した作成token（purpose=import_rule_create、30分）を渡す。createはGuard内でnonceの既存ルールを確認し、なければ入力内容のdigestとnonceを新ルール行に同時保存する。既存ならdigestが同じ場合にそのルールを返し、異なる内容へのnonce転用は422で再確認を求める。DBのunique indexも併用し、応答喪失・並行送信でも1件にする。元候補eventは履歴用であり、nonceの唯一の保存先にしない。手動新規でも架空の文書・候補を作らない。
- 単発の候補修正・承認からルールを自動生成しない。手動新規も同じ確認フォームを使い、特殊取引用ルールは作成不可。

#### 5.2 初回抽出から判定まで

1. #67のImageReceiver文書受付・digest再送判定を維持。GeminiはGuard外で呼ぶ。
2. `commit_extraction` のGuard内でBuilderが原文・出典・draftを保存する。未知directionはnil、未知kindはunknownで保持し、expenseへの強制変換を廃止。
3. `Imports::RuleResolver.call(entry:, draft:)` が現在のsource/channelと原文条件で候補を求め、一致1件なら出力をdraftへ反映し、rule_decisionを保存。未確認のAIマスタは表示提案に留める。
4. 全行保存後、`Matcher.classify!` を実行。#67の重複／訂正／conflictの情報を優先して維持し、共通検証とルール保留理由は別metadataのreason_codesで併記。重複以外がnewでも、自動要件未達はheldにする。通常の手動approveは手動確認成立後に再判定してpendingにできるが、legacy_origin_unknown/user_heldは既存どおり明示操作を必要とする。
5. 文書state=extractedとextractedイベントを同一トランザクションで保存。文書途中失敗は全行rollbackする。以後は各候補単位で5.3を呼ぶ。

#### 5.3 自動反映と再実行

- `Applier::ACTIONS` に `auto_apply` を追加する。Webのresolve/bulk_approveからは受け付けず、内部ImageReceiverだけが指定する。controllerは許可する手動actionsを明示列挙し、文字列を無制限に中継しない。
- `Applier.call` の既存signatureを維持。auto_applyではattributes/target_id/tokenを拒否。Guard→文書→候補→identity等の既存ロック順序、終端／参照／conflictの優先判定、リトライ上限を維持する。
- auto_applyは最初のrule_decisionの一致ルールID/version/出力と、Guard下の現在の有効ルール・マスタ・候補・一般設定・source設定を照合。抽出後にルール変更／停止された場合は `rule_changed` として保留し、別ルールを再選択して自動適用しない。
- 最新Matcherとvalidatorのautomatic条件を再検証してからTransaction作成、target_snapshot、identity binding、appliedイベントを同一transactionでcommitする。イベントに `mode=automatic`、金額、rule snapshot、日付出典、判定根拠を残す。手動反映は `mode=manual`。自動に失敗したら候補と理由を残し、手動へ送る。
- 最初の判定時点でsource自動許可／一般設定が不許可なら、その候補は自動対象外と記録する。後から設定をONにしても遡及処理しない。候補作成後に利用者編集があった場合も自動対象外とする。
- 成功済み文書の再送では従来どおり過去候補を自動処理しない。内部auto_applyの再呼出しも終端判定で取引増加なし。extracted保存後・自動処理前に切断した候補は保留として画面へ残し、自動再開を追加しない。Jobでの自動再開は#70の対象。

#### 5.4 手動修正・承認

- 一覧／詳細で日付出典、kind、AI提案、ルール判定snapshot、保留理由を表示。category/payment/accountが埋まっていても未確定であることを示す。
- 承認操作は表示中の値を利用者が確認した操作として、date/amount/direction/category/payment/account/kindをconfirmation_metadataに保存する。日付を変更または「この日付を確認」にチェックした場合はdate_origin=user。未確定日付は空欄で、未指定のままの承認では補わない。kindのunknownをnormalに黙って変えない。
- kind/to_account_idはEDITABLE_ATTRIBUTESに追加するが、date_origin、metadata、rule_decision、承認日時をstrong parametersで受け入れない。サーバが実際の編集・明示確認から生成する。確認欄の値は別の許可パラメータとして受け付ける。
- `ImportEntriesController#preview` とbulk_approveの両方で編集前後・確認項目をイベント保存する。`ReviewToken.context` にmetadata digestとkind/to_account_idを加え、確認後の変更でtokenを無効にする。`Matcher` の重複結果やuser_held/legacy理由を失わない。
- `Applier#create_transaction` へmanual validationを追加。#67の同一／別取引／訂正版採用の確認フローを維持し、どのactionでもkindと整合性の制約を回避できない。link/acknowledgeは取引作成を伴わない場合でも特殊→予定昇格を阻止する。
- `Applier#link` は対象がplannedなら、ロック済み対象を基にentry_type=actualへ変更した保存後の投影を作り、`.transaction_reasons(..., context: :planned_promotion)` を実行する。候補draftの値で代用せず、対象のカテゴリ・支払経路等そのものを検証する。元候補の特殊kindによる昇格禁止も先に検証する。paidでの新規実績化は許可しない。transfer/investmentの予定は元候補で利用者が確認した移動種別と一致し、4.4の移動先・経路条件を満たす場合だけ実績化できる。
- 予定実績化の口座差は既存ReviewTokenで表示・確認したsourceとの口座差に限りmanualで許容し、その他の共通整合性条件は免除しない。category区分・payment route等が不正ならstatus=held、reason=`invalid_planned_target` と個別理由を返す。この失敗判定はdraft.save!/target.update!/bind!/event!より前に置き、そのresolve呼出しでは予定・候補・イベントを変更しない。画面に保留結果と対象予定を修正するリンクを表示する。修正後は既存tokenを再利用せず差分を再プレビューする。
- 既存actualへのlinkは既存実績の値を変更しない対応付けなので実績の再分類を強制しない。ただし値の差分・元候補の特殊kindを含む既存確認は維持する。

#### 5.5 一括日付指定

- 初回アップロード画面のmanual_date一括指定を、抽出後の対象選択＋プレビュー＋確定へ移す。アップロードPOSTにmanual_dateがあれば422で抽出後の指定方法を案内し、値を黙って無視しない。ImageReceiverのsignatureは維持してcontrollerからnilを渡す。過去文書のmanual_dateは履歴として維持する。
- 新規 `ImportDraftDatesController#preview/#update`（collection `POST /import_draft_dates/preview`、`PATCH /import_draft_dates`）。対象は明示選択した未処理の代表候補、上限100件。IDsを重複除去し、source／文書／行／店名／旧日付・出典→新日付の全対象を表示する。処理済み・参照候補・conflict混入、存在しないID、不正日付、100件超は全体を422とし、部分適用しない。
- previewはDB更新なし。署名tokenに対象ID集合、各候補lock_version、draft snapshot digest、metadata digest、新日付、nonceを含める（purpose=import_bulk_date、30分）。
- updateはGuard→文書ID順→候補ID順→draftのロックでtokenを再検証。全件dateを変更、date_origin=user、手動確認日時を付加、editedイベントを保存し、Matcherを全件再計算。変更後も自動反映はしない。変更結果と件数・対象リンクを表示する。1件でも古くなっていたら全件rollbackし再プレビューを求める。nonceイベントで二重送信は既存結果へ案内する。
- 単票での利用者指定日も同じ日付validationを利用。過去文書の明示manual_dateはuserとして解釈できるが、migrationで過去値の意味を推定せず、既存候補の出典はunresolvedとする。

#### 5.6 成功／保留の閲覧

- レビュー一覧の修正・承認フォームは未処理候補のみ。自動反映済みにはチェック欄や再承認を要求しない。自動成功が全件でも件数・収入合計・支出合計（符号を混ぜない）・適用ルール別内訳を表示する。
- `import_documents/_summary` と候補詳細にmode・rule snapshot・日付出典・全保留理由を表示。集計の元はappliedイベントの確定時amount/directionとし、後のdraft変更やルール変更で過去の自動処理実績を変えない。文書の既存新規／保留等集計も併記する。
- pending_document検索だけに依存せず、レビュー一覧に「要確認」「処理済み」の切替と履歴リンクを置く。defaultは要確認、document_idsを指定した直後は自動成功分もサマリ表示する。文書50件paginationを維持し、ruleとmasterの事前ロードで行単位の追加問い合わせを抑える。
- 新reason（rule_missing/ambiguous/invalid/changed、date_unresolved、extraction_evidence_missing/uncertain、special_transaction、payment_route_unconfirmed/mismatch、category_direction_mismatch、auto_apply_disabled等）をImportsHelperへ日本語表示として追加する。複数理由をrule_decision/metadataに保存し、ImportEntry.reason_codeは最も重要な既存重複理由を優先する。

#### 5.7 反映後の訂正

- applied/linked候補の詳細に「対応実績を訂正する」を設ける。新規 `ImportTransactionCorrectionsController#preview/#update`、`POST /import_entries/:import_entry_id/correction/preview`、`PATCH /import_entries/:import_entry_id/correction`。ルール編集・候補再承認と別操作。
- 対象実績ID・現在値・変更後・差分・この実績に関連する他の候補IDを表示する。対象が削除済みなら訂正不可。日付・direction・amount・category/payment/account/to_account・memo・credit_card_status・due overrideを許可し、entry_type/paid_on/target IDをクライアントから変更させない。
- 既存の支払済実績の訂正も対象。credit_card_status=paidはexpense＋payment_kind=credit_card＋bank口座、unpaidはcredit_pending、not_applicableは通常経路を検証する。source口座との違いは支払済訂正または明示した口座訂正の差分として確認する。通常新規取込のpaid禁止と区別する。paid_onは既存Transaction callbackで再算出し、プレビューの保存後予測値にも反映する。
- previewでTransactionのdupへ編集値を代入しvalidationとcallbackで正規化後のsnapshotを生成する（DB書き込みはしない。共通正規化メソッドをCreditCardPaymentCycle/Transactionから切り出し、callbackとpreviewで共用）。署名tokenにentry/target ID、現在の実績snapshot digest、全関連候補のversion、変更後snapshot、nonceを含める（purpose=import_correction、30分）。
- updateはGuard→文書→候補→実績の順でロックしsnapshotを再検証。Transaction更新とbefore/afterイベントを同一transactionで保存する。#67のTargetIntegrity callbackは全関連候補をconflictにする。訂正操作の起点候補は利用者が差分を確認したのでtarget_snapshotを新値へ更新して元のapplied/linked状態を維持し、他の候補はconflictのまま再確認を要求する。訂正の結果としてruleを作らない。
- イベントは訂正前のapplied snapshotを上書きしない。二重送信はnonceで前回の結果へ案内し再更新しない。通常のTransactionsController#updateからの編集は従来どおり#67のconflict確認を残す。

### 6. 対象ファイル・クラス・メソッド

| 対象（新規は新） | 実装単位・signature・参照 |
|---|---|
| `db/migrate/20261021000001_add_import_classification.rb`（新）/ `db/schema.rb` | 4章の新表・source/payment/draft列とFK/index。既存候補・実績不変 |
| `app/models/import_classification_rule.rb`（新） | 関連・範囲・出力validation、version加算、停止保持。物理削除なし |
| `app/models/{import_source,payment_method,category,account,setting}.rb` | 新属性validation、ruleとのrestrict関連、設定・master更新のGuard取得。masterのkind変更を読直しで検出。Accountはincoming_image_import_drafts（foreign_key: :to_account_id、class_name: ImageImportDraft、dependent: :restrict_with_error）も追加 |
| `app/models/image_import_draft.rb` | date_origin/kind/metadata/rule_decision、to_account関連。transaction_attributesはkind等の管理列を除きTransaction用属性だけ返す。resolved?を共通検証化 |
| `app/services/imports/merchant_key.rb`（新） | `.normalize(value)` → String/nil、4.1の厳密な共用正規化 |
| `app/services/imports/{rule_resolver,candidate_validator,transaction_kind_classifier}.rb`（新） | `.call(entry:, draft:)` / `.call(draft:, metadata:, mode:)` / `.call(payload:)`。CandidateValidatorは `.transaction_reasons(transaction:, context:)` も公開し、link先の保存後投影・訂正と共用。副作用と戻り値を分離しvalidator自体は永続化しない |
| `app/services/image_import_draft_builder.rb` | 既存build signature維持。strict日付・unknown方向・根拠保存→全行後ルール判定とMatcher。find_masterは提案用 |
| `app/services/gemini/transaction_extractor.rb` | RESPONSE_SCHEMA、prompt、valid_item?、型の正規化。既存HTTP・error handlingを維持 |
| `app/services/imports/{entry_recorder,fingerprint}.rb` | payload許可キー追加。source_digest算法維持。snapshotにto_account_id等を含める |
| `app/services/imports/{image_receiver,applier,matcher,review_token}.rb` | signatures維持、auto_apply分離、手動／自動validator、理由併記、確認tokenの拡張。類似判定の±7日・既存終端処理は維持 |
| `app/services/imports/{bulk_date_update,transaction_correction,rule_writer}.rb`（新） | `.preview(...)` / `.call(..., token:)`、Guard内書込み、専用purposeの署名・nonceイベントによる冪等化 |
| `app/controllers/import_classification_rules_controller.rb`（新） | index/new/create/edit/update、確認フォーム・strong params |
| `app/controllers/import_draft_dates_controller.rb`（新） | preview/update、全件一括・上限100 |
| `app/controllers/import_transaction_corrections_controller.rb`（新） | preview/update、対象実績の差分確認 |
| `app/controllers/{image_imports,image_import_drafts,import_entries,import_sources,settings,payment_methods}_controller.rb` | 日付導線、手動確認、auto_applyのHTTP拒否、sourceフラグ、payment kind設定 |
| `app/models/transaction.rb` / `app/models/concerns/credit_card_payment_cycle.rb` | 5.7の保存前正規化を副作用のないメソッドに分離してpreviewと共用。一般入力の結果は維持 |
| `app/views/import_classification_rules/*`（新）、`import_draft_dates/preview`（新）、`import_transaction_corrections/preview`（新） | 全範囲・差分・明示確認 |
| `app/views/{image_imports/new,image_import_drafts/index,import_entries/show,import_documents/_summary,import_sources/_form,payment_methods/_form,settings/edit}.html.erb`、`app/helpers/imports_helper.rb` | 5章の表示・導線と日本語理由。既存のimport_entries/_values・_comparisonを差分表示へ再利用 |
| `config/routes.rb` | 上記3 controller群の明示ルート。resolveで受けるactionを手動に限定 |
| `spec/support/{import_fixtures,import_concurrency}.rb` | metadata fixture、新表をFK順にcleanup、専用#68 DBだけ許可 |
| `spec/models/*` / `spec/services/imports/*` / `spec/requests/*` | 10章。既存specの当日補完・名称一致のみの自動成功期待は新仕様へ変更 |
| `docs/要件定義書.md` / `docs/アプリケーション仕様書.md` | 実装時に自動化条件・例外・日付・ルール管理を現物に合わせ更新 |

追加メソッドの戻り値はreason_codes、before/after、matched_rules、statusを持つ値オブジェクトに統一する。controllerに判定ロジック・Transaction直接生成を分散させない。サービス追加は取引作成／ルール更新／一括日付／訂正の責務で分ける。

### 7. DB・トランザクション・移行

- 新規migrationはMySQL/PostgreSQLの両方で動作させる。新表・index・FKは存在確認を行い、DDLがtransaction外のMySQLで中断しても再実行できるようにする。json列はNULL可追加→既存行を空Hashにbackfill→NOT NULL化とし、DB固有json defaultに依存しない。新規モデルも空Hashを明示初期化する。
- `image_import_drafts.direction` の現行NOT NULL制約を外し、defaultのexpense(1)もNULLへ変更する。既存のdirection値は維持する。Builderは不明を明示nilで保存し、その他のdraft生成も暗黙の支出初期値へ依存させない。Transaction.directionのNOT NULLは維持し、validatorで未確定directionの反映を阻止する。
- 既存draft.date/amount/direction/master IDs・文書manual_date・payload・digest・target snapshot・実績を変更しない。date_origin=unresolved、kind=unknown、metadata/rule_decision={}で初期化し、既存未処理候補は手動確認へ送る。反映済み候補は終端維持。ルールは0件、source自動化false、payment kind=unknownで導入する。
- `image_import_drafts.to_account_id` はNULL可FK、index。Account側にも `has_many :incoming_image_import_drafts, class_name: "ImageImportDraft", foreign_key: :to_account_id, dependent: :restrict_with_error` を置く。移動先参照だけを持つ口座でも既存AccountsControllerのdestroy失敗分岐で理由付き拒否とし、未処理・却下済み等を問わず履歴を保持する。ImportClassificationRuleの参照先マスタもrestrictで削除事故を防ぐ（Account/Category/PaymentMethod/ImportSourceからhas_many dependent restrict_with_error）。confirmation_entryは削除されない履歴参照。
- Guardを取る更新対象はルール・source設定・一般承認設定・経路整合性に関わるmasterの更新／削除と取引反映。すべてGuard先行、必要な文書／候補はID昇順、Transactionはその後。Guard中に外部API呼出しをしない。
- 既存Applierの一時DB例外リトライ・接続断後の終端再確認を維持。新操作の一意nonce判定と更新もGuard内で行い、成功イベント込みでcommit。callbackからGuardを再取得する場合は既存と同一transactionで再入する。
- migrationのdownは新ルール・判断履歴を失うため自動撤去を拒否するIrreversibleMigrationとし、未導入DBでのみ破棄可能な開発手順を別に示す。本番や共用DBを検証に使わない。

### 8. 外部連携・Job・ファイル

Geminiへの送信は既存の画像抽出時のみ。実際のAPIキー・API応答本文・画像をログやレビュー資料へ転記しない。ルールの管理情報や過去実績を追加で外部送信しない。Job・定期実行・CSV連携を追加しない。画像再送で自動再解析しない#67の契約を維持する。schema/promptはローカルのモックHTTPで検証し、課金を伴う実通信は実装テストの条件にしない。

### 9. 例外・境界条件

- 未知店舗／原文merchantなし／ルール未設定は保留。別source・別元口座の同名店は一致しない。見えているAI候補を利用者が確認すれば、その1件だけmanual登録できる。
- 競合・多重一致・全停止は自動反映しない。編集済み候補に将来のルール変更を上書きしない。既存候補へルール再適用の自動ボタンは設けない。
- 不正日付、空日付、年なし、非整数・巨大額、カテゴリ不一致、credit_pendingと現金等の矛盾、paidの新規取込はすべて保留。draft保存と実績反映の可否を分け、後から修正可能にする。
- 特殊kind・不明kindはルールが一致しても自動化しない。元データの特殊情報をmemo編集で消して自動化することを防ぐ。
- プレビュー後の候補編集、実績変更／削除、master変更、rule変更、期限切れ、token改変、異なるpurposeは無更新で再確認へ。新操作はRecordInvalid/ArgumentError/StaleObjectErrorを422または再プレビュー案内に変換し、途中commitしない。
- 確定済み・参照候補へ二重送信してもTransactionとイベントの確定数は増やさない。自動設定ON後の再送も既存結果を返すだけ。
- HTML表示はERB標準escape、merchant/AI根拠にhtml_safeを使わない。強いパラメータで制限し、HTTPからmetadata・ルール判定・auto_apply・target IDを注入できない。

### 10. テスト方針

本フェーズは文書のみでアプリテスト未実行。以下は実装フェーズの必須検証であり、成功済みの記録ではない。

| ID | 対象・入力 | 期待結果 |
|---|---|---|
| T1 | rule model/resolver：同名店×別source・別元口座・収支・channel、支店名差、Unicode空白、大文字、255文字超 | 範囲外へ波及せず、定義した正規化の完全一致だけ再利用 |
| T2 | rule writer/requests：単発修正、未反映・特殊候補、実績から明示作成、未確認checkbox、期限切れ、範囲変更；元候補のない手動新規も含む二重送信・並行送信・応答喪失後の再送・nonce内容改変 | 自動学習なし、確認済み対象だけ作成、同一nonceは同じルール、内容違いは422、二重作成なし |
| T3 | ルール0/1/複数、有効／無効、異なる優先度・同じ出力の複数一致、マスタ変更 | 複数一致はすべてheld。理由・全一致・priority・snapshotを表示 |
| T4 | 一般承認true/false×sourceフラグtrue/false、旧false移行、設定OFFの並行commit | 両許可がある新規候補だけ自動化。停止commit後に自動反映なし |
| T5 | validator/applier全新規actions：正整数範囲、category kind、payment kind×account kind×status、due override、元口座不一致；link先予定の正常値／収支とcategory.kind不一致／現金方法＋銀行口座／不正クレカ状態／移動先欠落 | 不整合をmanual/distinctでも阻止。明示差分確認した口座訂正だけmanual許可。正常な予定だけactual化し、異常な予定へのlinkは取引・候補・イベントを無変更でheld結果と修正先リンクを返す。予定修正後の旧tokenは無効 |
| T6 | strict date：閏年・不正日・年なし・相対日・rawとISO不一致・日付境界・未確定；一括0/1/100/101件・処理済混入・stale・連打 | 当日補完なし。出典を表示。一括は無更新preview→全件成功か全件rollback |
| T7 | 全kind、unknown direction、正常行＋direction不明行の同画像混在、特殊語とnormalの矛盾、証拠欠落、不確実性、AIの正しいマスタ名だけ | 不明directionはnilのまま候補保存し正常行も保持。特殊は自動反映なし、手動transfer/feeは要件を満たして登録、settlement/refundの推測処理なし |
| T8 | 自動10件＋保留、全件自動成功、収入支出混在、後からルール変更 | 個別承認0、件数・方向別金額・rule別履歴が確定時の値で閲覧可能 |
| T9 | ルール変更・停止・再有効化、抽出→反映間のversion変更、成功画像の再送、既存未処理候補 | 過去実績・編集済候補不変、再送・設定変更で遡及反映なし |
| T10 | 反映後訂正のpreview/update、paid/unpaid・override正規化、実績削除・他候補も同一実績・token連打 | before/after一致、起点のみ確認維持・他候補conflict、元applied履歴不変 |
| T11 | #67再実行・外部ID訂正・参照候補・同画像並行・別画像類似並行・自動と手動同時 | 二重登録なし。既存の±7日・source・終端・conflict・rollback維持 |
| T12 | MySQL/PostgreSQLでmigration/schema両構築、既存draft/実績fixture、DDL途中再開、default設定、移動先だけに参照される未処理／処理済み／却下済み候補の口座削除request | 既存値不変・directionのNULL許可と暗黙支出default廃止、FK/index成立、理由付き削除拒否で候補・口座保持、全RSpec成功 |

- 新規model/service/request specを追加し、Builder・Extractor・ImageReceiver・Applier・ReviewToken・履歴／マスタ削除の既存specを更新する。実DBのモデルを使い、GeminiのHTTP境界だけモックする。判定関数を丸ごとモックして成功扱いにしない。
- 並行specは既存 `ImportConcurrency` を明示requireしてQueue/barrier方式を使う。共有開発DBを避け、許可した使い捨てDB `budget_book_app_test_68` のみで実施。cleanupに新表・関連を追加して既存fixtureを削除しない。
- 実装時の主コマンド: `RAILS_ENV=test bundle exec rspec`、新規サービス／requestの個別RSpec、`git diff --check`、変更Rubyの `ruby -c`。DB接続情報は値を表示せず専用環境に設定する。MySQL/PostgreSQLそれぞれmigration構築とschema構築で全RSpecを行い、既存pendingを識別して保存する。
- 親#65の操作削減比較は、確認済みルール10件のキャッシュレス通常取引で、初期設定後の分類再選択0・個別承認0を検証する。画像取得／アップロードは残るため回数不変と明記。現金3件・定期1件・引落1件・残高1回は本Issueの自動化対象外で改善件数に加算しない。初回ルール設定・支払種別設定の操作数は別途記録する。
- 同じ10件の画像・同じ初期マスタで、基点mainの承認必須運用と導入後の明示許可済み継続運用を比較し、「支出ごとの入力回数」「再選択項目数」「ファイル取得・アップロード回数」「正常データの承認件数」「必要画面数」の5指標を導入前後とも `docs/issue_68/操作削減検証.md` に実測保存する。入力回数は取引別フォームへの入力回数、再選択は分類／支払方法／口座の選び直した項目数、必要画面数は取込開始から登録結果確認までに実際に開いた画面数と定義する。0と推定せず、画像取得と取込元の選択・結果閲覧も数える。初回設定の各操作は別表に保存する。

### 11. 後方互換性・回帰リスク

安全側への変更として、旧一般設定が承認不要でもsource許可とルール確認がなければ自動登録されなくなる。導入時の説明にこの挙動と支払方法kindの設定を明示する。取込の日付欠落は未確定になり、旧当日補完のspecは変更する。

既存実績の読み出し・集計、旧payload/digest、#67の再送・外部ID・比較・履歴、通常の取引編集・クレカ精算は維持する。日付出典の旧値を推定して確定させず、新経路からの再反映もしない。種別・日付・根拠のJSONは版を含む最小schemaを定義し、不明版は手動確認へ落とす。

主な回帰リスクはMatcherとmanual/automatic検証の相互作用、既存ReviewToken、クレカcallbackと訂正プレビューの一致、Guardとマスタ更新のロック順序。T5/T10/T11と全RSpec、両DB構築で検証する。ルール停止だけで過去実績が変わらないことを明示assertする。

### 12. レビュー状態

- Technical Reviewer: REVIEWING
- Consistency Reviewer: REVIEWING
- レビューは新規の専用Reviewer 2体を並列で起動し、最大3 Round。両PASSが揃った時点で詳細設計を確定し、実装へ進まず停止する。3 Roundで未収束なら未解決指摘を記録して停止する。
