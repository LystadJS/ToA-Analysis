#!/usr/bin/env bash
# Run in the current shell with: source scripts/start-postgres.sh
# Commands use the repository-local cluster through a private Unix socket.
toa_start() {
  local root data socket db
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd) || return
  data="$root/.toa/pgdata"
  socket="$root/.toa/socket"
  mkdir -p "$socket" || return
  chmod 700 "$socket" || return
  export PGHOST="$socket" PGPORT=55432 PGUSER="$(id -un)"
  if [[ ! -s "$data/PG_VERSION" ]]; then
    initdb -D "$data" --encoding=UTF8 --locale=C --auth-local=peer --auth-host=scram-sha-256 >/dev/null || return
  fi
  if ! pg_ctl -D "$data" status >/dev/null; then
    pg_ctl -D "$data" -l "$root/.toa/postgres.log" -o "-k '$socket' -p $PGPORT -c listen_addresses=''" -w start || return
  fi
  for db in toa_us toa_china; do
    if [[ $(psql -XAt -v ON_ERROR_STOP=1 -d postgres -c "select count(*) from pg_database where datname='$db'") == 0 ]]; then
      createdb "$db" || return
    fi
    psql -XqAt -v ON_ERROR_STOP=1 -d "$db" -c 'select current_database()' || return
  done
}
toa_start
