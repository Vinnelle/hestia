# shellcheck shell=sh
set -eu

export RESTIC_CACHE_DIR=/tmp/restic-cache

restic cat config >/dev/null 2>&1 || restic init

restic backup /data --host pv-backup

restic forget --host pv-backup --keep-daily 7 --prune

restic check
