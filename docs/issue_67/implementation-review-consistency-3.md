## 確認範囲
- GitHub Issue #67 本文、承認済み詳細設計コメント `6262287659`
- 基点 `833c3f43d36e4426edfb1568ff0e13971056fa2a` の差分、未追跡の取込関連実装・spec
- 取込モデル、Fingerprint／EntryRecorder／Matcher／ImageReceiver／Applier／ReviewToken／TargetIntegrity
- 取込候補Controller・詳細画面、取引書込み変更、移行コード、仕様書差分
- 取込関連model／service／request spec、並行検証補助
- 提示されたMySQL／PostgreSQLの全件ログ：各255 examples、0 failures、8 pending
- 作業開始前から存在する `.github/workflows/keep_alive.yml` と `docs/明細取得方式調査_66.md` は対象外

## トレーサビリティ
- 出所・処理結果の追跡 → 設計§3・4・9 → `app/services/imports/entry_recorder.rb:23`、`app/services/imports/applier.rb:141` → `import_history_spec.rb`、`import_tracking_spec.rb`
- 再送・二重承認・並行処理・途中失敗 → 設計§6 → `app/services/imports/image_receiver.rb:66`、`app/services/imports/applier.rb:17` → `image_receiver_spec.rb`、`concurrency_spec.rb`、`applier_edges_spec.rb`
- 外部IDの同一性・訂正 → 設計§4・5.2 → `app/services/imports/entry_recorder.rb:13`、`app/services/imports/applier.rb:86` → `entry_recorder_spec.rb`
- 正当な同額複数件・類似候補の利用者判断 → 設計§5.1・5.2 → `app/services/imports/matcher.rb:38`、`app/services/imports/applier.rb:92` → `applier_spec.rb`「同日・同額・同店舗の2行を残し…」
- 手入力・予定との対応確認 → 設計§5.2・9 → `app/controllers/import_entries_controller.rb:46`、`app/services/imports/applier.rb:108` → `import_entry_resolution_spec.rb`、`applier_spec.rb`
- 保留停止・確定結果の維持・変更削除検知 → 設計§5.3 → `app/services/imports/applier.rb:43`、`app/services/imports/target_integrity.rb:5` → `applier_edges_spec.rb`、`import_credit_card_integrity_spec.rb`
- 件数・理由・元候補への対応 → 設計§9 → `app/models/import_entry.rb:35`、`app/views/import_entries/show.html.erb:1` → `import_history_spec.rb`
- 月跨ぎ・競合・移行等の検証 → 設計§8・10 → `db/migrate/20261019000002_create_import_tracking.rb:88`、`app/models/import_guard.rb:3` → `applier_edges_spec.rb`、`concurrency_spec.rb`。実DB再構築・旧候補移行の検証結果は未完了

## 指摘
### [MAJOR]-1 両DBの再構築・旧候補移行について、設計が要求する検証結果が未確定
- 箇所: `db/migrate/20261019000002_create_import_tracking.rb:99`、`spec/services/imports/concurrency_spec.rb:50`
- 根拠: 詳細設計§10は、MySQL／PostgreSQLそれぞれでmigration構築とschemaロード構築の両方、および旧候補の件数・再実行・NOT NULL・既存取引不変を確認することを要求している。
- 問題: 全件RSpecの成功は確認できるが、専用DB再構築・旧候補移行の確認は未完了と提示されている。既存DBでのspec成功だけでは、この受入条件を満たしたと判定できない。
- 修正方針: 専用使い捨てDBで両構築経路と旧候補移行検証を完了し、実行コマンド・結果・検証項目の証跡を提示する。現時点でコード修正を要求する指摘ではない。

RESULT: FAIL
