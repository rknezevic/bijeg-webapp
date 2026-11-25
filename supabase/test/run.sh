#!/usr/bin/env bash
# Runs the migration + full game simulation on a local Postgres (needs unaccent/fuzzystrmatch).
set -e
P="psql -h ${PGHOST:-/tmp/pgtest} -p ${PGPORT:-5499} -U postgres -v ON_ERROR_STOP=1 -q"
D="$(cd "$(dirname "$0")" && pwd)"
$P -c "drop database if exists bijeg_test" -c "create database bijeg_test" 2>&1 | grep -v NOTICE || true
$P -d bijeg_test -f "$D/mock_supabase.sql" 2>&1 | grep -vi wal || true
for f in "$D"/../migrations/*.sql; do $P -d bijeg_test -f "$f" 2>&1 | grep -v NOTICE || true; done
$P -d bijeg_test -f "$D/simulate_game.sql"
$P -d bijeg_test -c "truncate public.questions restart identity cascade" -f "$D/../seed.sql" -f "$D/check_questions.sql"
