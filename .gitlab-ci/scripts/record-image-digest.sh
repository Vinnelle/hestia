#!/bin/sh
set -eu

deployment="$1"
image_ref="$2"

# Only prd pins digests. A merge-request build still builds and pushes the image,
# but recording the digest there would commit to the MR's source branch, which
# re-runs the MR pipeline and pins a digest for a change that may never merge.
if [ "${CI_COMMIT_BRANCH:-}" != "prd" ]; then
  echo "not on prd -- image pushed, digest not recorded"
  exit 0
fi

git config user.name "gitlab-ci"
git config user.email "gitlab-ci@vinnel.cloud"

for attempt in 1 2 3 4 5; do
  if ! git fetch --depth=1 origin "$CI_COMMIT_REF_NAME"; then
    sleep "$attempt"
    continue
  fi
  git reset --hard FETCH_HEAD

  jq --arg d "$deployment" --arg r "$image_ref" '.[$d] = $r' hestia/images.json > hestia/images.json.tmp
  mv hestia/images.json.tmp hestia/images.json
  git add hestia/images.json

  if git diff --cached --quiet; then
    echo "hestia/images.json already records this digest"
    exit 0
  fi

  # [skip ci] belts-and-braces: job-token pushes already create no pipeline, but
  # this keeps that true if the push credential ever changes.
  git commit -m "deploy: pin $deployment image digest [skip ci]"
  if git push origin "HEAD:${CI_COMMIT_REF_NAME}"; then
    exit 0
  fi
  sleep "$attempt"
done

echo "failed to push image digest update after five attempts" >&2
exit 1
