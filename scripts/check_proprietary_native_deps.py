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


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
