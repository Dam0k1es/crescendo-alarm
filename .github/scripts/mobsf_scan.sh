#!/usr/bin/env bash
# Full MobSF static scan of a built APK, gated by scripts/mobsf_summary.py
# against .github/security-exceptions.json (docs/REQUIREMENTS.md R1).
#
# Shared by ci.yml's mobsf-full-scan job (master) and release.yml's
# build-signed-release job (the APK attached to a GitHub Release), so the two
# cannot drift apart - the release APK used to be the one build that was
# never MobSF-scanned at all (audit of 2026-10-05).
#
# Fails closed at every step: MobSF not coming up, no API key in its log, an
# HTTP error from upload or scan (curl -f), a reply without a hash, and a
# report that is not a complete scan of THIS APK (mobsf_summary.py --apk
# compares the report's sha256 with the file) all exit non-zero. The old
# inline version had no -f on its curl calls, so an error reply was written
# to the report file and summarised as "HIGH: 0".
#
# Usage: .github/scripts/mobsf_scan.sh <app.apk> <report-out.json>
# Needs docker, curl, python3. Leaves <report-out.json> behind (whatever
# MobSF returned) for upload as evidence.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <app.apk> <report-out.json>" >&2
  exit 2
fi
APK=$1
REPORT=$2
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
IMAGE=${MOBSF_IMAGE:-opensecurity/mobile-security-framework-mobsf:latest}
NAME=mobsf-scan-$$
BASE=http://localhost:8000

[ -f "$APK" ] || { echo "FAIL: APK $APK does not exist" >&2; exit 1; }

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --name "$NAME" -p 8000:8000 "$IMAGE" >/dev/null
up=0
for _ in $(seq 1 60); do
  if curl -sf -m 5 "$BASE/" -o /dev/null; then
    up=1
    break
  fi
  sleep 5
done
if [ "$up" -ne 1 ]; then
  echo "FAIL: MobSF did not come up within 5 minutes" >&2
  docker logs --tail 50 "$NAME" >&2 || true
  exit 1
fi
echo "MobSF is up"

API_KEY=$(docker logs "$NAME" 2>&1 | grep "REST API Key" | tail -1 | grep -oE '[0-9a-f]{64}' || true)
if [ -z "$API_KEY" ]; then
  echo "FAIL: no REST API key found in the MobSF log" >&2
  exit 1
fi

FILE_NAME=$(basename "$APK")
echo "Uploading $FILE_NAME..."
UPLOAD=$(curl -fsS -m 300 -X POST "$BASE/api/v1/upload" \
  -H "Authorization: $API_KEY" \
  -F "file=@$APK")
echo "$UPLOAD"
HASH=$(printf '%s' "$UPLOAD" | python3 -c "import sys, json; print(json.load(sys.stdin)['hash'])")
if [ -z "$HASH" ]; then
  echo "FAIL: MobSF upload reply carries no hash" >&2
  exit 1
fi

echo "Scanning (hash=$HASH)..."
curl -fsS -m 1800 -X POST "$BASE/api/v1/scan" \
  -H "Authorization: $API_KEY" \
  -F "hash=$HASH" -F "scan_type=apk" -F "file_name=$FILE_NAME" \
  -o "$REPORT"

python3 "$ROOT/scripts/mobsf_summary.py" "$REPORT" \
  "$ROOT/.github/security-exceptions.json" --apk "$APK"
