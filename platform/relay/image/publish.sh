#!/bin/sh
set -eu

here=$(cd "$(dirname "$0")" && pwd)
image="$here/out/relay.img"
sha=$(cat "$here/out/relay.img.sha256")
label="gaia-relay-$(printf %s "$sha" | cut -c1-16)"

: "${OS_AUTH_URL:?}" "${OS_REGION_NAME:?}" "${OS_APPLICATION_CREDENTIAL_ID:?}" "${OS_APPLICATION_CREDENTIAL_SECRET:?}"

echo "==> installing curl and jq"
apk add --no-cache --quiet curl jq

call() {
  if ! response=$(curl -sS --fail-with-body "$@"); then
    echo "OpenStack API: $response" >&2
    exit 1
  fi
  printf %s "$response"
}

echo "==> signing in to $OS_AUTH_URL with the application credential"
headers=$(mktemp)
trap 'rm -f "$headers"' EXIT
auth=$(jq -n --arg id "$OS_APPLICATION_CREDENTIAL_ID" --arg secret "$OS_APPLICATION_CREDENTIAL_SECRET" \
  '{auth: {identity: {methods: ["application_credential"], application_credential: {id: $id, secret: $secret}}}}')
session=$(printf %s "$auth" | call -D "$headers" -H 'Content-Type: application/json' -d @- "${OS_AUTH_URL%/}/v3/auth/tokens")
token=$(grep -i '^x-subject-token:' "$headers" | cut -d' ' -f2 | tr -d '\r')
glance=$(printf %s "$session" | jq -r --arg region "$OS_REGION_NAME" \
  'first(.token.catalog[] | select(.type == "image") | .endpoints[] | select(.interface == "public" and (.region_id == $region or .region == $region)) | .url) // empty')
if [ -z "$token" ] || [ -z "$glance" ]; then
  echo "no token, or no image service in $OS_REGION_NAME" >&2
  exit 1
fi
glance="${glance%/}"
glance="${glance%/v2}/v2"

api() {
  call -H "X-Auth-Token: $token" "$@"
}

echo "==> image $label (sha256 $sha)"
echo "==> looking for it among your images in $OS_REGION_NAME"
found=$(api "$glance/images?name=$label")
for stale in $(printf %s "$found" | jq -r '.images[] | select(.status != "active" or .disk_format != "iso") | .id'); do
  echo "    deleting $stale, an unfinished or non-iso upload"
  api -X DELETE "$glance/images/$stale" >/dev/null
done
id=$(printf %s "$found" | jq -r 'first(.images[] | select(.status == "active" and .disk_format == "iso") | .id) // empty')

if [ -n "$id" ]; then
  echo "==> already uploaded as $id"
else
  echo "==> creating the image"
  meta=$(jq -n --arg name "$label" \
    '{name: $name, disk_format: "iso", container_format: "bare", visibility: "private", os_type: "linux", os_distro: "alpine"}')
  created=$(printf %s "$meta" | api -H 'Content-Type: application/json' -d @- "$glance/images")
  id=$(printf %s "$created" | jq -r .id)
  echo "==> uploading $(du -m "$image" | cut -f1) MiB as $id"
  if ! put=$(curl -S --progress-bar --fail-with-body -X PUT -H "X-Auth-Token: $token" \
    -H 'Content-Type: application/octet-stream' --upload-file "$image" "$glance/images/$id/file"); then
    echo "upload of $id failed: $put" >&2
    exit 1
  fi
fi

echo "==> waiting for $id to become active"
tries=0
last=
while :; do
  info=$(api "$glance/images/$id")
  status=$(printf %s "$info" | jq -r .status)
  [ "$status" = active ] && break
  case $status in
    killed | deleted | deactivated)
      echo "image $id is $status" >&2
      exit 1
      ;;
  esac
  if [ "$status" != "$last" ]; then
    echo "    $status"
    last=$status
  fi
  tries=$((tries + 1))
  if [ "$tries" -gt 60 ]; then
    echo "image $id is still $status after 10 minutes" >&2
    exit 1
  fi
  sleep 10
done
echo "    active"

algo=$(printf %s "$info" | jq -r '.os_hash_algo // "md5"')
stored=$(printf %s "$info" | jq -r '.os_hash_value // .checksum')
if [ "$("${algo}sum" "$image" | cut -d' ' -f1)" != "$stored" ]; then
  echo "image $id does not match out/relay.img ($algo $stored)" >&2
  exit 1
fi
echo "==> $algo matches out/relay.img"

printf '{\n  "id": "%s",\n  "label": "%s"\n}\n' "$id" "$label" > "$here/image.json"
echo "published $id ($label) in $OS_REGION_NAME; wrote image.json"
