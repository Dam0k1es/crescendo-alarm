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
precision cases that keep a group match on dot boundaries (free Google
libraries such as Material Components, Gson and Guava must pass). Added because an independent audit found this was the one
verdict-producing script in the project without a self-test of its own kind
(docs/TODO.md T-144) - unlike `.github/scripts/alarm_detection.sh`'s
`self_test()`, which this mirrors: a future typo in `FORBIDDEN` or a broken
`_offense()` prefix check would otherwise stay green until an actual
forbidden artifact reappeared, which is exactly the case this guard exists
to catch pre-merge.
"""
import json
import sys

# (group, name-prefix) pairs. A group matches itself and its subgroups on a
# dot boundary (`com.google.firebase` also covers `com.google.firebase.x`,
# but `com.google.android.gms` never covers `com.google.android.gmsx`); an
# empty name-prefix bans the whole group.
#
# docs/TODO.md T-213 (G2): this used to forbid only ML Kit's
# `play-services-mlkit*` inside com.google.android.gms and treated the rest of
# that group as legitimate. It is not: every com.google.android.gms artifact
# is Google Play Services client code under Google's proprietary terms, and
# F-Droid rejects all of it. The same holds for the groups below. Free Google
# libraries live in other groups (com.google.android.material,
# com.google.code.gson, com.google.guava, com.android.tools) and stay allowed.
FORBIDDEN = [
    (
        "com.google.mlkit",
        "",
        "Google ML Kit - proprietary binaries, the actual T-33 offender.",
    ),
    (
        "com.google.android.gms",
        "",
        "Google Play Services (including ML Kit's \"unbundled\" variant, "
        "Maps, Ads, Auth) - proprietary.",
    ),
    (
        "com.google.firebase",
        "",
        "Firebase Android SDK - depends on proprietary Play Services.",
    ),
    (
        "com.google.android.play",
        "",
        "Google Play Core (review, app-update, integrity, asset delivery) - "
        "proprietary.",
    ),
    (
        "com.google.android.datatransport",
        "",
        "Google's telemetry transport used by Firebase - proprietary.",
    ),
    (
        "com.google.android.ump",
        "",
        "Google User Messaging Platform (ads consent) - proprietary.",
    ),
    (
        "com.crashlytics.sdk.android",
        "",
        "Crashlytics (Fabric era) - proprietary crash reporting.",
    ),
    (
        "io.fabric.sdk.android",
        "",
        "Fabric SDK - proprietary.",
    ),
    (
        "com.huawei.hms",
        "",
        "Huawei Mobile Services - proprietary.",
    ),
    (
        "com.huawei.agconnect",
        "",
        "Huawei AppGallery Connect - proprietary.",
    ),
    (
        "com.syncfusion",
        "",
        "Syncfusion Essential Studio - requires a Community or commercial "
        "licence (T-05).",
    ),
]


def _group_matches(group: str, forbidden_group: str) -> bool:
    return group == forbidden_group or group.startswith(forbidden_group + ".")


def _offense(group: str, name: str) -> str | None:
    for forbidden_group, name_prefix, reason in FORBIDDEN:
        if not _group_matches(group, forbidden_group):
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

    # docs/TODO.md T-213 (G2): whole proprietary groups. Every
    # com.google.android.gms artifact is Google Play Services (proprietary);
    # the earlier precision case that ALLOWED play-services-maps was wrong.
    check("GMS maps", "com.google.android.gms", "play-services-maps", True)
    check("GMS base", "com.google.android.gms", "play-services-base", True)
    check("GMS ads", "com.google.android.gms", "play-services-ads-lite",
          True)
    check("Firebase", "com.google.firebase", "firebase-messaging", True)
    check("Firebase Crashlytics", "com.google.firebase",
          "firebase-crashlytics", True)
    check("Play Core", "com.google.android.play", "core", True)
    check("Play review", "com.google.android.play", "review", True)
    check("Play integrity", "com.google.android.play", "integrity", True)
    check("datatransport", "com.google.android.datatransport",
          "transport-runtime", True)
    check("UMP consent SDK", "com.google.android.ump", "user-messaging-platform",
          True)
    check("Crashlytics (Fabric era)", "com.crashlytics.sdk.android",
          "crashlytics", True)
    check("Fabric", "io.fabric.sdk.android", "fabric", True)
    check("Huawei HMS", "com.huawei.hms", "push", True)
    check("Huawei AGConnect", "com.huawei.agconnect", "agconnect-core", True)
    check("subgroup of a forbidden group", "com.google.firebase.crashlytics",
          "x", True)

    # Precision cases: a group-prefix match on dot boundaries, never a bare
    # string prefix - these free libraries must NOT fire, or the check would
    # be too broad to ship. All four ship in this app today.
    check("Material Components", "com.google.android.material", "material",
          False)
    check("Gson", "com.google.code.gson", "gson", False)
    check("Guava", "com.google.guava", "guava", False)
    check("desugar_jdk_libs", "com.android.tools", "desugar_jdk_libs", False)
    check("near-miss group name", "com.google.android.gmsx", "thing", False)
    check("near-miss play group", "com.google.android.player", "thing",
          False)
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
