#!/usr/bin/env bash
set -euo pipefail
cd /home/murakamiko/projects/budget_book_app
export RAILS_ENV=test IMPORT_TEST_DATABASE=budget_book_app_test_68 BUDGET_BOOK_APP_DATABASE_HOST=127.0.0.1
export BUDGET_BOOK_APP_DATABASE_PASSWORD=''
unset DATABASE_URL MY_APP_DATABASE_URL
export IMPORT_TEST_ADAPTER=mysql2 BUDGET_BOOK_APP_DATABASE_PORT=13368 BUDGET_BOOK_APP_DATABASE_USERNAME=root
bundle exec ruby /tmp/budget-book-68-validation/verify_migration.rb > /tmp/budget-book-68-validation/mysql-migration-preservation.log 2>&1
export IMPORT_TEST_ADAPTER=postgresql BUDGET_BOOK_APP_DATABASE_PORT=15368 BUDGET_BOOK_APP_DATABASE_USERNAME=murakamiko
bundle exec ruby /tmp/budget-book-68-validation/verify_migration.rb > /tmp/budget-book-68-validation/postgres-migration-preservation.log 2>&1
echo 'Both dedicated database migration/schema validations completed.'
