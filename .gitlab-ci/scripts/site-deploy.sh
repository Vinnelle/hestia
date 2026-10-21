#!/bin/sh
set -eu

namespace=""
deployments=""
while [ $# -gt 0 ]; do
  case "$1" in
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
  if ! out=$(kubectl get "deployment/$name" -n "$namespace" -o name 2>&1); then
    case "$out" in
      *NotFound*)
        echo "deployment/$name does not exist yet -- Terraform will create it from the recorded digest"
        continue
        ;;
      *)
        echo "$out" >&2
        exit 1
        ;;
    esac
  fi
  image=$(jq -re --arg n "$name" '.[$n]' /tmp/images.json)
  kubectl set image "deployment/$name" -n "$namespace" "*=$image"
  live="$live $name"
done
for name in $live; do
  kubectl rollout status "deployment/$name" -n "$namespace"
done
