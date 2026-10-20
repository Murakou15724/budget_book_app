## 確認範囲
- GitHub Issue #67・親Issue #65本文、承認済み詳細設計コメント `6262287659`
- 基点 `833c3f43d36e4426edfb1568ff0e13971056fa2a` からの差分、Git状態、未追跡の実装・spec
- `app/services/imports/*.rb`、取込関連モデル・Controller・View、Transaction関連変更
- migration、schema、設定変更、`docs/アプリケーション仕様書.md`
- 取込関連model/service/request specとテスト補助コード
- 提示された両DBの実行ログ：各227 examples、0 failures、8 pending。レビュー中のテスト実行なし

## トレーサビリティ
- 出所・処理結果の追跡 → 設計3・4・9節 → EntryRecorder、文書summary → import_history_spec
- 再送・二重承認・途中失敗・並行処理 → 設計6節 → ImageReceiver、Applier → Receiver/Applier/Concurrency spec。ただし後発保留の並行検証とschema構築検証に不足
- 確かな外部IDと訂正 → 設計4・5節 → EntryRecorder、Applier → 同内容再取込・別口座／service・訂正版採用spec
- 正当な同額複数件・類似の利用者判断 → 設計5節 → Matcher、Applier → 同日・同額・同店舗の別取引spec。比較snapshot表示に不足
- 手入力・予定との対応 → 設計5・9節 → Applier → 手入力link、予定実績化spec
- 保留停止・既存変更／削除・再処理 → 設計5節 → Matcher、TargetIntegrity → Applier/EntryRecorder spec。保留理由喪失の経路は未検証
- 四分類・理由・元候補への対応 → 設計9節 → ImportEntry、summary → history spec。訂正／保留の排他集計を直接検証するspecはなし
- 月跨ぎ・競合・移行等 → 設計8・10節 → migration、Matcher → 月跨ぎ・マスタ削除・Guard spec。schemaロード構築の両DB検証は未提示

## 指摘

### [MAJOR]-1 明示保留・旧候補の停止理由が類似判定で失われる
- 箇所: `app/services/imports/matcher.rb:20`、`:22`、`:47`
- 根拠: 設計5.2節「保留…自動反映も通常の一括承認も実行しない」、1節「保留・訂正・矛盾・旧候補は停止する」。
- 問題: user_held／legacy_origin_unknownに類似対象があると通常承認で理由がsimilar_candidatesに置換される。比較先の却下・削除後、次の通常承認でnew+pendingとなり登録できる。
- 修正方針: 明示保留・legacy由来の停止条件を類似理由と独立して保持する。類似あり→通常承認→比較対象解消→再承認のspecを両状態について追加する。

### [MAJOR]-2 異文書の並行自動反映を検証するspecが設計のシナリオを実行していない
- 箇所: `spec/services/imports/concurrency_spec.rb:36`
- 根拠: 設計6.3節「後発が先行Transactionを認識し保留になる」、10節「同時異文書の自動反映で後発保留」。
- 問題: 現specは両候補を事前登録し両方held・取引増加0件を期待するため、画像受付・抽出・自動反映の競合で先行だけ反映する経路を検証していない。設定falseのReceiver specは既存画像再送停止だけ。
- 修正方針: 別source・同口座の異文書で抽出保存と自動反映を含む独立connectionの競合を制御し、取引1件・後発保留を検証する。承認不要設定で問題なしの新規だけ反映し、held／correction／conflictが停止する検証も追加する。

### [MAJOR]-3 必須のschemaロード構築による両DB検証が完了していない
- 箇所: `spec/models/import_guard_spec.rb:4`、`spec/services/imports/concurrency_spec.rb:48`
- 根拠: 設計10節はmigration構築とschema:load構築の両方を必須としている。依頼時点で手動実行依頼中。
- 問題: 既存DBからGuardを削除するspecだけでは、schemaから構築したDBでの成功証跡にならない。
- 修正方針: 専用MySQL／PostgreSQLをschemaから構築し、Guard初期0件、通常取引の初回保存、初期化競合、同候補の同時承認、rollback後の再作成を検証して記録する。

### [MINOR]-4 「別取引」の確認画面に比較対象のsnapshotが表示されない
- 箇所: `app/views/import_entries/_comparison.html.erb:2`、`app/views/import_entries/show.html.erb:45`
- 根拠: 設計5.2節「比較対象のid・snapshotを表示して『別取引として登録』を選べる」。
- 問題: target未指定の別取引プレビューでは、比較対象は日付・金額・メモ・入力区分程度で、tokenに含めるカテゴリ・支払方法・支払状況等のsnapshotを確認できない。
- 修正方針: 比較対象Transaction／未処理候補のsnapshotを表示し、request specで検証する。

RESULT: FAIL
