#!/bin/sh
set -eu

path="$1"
message="$2"
cd "$path"

git config user.name "gitlab-ci"
git config user.email "gitlab-ci@vinnel.cloud"

branch=$(git rev-parse --abbrev-ref HEAD)

for attempt in 1 2 3 4 5; do
  if ! { git fetch --depth=1 origin "$branch" && git reset --soft FETCH_HEAD; }; then
    sleep "$attempt"
    continue
  fi
  git add -A

  if git diff --cached --quiet; then
    echo "mirror already up to date"
    exit 0
  fi

  git commit -m "$message"
  if git push origin "HEAD:$branch"; then
    exit 0
  fi
  sleep "$attempt"
done

echo "failed to push after 5 attempts" >&2
exit 1
