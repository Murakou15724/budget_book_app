#!/usr/bin/env bash
set -euo pipefail
cd /home/murakamiko/projects/budget_book_app
export RAILS_ENV=test IMPORT_TEST_DATABASE=budget_book_app_test_69 BUDGET_BOOK_APP_DATABASE_HOST=127.0.0.1
export BUDGET_BOOK_APP_DATABASE_PASSWORD=''
unset DATABASE_URL MY_APP_DATABASE_URL
export IMPORT_TEST_ADAPTER="$1"
export SCHEMA="/tmp/budget-book-69-validation/${IMPORT_TEST_ADAPTER}-schema.rb"
shift
case "$IMPORT_TEST_ADAPTER" in
  mysql2) export BUDGET_BOOK_APP_DATABASE_PORT=13369 BUDGET_BOOK_APP_DATABASE_USERNAME=root ;;
  postgresql) export BUDGET_BOOK_APP_DATABASE_PORT=15369 BUDGET_BOOK_APP_DATABASE_USERNAME=murakamiko ;;
  *) exit 2 ;;
esac
exec bundle exec "$@"
