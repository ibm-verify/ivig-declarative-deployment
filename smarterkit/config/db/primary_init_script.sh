#!/bin/bash
# Copyright IBM Corp. 2026
# SPDX-License-Identifier: MIT

set -e

mkdir -p /var/lib/postgresql/data/isvgim{data,indexes}
echo "$(date -Is) - Running init script the 1st time Primary PostgreSql pod is created...";
if [ "$POSTGRES_USER" = "$PG_ISVGIM_USER" ]; then
  echo "User $POSTGRES_USER already exists"
else
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
CREATE USER "$PG_ISVGIM_USER" WITH PASSWORD '$PG_ISVGIM_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE "$POSTGRES_DB" to "$PG_ISVGIM_USER";
EOSQL
fi

echo "$(date -Is) - Init script is completed";
