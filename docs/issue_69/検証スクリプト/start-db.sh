#!/usr/bin/env bash
set -euo pipefail
validation_root=/tmp/budget-book-69-validation
mkdir -p "$validation_root/mysql"
if [ ! -d "$validation_root/mysql/mysql" ]; then
  /usr/sbin/mysqld --no-defaults --initialize-insecure --datadir="$validation_root/mysql" --log-error="$validation_root/mysql-init.log"
fi
if [ ! -f "$validation_root/mysql.pid" ] || ! kill -0 "$(cat "$validation_root/mysql.pid")" 2>/dev/null; then
  /usr/sbin/mysqld --no-defaults --datadir="$validation_root/mysql" --socket="$validation_root/mysql.sock" --port=13369 --bind-address=127.0.0.1 --pid-file="$validation_root/mysql.pid" --log-error="$validation_root/mysql.log" --mysqlx=0 --innodb-buffer-pool-size=64M --max-allowed-packet=64M --daemonize
fi
pg_exec="$validation_root/pg-bin/usr/lib/postgresql/16/bin"
if [ ! -d "$validation_root/pg-data" ]; then
  "$pg_exec/initdb" -D "$validation_root/pg-data" -A trust --no-locale -E UTF8 > "$validation_root/pg-init.log"
fi
if ! "$pg_exec/pg_ctl" -D "$validation_root/pg-data" status > /dev/null; then
  "$pg_exec/pg_ctl" -D "$validation_root/pg-data" -l "$validation_root/postgres.log" -o "-p 15369 -k $validation_root -h 127.0.0.1" start
fi
