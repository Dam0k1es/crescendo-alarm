#!/usr/bin/env bash
# Local security/quality baseline for WakeyWakey.
# Runs, independently of each other:
#   1. flutter analyze         - static analysis / lints
#   2. osv-scanner              - known vulnerabilities in pubspec.lock dependencies
#   3. trufflehog                - secret scanning of the working tree
#
# This covers 3 of R1's 5 tools (see docs/REQUIREMENTS.md) - it does not run
# mobsfscan or a full MobSF scan (both need the built APK and, for MobSF, a
# local Docker instance - see .github/workflows/ci.yml if you need to run
# those too).
#
# Requires: flutter (on PATH), osv-scanner, trufflehog
#   https://github.com/google/osv-scanner
#   https://github.com/trufflesecurity/trufflehog
#
# Note: if `flutter analyze` fails with a PathAccessException/symlink error,
# your checkout is on a filesystem without symlink support (e.g. a
# VirtualBox/vboxsf shared folder). Run this from a checkout on a native
# filesystem instead - Flutter needs to create plugin symlinks even for
# `analyze`.
#
# Exit code is non-zero if any step reported findings or failed to run, so
# this can be wired into CI later. `flutter analyze` in particular exits
# non-zero even for info-level lints, not just errors.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

overall_status=0

echo "== 1/3: flutter analyze =="
flutter analyze
status=$?
[ "$status" -ne 0 ] && overall_status=1

echo
echo "== 2/3: osv-scanner (pubspec.lock) =="
osv-scanner --lockfile=pubspec.lock
status=$?
[ "$status" -ne 0 ] && overall_status=1

echo
echo "== 3/3: trufflehog (filesystem) =="
exclude_file="$(mktemp)"
trap 'rm -f "$exclude_file"' EXIT
printf 'build/\n.dart_tool/\n' > "$exclude_file"
trufflehog filesystem --results=verified,unknown --fail --exclude-paths="$exclude_file" .
status=$?
[ "$status" -ne 0 ] && overall_status=1

echo
if [ "$overall_status" -eq 0 ]; then
  echo "All checks completed cleanly."
else
  echo "All checks ran; at least one reported findings or failed - see output above."
fi
exit "$overall_status"
