#!/bin/sh
set -eu

api="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}"
source_branch="${CI_COMMIT_BRANCH}"
target_branch="${MR_TARGET_BRANCH:-prd}"

get() { curl -fsS -H "PRIVATE-TOKEN: ${CI_BOT_TOKEN}" "$@"; }

ahead=$(get "${api}/repository/compare?from=${target_branch}&to=${source_branch}" | jq '.commits | length')
if [ "$ahead" -eq 0 ]; then
  echo "${source_branch} is not ahead of ${target_branch}, nothing to merge"
  exit 0
fi

iid=$(get "${api}/merge_requests?state=opened&source_branch=${source_branch}&target_branch=${target_branch}" |
  jq -r '.[0].iid // empty')

if [ -z "$iid" ]; then
  iid=$(get -X POST \
    --data-urlencode "source_branch=${source_branch}" \
    --data-urlencode "target_branch=${target_branch}" \
    --data-urlencode "title=Merge ${source_branch} into ${target_branch}" \
    --data-urlencode "description=Opened automatically for ${CI_COMMIT_SHA}. Auto-merges once the pipeline passes." \
    --data "remove_source_branch=false" \
    --data "squash=false" \
    "${api}/merge_requests" | jq -r '.iid')
  echo "opened !${iid} (${ahead} commit(s) ahead)"
else
  echo "reusing open !${iid} (${ahead} commit(s) ahead)"
fi

# Auto-merge can only be armed once the MR has a head pipeline and GitLab has
# finished computing mergeability.
attempt=0
while [ "$attempt" -lt 40 ]; do
  mr=$(get "${api}/merge_requests/${iid}")
  state=$(echo "$mr" | jq -r '.state')
  status=$(echo "$mr" | jq -r '.detailed_merge_status // .merge_status // "unknown"')
  pipeline=$(echo "$mr" | jq -r '.head_pipeline.id // empty')

  case "$state" in
    merged | closed)
      echo "!${iid} is already ${state}"
      exit 0
      ;;
  esac

  case "$status" in
    broken_status | conflict)
      echo "!${iid} cannot be merged automatically (${status}) -- resolve by hand" >&2
      exit 1
      ;;
  esac

  if [ -n "$pipeline" ]; then
    # should_remove_source_branch=false is load-bearing: the project sets
    # remove_source_branch_after_merge, which would delete the long-lived
    # integration branch on the first auto-merge.
    if get -X PUT \
      --data "merge_when_pipeline_succeeds=true" \
      --data "should_remove_source_branch=false" \
      "${api}/merge_requests/${iid}/merge" >/dev/null 2>&1; then
      echo "auto-merge armed on !${iid} against pipeline ${pipeline}"
      exit 0
    fi
  fi

  attempt=$((attempt + 1))
  sleep 5
done

echo "gave up arming auto-merge on !${iid} after $((attempt * 5))s (status=${status}, pipeline=${pipeline:-none})" >&2
exit 1
