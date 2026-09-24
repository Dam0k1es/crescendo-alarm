#!/usr/bin/env python3
"""docs/TODO.md T-144: fail if the resolved Android dependency tree contains
a native artifact this project's GPLv3 position forbids
(docs/licence-position.md), even though it never appears in pubspec.yaml or
a lib/ import - exactly how Google's ML Kit barcode binaries arrived
before T-33: through mobile_scanner's own build.gradle, invisible to
test/no_proprietary_dependencies_test.dart, which only reads pubspec.yaml
and lib/ source.

Reads the CycloneDX SBOM `:app:cyclonedxBom` already produces for the
native osv-scanner pass (see CLAUDE.md's CI/CD section) - this adds a
second check against the same file rather than resolving the dependency
tree a second time.

Usage: python3 scripts/check_proprietary_native_deps.py <bom.json>
       python3 scripts/check_proprietary_native_deps.py --self-test

`--self-test` needs no SBOM file and no network access - it checks `_offense()`
against synthetic components covering every `FORBIDDEN` entry, plus the
precision cases that make this a (group, name-prefix) match rather than a
whole-group ban. Added because an independent audit found this was the one
verdict-producing script in the project without a self-test of its own kind
(docs/TODO.md T-144) - unlike `.github/scripts/alarm_detection.sh`'s
`self_test()`, which this mirrors: a future typo in `FORBIDDEN` or a broken
`_offense()` prefix check would otherwise stay green until an actual
forbidden artifact reappeared, which is exactly the case this guard exists
to catch pre-merge.
"""
import json
import sys

# (group, name-prefix) pairs, not a whole-group ban where that would be too
# broad: com.google.android.gms is a large, otherwise-legitimate group, so
# only its specific ML Kit "unbundled" artifact family is forbidden, not
# every artifact under that group.
FORBIDDEN = [
    (
        "com.google.mlkit",
        "",
        "Google ML Kit - proprietary binaries, the actual T-33 offender.",
    ),
    (
        "com.google.android.gms",
        "play-services-mlkit",
        "Google ML Kit's \"unbundled\" Play Services variant - still "
        "proprietary.",
    ),
    (
        "com.syncfusion",
        "",
        "Syncfusion Essential Studio - requires a Community or commercial "
        "licence (T-05).",
    ),
]


def _offense(group: str, name: str) -> str | None:
    for forbidden_group, name_prefix, reason in FORBIDDEN:
        if group != forbidden_group:
            continue
        if name_prefix and not name.startswith(name_prefix):
            continue
        return f"{group}:{name} - {reason}"
    return None


def main(bom_path: str) -> int:
    with open(bom_path) as f:
        bom = json.load(f)

    components = bom.get("components", [])
    offenders = []
    for component in components:
        group = component.get("group") or ""
        name = component.get("name") or ""
        offense = _offense(group, name)
        if offense:
            offenders.append(offense)

    if offenders:
        print("Forbidden native dependency found in the resolved Android build:")
        for offense in offenders:
            print(f"  - {offense}")
        return 1

    print(
        f"No forbidden native dependency found among {len(components)} "
        f"resolved components."
    )
    return 0


def self_test() -> int:
    failed = False

    def check(label: str, group: str, name: str, expect_offense: bool) -> None:
        nonlocal failed
        got = _offense(group, name)
        if expect_offense and got is None:
            print(f"SELF-TEST FAIL: {label}: expected an offense, got none "
                  f"for {group}:{name}")
            failed = True
        elif not expect_offense and got is not None:
            print(f"SELF-TEST FAIL: {label}: expected no offense for "
                  f"{group}:{name}, got {got!r}")
            failed = True

    # Each FORBIDDEN entry must actually fire - not just exist in the list.
    check("ML Kit (any name)", "com.google.mlkit", "vision-common", True)
    check("ML Kit (blank name)", "com.google.mlkit", "", True)
    check("unbundled ML Kit", "com.google.android.gms",
          "play-services-mlkit-barcode-scanning", True)
    check("Syncfusion (any name)", "com.syncfusion", "flutter_syncfusion",
          True)

    # Precision cases: this is (group, name-prefix), not a whole-group ban -
    # these must NOT fire, or the check would be too broad to ship.
    check("gms group, unrelated artifact", "com.google.android.gms",
          "play-services-maps", False)
    check("gms group, near-miss prefix", "com.google.android.gms",
          "play-services-ml", False)
    check("unrelated group entirely", "com.example.totally.fine", "thing",
          False)
    check("empty bom", "", "", False)

    # main() itself: a clean synthetic BOM must exit 0, one containing a
    # real offender must exit 1 - proves the wiring from component dicts
    # through to the process exit code, not just `_offense()` in isolation.
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump({"components": [{"group": "com.example", "name": "fine"}]}, f)
        clean_path = f.name
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump({"components": [
            {"group": "com.example", "name": "fine"},
            {"group": "com.syncfusion", "name": "flutter_syncfusion"},
        ]}, f)
        offending_path = f.name

    if main(clean_path) != 0:
        print("SELF-TEST FAIL: main() flagged a clean synthetic BOM")
        failed = True
    if main(offending_path) != 1:
        print("SELF-TEST FAIL: main() did not flag a BOM containing "
              "com.syncfusion")
        failed = True

    if failed:
        print("SELF-TEST: FAILED")
        return 1
    print("SELF-TEST: all cases passed.")
    return 0


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        sys.exit(self_test())
    sys.exit(main(sys.argv[1]))
