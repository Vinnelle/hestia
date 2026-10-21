#!/bin/sh
set -eu

: "${MEGA_ENDPOINT:?}" "${MEGA_REGION:?}" "${BUCKET:?}" "${PBS_S3_ACCESS_KEY:?}" "${PBS_S3_SECRET_KEY:?}"
: "${RESEND_API_KEY:?}" "${ALERT_EMAIL:?}"
REUSE_DATASTORE=${REUSE_DATASTORE:-false}
NEW_ENCRYPTION_KEY=${NEW_ENCRYPTION_KEY:-false}
NEW_TOKEN=${NEW_TOKEN:-false}
PROVIDER_QUIRKS=${PBS_PROVIDER_QUIRKS:-}

exec 3>&1 1>&2

pbm() {
  proxmox-backup-manager "$@"
}

listed() {
  pattern=$1
  shift
  pbm "$@" --output-format json | grep -q "$pattern"
}

echo "==> package repositories"
. /etc/os-release
cat > /etc/apt/sources.list.d/pbs.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pbs
Suites: $VERSION_CODENAME
Components: pbs-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
if ! dpkg -s proxmox-backup-server >/dev/null 2>&1; then
  echo "==> installing proxmox-backup-server"
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq proxmox-backup-server
fi
enterprise=/etc/apt/sources.list.d/pbs-enterprise.sources
if [ -f "$enterprise" ] && ! grep -q '^Enabled:' "$enterprise"; then
  echo 'Enabled: false' >> "$enterprise"
fi

echo "==> local cache on the encrypted vault pool"
cache=/mnt/pbs-cache
if ! zfs list -H vault/pbs-cache >/dev/null 2>&1; then
  mkdir -p "$cache"
  chattr +i "$cache"
  zfs create -o mountpoint="$cache" -o quota=100G vault/pbs-cache
fi
if [ "$(zfs get -H -o value mounted vault/pbs-cache)" != yes ]; then
  echo "vault/pbs-cache is not mounted: unlock the pool first (zfs load-key -a && zfs mount -a)" >&2
  exit 1
fi

echo "==> S3 endpoint mega ($MEGA_ENDPOINT, $MEGA_REGION)"
set -- --endpoint "$MEGA_ENDPOINT" --region "$MEGA_REGION" --path-style true \
  --access-key "$PBS_S3_ACCESS_KEY" --secret-key "$PBS_S3_SECRET_KEY"
if [ -n "$PROVIDER_QUIRKS" ]; then
  set -- "$@" --provider-quirks "$PROVIDER_QUIRKS"
fi
if listed '"id":"mega"' s3 endpoint list; then
  pbm s3 endpoint update mega "$@"
else
  pbm s3 endpoint create mega "$@"
fi
pbm s3 check mega "$BUCKET"

echo "==> datastore mega in bucket $BUCKET"
if ! listed '"name":"mega"' datastore list; then
  pbm datastore create mega "$cache/mega" --backend "type=s3,client=mega,bucket=$BUCKET" \
    --gc-schedule daily --reuse-datastore "$REUSE_DATASTORE" --overwrite-in-use "$REUSE_DATASTORE"
fi
if ! listed '"id":"mega-verify"' verify-job list; then
  pbm verify-job create mega-verify --store mega --schedule 'sat 05:00' \
    --ignore-verified true --outdated-after 30
fi

echo "==> failure mail through Resend to $ALERT_EMAIL"
if listed '"name":"resend"' notification endpoint smtp list; then
  pbm notification endpoint smtp update resend --password "$RESEND_API_KEY" --mailto "$ALERT_EMAIL"
else
  pbm notification endpoint smtp create resend --server smtp.resend.com --port 587 --mode starttls \
    --username resend --password "$RESEND_API_KEY" --from-address alerts@vinnel.cloud \
    --author 'Proxmox Backup Server' --mailto "$ALERT_EMAIL"
fi
pbm notification matcher update default-matcher --target resend

echo "==> backup-only login for Proxmox VE"
if ! listed '"userid":"pve@pbs"' user list; then
  pbm user create pve@pbs --comment 'Proxmox VE backups'
fi
if [ "$NEW_TOKEN" = true ] && listed '"tokenid":"pve@pbs!pve"' user list-tokens pve@pbs; then
  pbm user delete-token pve@pbs pve
fi
if ! listed '"tokenid":"pve@pbs!pve"' user list-tokens pve@pbs; then
  token=$(pbm user generate-token pve@pbs pve)
  printf 'token-secret=%s\n' "$(printf %s "$token" | grep -o -E '[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}' | head -1)" >&3
fi
pbm acl update /datastore/mega DatastorePowerUser --auth-id pve@pbs
pbm acl update /datastore/mega DatastorePowerUser --auth-id 'pve@pbs!pve'

if [ "$NEW_ENCRYPTION_KEY" = true ]; then
  echo "==> new backup encryption key"
  keys=$(mktemp -d -p /run)
  proxmox-backup-client key create --kdf none "$keys/key.json"
  printf 'encryption-key=%s\n' "$(base64 -w0 "$keys/key.json")" >&3
  rm -rf "$keys"
fi

printf 'fingerprint=%s\n' "$(pbm cert info | sed -n 's/^Fingerprint (sha256): //p')" >&3
