#!/bin/sh
set -e

: "${PGDATA:=/var/lib/postgresql/data}"
: "${POSTGRES_USER:=postgres}"
: "${POSTGRES_DB:=${POSTGRES_USER}}"
: "${POSTGRES_HOST_AUTH_METHOD:=}"

# Support Docker secrets via _FILE suffix
file_env() {
  local var="$1"
  local def="${2:-}"
  local fileVar="${var}_FILE"
  local val="$def"
  if [ -n "${!var:-}" ] && [ -n "${!fileVar:-}" ]; then
    echo "error: both $var and $fileVar are set" >&2
    exit 1
  fi
  if [ -n "${!var:-}" ]; then
    val="${!var}"
  elif [ -n "${!fileVar:-}" ]; then
    val="$(cat "${!fileVar}")"
  fi
  export "$var"="$val"
  unset "$fileVar"
}

file_env 'POSTGRES_PASSWORD'
file_env 'POSTGRES_USER' 'postgres'
file_env 'POSTGRES_DB' "$POSTGRES_USER"
file_env 'POSTGRES_INITDB_ARGS'

if [ "$(id -u)" = '0' ]; then
  # Ensure directories exist with correct ownership
  mkdir -p "$PGDATA" /run/postgresql
  chown postgres:postgres "$PGDATA" /run/postgresql /var/lib/postgresql
  chmod 700 "$PGDATA"
  chmod 3775 /run/postgresql
  ln -sf /run /var/run

  exec su-exec postgres "$0" "$@"
fi

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  # Validate environment
  if [ -z "$POSTGRES_PASSWORD" ] && [ "$POSTGRES_HOST_AUTH_METHOD" != "trust" ]; then
    cat >&2 <<-'EOF'
      Error: Database is uninitialized and no password is set.
      Set POSTGRES_PASSWORD or use POSTGRES_HOST_AUTH_METHOD=trust (not recommended).
		EOF
    exit 1
  fi

  # Initialize database cluster
  if [ -n "$POSTGRES_PASSWORD" ]; then
    initdb --username="$POSTGRES_USER" --pwfile=<(printf '%s\n' "$POSTGRES_PASSWORD") $POSTGRES_INITDB_ARGS -D "$PGDATA"
  else
    initdb --username="$POSTGRES_USER" $POSTGRES_INITDB_ARGS -D "$PGDATA"
  fi

  # Configure postgresql.conf
  cat >> "$PGDATA/postgresql.conf" <<-'CONF'
listen_addresses = '*'
port = 5432
shared_preload_libraries = 'pg_cron, pg_duckdb, pg_tle, pg_net, safeupdate'
# To schedule jobs in a specific database, add a line like:
# Defaults to 'postgres' if not set.
# cron.database_name = 'your_database_name'
CONF

  # Configure pg_hba.conf — trust for local sockets, configurable for remote
  {
    echo "local all all peer"
    echo "host all all 127.0.0.1/32 trust"
    echo "host all all ::1/128 trust"
    if [ -n "$POSTGRES_HOST_AUTH_METHOD" ]; then
      echo "host all all all $POSTGRES_HOST_AUTH_METHOD"
    else
      # Default to scram-sha-256 if password set, otherwise trust
      if [ -n "$POSTGRES_PASSWORD" ]; then
        echo "host all all all scram-sha-256"
      else
        echo "host all all all trust"
      fi
    fi
  } > "$PGDATA/pg_hba.conf"

  # Create the specified database
  if [ "$POSTGRES_DB" != "$POSTGRES_USER" ]; then
    postgres --single -D "$PGDATA" -c "CREATE DATABASE \"$POSTGRES_DB\";" >/dev/null
  fi

  # Run init scripts
  if [ -d /docker-entrypoint-initdb.d ]; then
    for f in /docker-entrypoint-initdb.d/*; do
      case "$f" in
        *.sh)
          if [ -x "$f" ]; then
            "$f"
          else
            . "$f"
          fi
          ;;
        *.sql)
          postgres --single -D "$PGDATA" -d "$POSTGRES_DB" < "$f" >/dev/null
          ;;
        *.sql.gz)
          gunzip -c "$f" | postgres --single -D "$PGDATA" -d "$POSTGRES_DB" >/dev/null
          ;;
        *.sql.xz)
          xzcat "$f" | postgres --single -D "$PGDATA" -d "$POSTGRES_DB" >/dev/null
          ;;
        *.sql.zst)
          zstd -dc "$f" | postgres --single -D "$PGDATA" -d "$POSTGRES_DB" >/dev/null
          ;;
      esac
    done
  fi
fi

exec "$@"
