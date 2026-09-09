#!/usr/bin/env bash
# Keeps GitHub Actions artifact storage down to just what's needed: deletes
# artifacts from every release.yml run except the current one, the most
# recent *other* run that succeeded, and the most recent *other* run that
# failed (so there's always a known-good reference build/evidence set AND
# the most recent failure's evidence available for comparison, even when the
# latest run succeeded). Explicitly scoped to release.yml's own run IDs -
# artifacts from ci.yml (or any other workflow) are left alone.
#
# Requires GH_TOKEN (with `actions: write` permission) and GITHUB_REPOSITORY/
# GITHUB_RUN_ID in the environment, as set by the release.yml job that calls
# this.
set -euo pipefail

REPO="$GITHUB_REPOSITORY"
CURRENT_RUN_ID="$GITHUB_RUN_ID"

mapfile -t RELEASE_RUN_IDS < <(
  gh api "repos/$REPO/actions/workflows/release.yml/runs?per_page=100" \
    --paginate --jq '.workflow_runs[].id'
)

KEEP_SUCCESS_RUN_ID=$(
  gh api "repos/$REPO/actions/workflows/release.yml/runs?status=success&per_page=10" \
    --jq "[.workflow_runs[] | select(.id != $CURRENT_RUN_ID)] | .[0].id // empty"
)

KEEP_FAILURE_RUN_ID=$(
  gh api "repos/$REPO/actions/workflows/release.yml/runs?status=failure&per_page=10" \
    --jq "[.workflow_runs[] | select(.id != $CURRENT_RUN_ID)] | .[0].id // empty"
)

echo "release.yml runs known: ${#RELEASE_RUN_IDS[@]}"
echo "Current run: $CURRENT_RUN_ID"
echo "Keeping artifacts from prior successful run: ${KEEP_SUCCESS_RUN_ID:-(none found)}"
echo "Keeping artifacts from prior failed run: ${KEEP_FAILURE_RUN_ID:-(none found)}"

is_release_run() {
  local id="$1"
  for r in "${RELEASE_RUN_IDS[@]}"; do
    [ "$r" = "$id" ] && return 0
  done
  return 1
}

is_kept_run() {
  local id="$1"
  [ "$id" = "$CURRENT_RUN_ID" ] && return 0
  [ -n "$KEEP_SUCCESS_RUN_ID" ] && [ "$id" = "$KEEP_SUCCESS_RUN_ID" ] && return 0
  [ -n "$KEEP_FAILURE_RUN_ID" ] && [ "$id" = "$KEEP_FAILURE_RUN_ID" ] && return 0
  return 1
}

gh api "repos/$REPO/actions/artifacts?per_page=100" --paginate \
  --jq '.artifacts[] | "\(.id) \(.workflow_run.id)"' |
while read -r ARTIFACT_ID RUN_ID; do
  if ! is_release_run "$RUN_ID"; then
    continue # belongs to a different workflow (e.g. ci.yml) - not ours to touch
  fi
  if is_kept_run "$RUN_ID"; then
    continue
  fi
  echo "Deleting artifact $ARTIFACT_ID (from release.yml run $RUN_ID)"
  gh api -X DELETE "repos/$REPO/actions/artifacts/$ARTIFACT_ID" || true
done
