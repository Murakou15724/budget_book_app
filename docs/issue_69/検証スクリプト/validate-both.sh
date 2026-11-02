#!/usr/bin/env bash
set -euo pipefail
cd /home/murakamiko/projects/budget_book_app
validation_root=/tmp/budget-book-69-validation
script_root=docs/issue_69/検証スクリプト
result_root=docs/issue_69/検証結果
mkdir -p "$validation_root" "$result_root"
git show 81123fa8f054e2f5f1686cd242e34f06338c9737:db/schema.rb > "$validation_root/baseline-schema.rb"
for adapter in mysql2 postgresql; do
  bash "$script_root/test.sh" "$adapter" rails db:create db:migrate > "$validation_root/$adapter-initial-migration.log" 2>&1
  status=0
  bash "$script_root/test.sh" "$adapter" ruby "$script_root/verify_migration.rb" > "$validation_root/$adapter-preservation.log" 2>&1 || status=$?
  for artifact in "$adapter-initial-migration.log" "$adapter-preservation.log" "$adapter-migration-final.log" "$adapter-schema-final.log" "migration-$adapter.json"; do
    if [ -f "$validation_root/$artifact" ]; then cp "$validation_root/$artifact" "$result_root/$artifact"; fi
  done
  if [ "$status" -ne 0 ]; then echo "$adapter validation failed: $result_root/$adapter-preservation.log"; exit "$status"; fi
done
echo "Both adapters: migration/schema full RSpec and DDL preservation validation completed."
