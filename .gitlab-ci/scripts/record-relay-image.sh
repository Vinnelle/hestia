#!/bin/sh
set -eu

pin=hestia/platform/relay/image/image.json

if [ "${CI_COMMIT_BRANCH:-}" != "prd" ]; then
  echo "not on prd -- image published, not pinned"
  exit 0
fi

published=$(mktemp)
cp "$pin" "$published"
label=$(jq -r .label "$published")

git config user.name "gitlab-ci"
git config user.email "gitlab-ci@vinnel.cloud"

for attempt in 1 2 3 4 5; do
  if ! git fetch --depth=1 origin "$CI_COMMIT_REF_NAME"; then
    sleep "$attempt"
    continue
  fi
  git reset --hard FETCH_HEAD
  cp "$published" "$pin"
  git add "$pin"

  if git diff --cached --quiet; then
    echo "$pin already pins $label"
    exit 0
  fi

  git commit -m "deploy: pin relay image $label [skip ci]"
  if git push origin "HEAD:${CI_COMMIT_REF_NAME}"; then
    exit 0
  fi
  sleep "$attempt"
done

echo "failed to push the relay image pin after five attempts" >&2
exit 1
