# shellcheck shell=sh
set -eu

# Client-side-encrypted backup: restic encrypts and deduplicates before
# anything leaves the pod, so R2 only ever stores ciphertext. Repository
# location and password come from RESTIC_REPOSITORY / RESTIC_PASSWORD (R2
# uses path-style addressing; restic's minio client applies it automatically
# for non-AWS endpoints).
#
# NOTE: this is still a file-level copy of live data. sqlite DBs (authelia,
# netbird, dashboard) are read mid-write and may not be crash-consistent —
# restores should expect to run an integrity check. Runs at 03:00 when write
# traffic ~0.

export RESTIC_CACHE_DIR=/tmp/restic-cache

# first run against an empty bucket prefix: create the repository
restic cat config >/dev/null 2>&1 || restic init

# --host pins the snapshot host so retention grouping doesn't fragment across
# per-run pod names
restic backup /data --host pv-backup

# 7 daily snapshots, same retention the dated-folder scheme had; prune drops
# the unreferenced data
restic forget --host pv-backup --keep-daily 7 --prune

# metadata-level consistency check (no --read-data: full verification would
# re-download the repo every night)
restic check
