#!/bin/sh
set -eu

zone=""
namespace=""
deployments=""
while [ $# -gt 0 ]; do
  case "$1" in
    --zone) zone="$2"; shift 2 ;;
    --namespace) namespace="$2"; shift 2 ;;
    *) deployments="$deployments $1"; shift ;;
  esac
done

if [ -z "$namespace" ]; then
  echo "--namespace is required" >&2
  exit 2
fi

git fetch --depth=1 origin "$CI_COMMIT_REF_NAME"
for f in hestia/sites/site-images.json hestia/apps/app-images.json hestia/identity/identity-images.json; do
  git show "FETCH_HEAD:$f"
done | jq -s 'add' > /tmp/images.json

live=""
for name in $deployments; do
  if ! kubectl get "deployment/$name" -n "$namespace" >/dev/null 2>&1; then
    echo "deployment/$name does not exist yet -- Terraform will create it from the recorded digest"
    continue
  fi
  image=$(jq -re --arg n "$name" '.[$n]' /tmp/images.json)
  kubectl set image "deployment/$name" -n "$namespace" "*=$image"
  live="$live $name"
done
for name in $live; do
  kubectl rollout status "deployment/$name" -n "$namespace"
done

if [ -n "$zone" ]; then
  zone_id=$(curl -fsS -H "Authorization: Bearer $CF_API_TOKEN" \
    "https://api.cloudflare.com/client/v4/zones?name=$zone" | jq -re '.result[0].id')
  curl -fsS -X POST \
    -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
    --data '{"purge_everything":true}' \
    "https://api.cloudflare.com/client/v4/zones/$zone_id/purge_cache" | jq -e '.success'
fi
