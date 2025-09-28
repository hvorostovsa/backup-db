#!/bin/sh
set -eu

LOG_FILE=/backups/backup.log

# check DB connection 
echo "checking database connection..." >> "$LOG_FILE"
if pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -q; then
    echo "[$(date +"%Y-%m-%d_%H-%M-%S")] INFO: Initial database connection successful." >> "$LOG_FILE"
else
    error_message=$(pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" 2>&1)
    echo "[$(date +"%Y-%m-%d_%H-%M-%S")] WARNING: Initial database connection failed. Will retry on schedule. Details: $error_message" >> "$LOG_FILE"
fi

do_backup() {
   DEST_DIR=/backups
  mkdir -p "$DEST_DIR"
  STAMP=$(date +"%Y-%m-%d_%H-%M-%S")
  OUT="$DEST_DIR/all_${STAMP}.sql.gz"

  echo "[$STAMP] INFO: starting backup -> $OUT" >> "$LOG_FILE" || true

  echo "[backup] start host=$PGHOST port=$PGPORT user=$PGUSER -> $OUT" >&2

  if pg_dumpall -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" | gzip -9 > "$OUT"; then
    echo "[backup] done: $OUT" >&2
    echo "[$STAMP] INFO: done -> $OUT" >> "$LOG_FILE" || true
    return 0
  else
    echo "[backup] ERROR: pg_dumpall failed" >&2
    rm -f "$OUT"
    echo "[$STAMP] ERROR: backup failed" >> "$LOG_FILE" || true
    return 1
  fi
}

if [ "${1:-}" = "run" ]; then
  do_backup
  exit $?
fi

# Setup cron 
CRON_SCHEDULE="${CRON_SCHEDULE:-* 3 * * *}"  # default
CRON_FILE=/etc/cron.d/pg-backup

echo "[entrypoint] Setting up daily backup with schedule: $CRON_SCHEDULE" >&2

{
  echo "SHELL=/bin/sh"
  echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  echo "TZ=${TZ:-UTC}"
  echo "PGHOST=$PGHOST"
  echo "PGUSER=$PGUSER" 
  echo "PGPASSWORD=$PGPASSWORD"
  echo "PGPORT=$PGPORT"
  echo "$CRON_SCHEDULE root /bin/sh /usr/local/bin/backup_entrypoint.sh run >> /proc/1/fd/1 2>&1"
  echo ""
} > "$CRON_FILE"

chmod 0644 "$CRON_FILE"
echo "[entrypoint] Installed cron file: $CRON_FILE" >&2

echo "[entrypoint] Starting cron daemon..." >&2
exec cron -f