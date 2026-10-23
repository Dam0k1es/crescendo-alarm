#!/usr/bin/env python3
"""docs/TODO.md T-241 (Philipp's review): fail when an APK exports a component
that is not on the reviewed list.

A plugin bump can add an exported receiver, service or activity that any
installed app may then call (T-238: an exported awesome_notifications service
crashed a ringing alarm; T-241: three exported receivers let any app make this
one post a notification). `test/manifest_*_test.dart` read the app's own
manifest and cannot see what the merger adds, so this reads the merged
manifest of the BUILT APK with aapt2, the same way
scripts/check_manifest_permissions.py reads its permissions, and compares the
set of exported components with EXPORTED below - in both directions.

    python3 scripts/check_exported_components.py app-release.apk
    python3 scripts/check_exported_components.py --self-test

A component counts as exported when android:exported is true, or when it has an
intent-filter and no android:exported at all.
"""
import os
import re
import subprocess
import sys

_COMPONENTS = ("activity", "activity-alias", "service", "receiver", "provider")

# component class -> why it must be exported. Adding one is a reviewed decision
# with the platform reason named (see .github/security-exceptions.json).
EXPORTED = {
    "com.crescendoalarm.crescendoalarm.MainActivity":
        "the launcher activity",
    "com.crescendoalarm.crescendoalarm.DirectBootReceiver":
        "LOCKED_BOOT_COMPLETED is a protected broadcast; a boot receiver must "
        "be exported to get it (T-158, accepted in security-exceptions.json)",
    "com.gdelataillade.alarm.alarm.BootReceiver":
        "the alarm plugin's own re-arm after boot; checks the protected "
        "BOOT_COMPLETED action",
    "me.carda.awesome_notifications.DartRefreshSchedulesReceiver":
        "awesome_notifications' boot/package-replaced receiver (T-158 reasoning; "
        "its QUICKBOOT exposure is the accepted F3 of "
        "docs/security-assessment-2026-09.md)",
    "androidx.profileinstaller.ProfileInstallReceiver":
        "AndroidX profile installer, guarded by android.permission.DUMP",
}


class InputError(Exception):
    pass


def exported_components(xmltree: str) -> set[str]:
    """Names of the exported components in an `aapt2 dump xmltree` text."""
    found: set[str] = set()
    comp = None  # (indent, name, exported_attr, has_filter)

    def close():
        nonlocal comp
        if comp:
            _, name, attr, has_filter = comp
            if attr is True or (attr is None and has_filter):
                if name:
                    found.add(name)
        comp = None

    for line in xmltree.splitlines():
        stripped = line.lstrip()
        indent = len(line) - len(stripped)
        if stripped.startswith("E: "):
            tag = stripped[3:].split(" ", 1)[0]
            if comp and indent <= comp[0]:
                close()
            if tag in _COMPONENTS:
                close()
                comp = (indent, None, None, False)
            elif comp and tag == "intent-filter":
                comp = (comp[0], comp[1], comp[2], True)
        elif comp and stripped.startswith("A: "):
            if indent != comp[0] + 2:
                continue  # an attribute of a child (action, category, meta-data)
            m = re.match(r'A: \S*:name\([^)]*\)="([^"]+)"', stripped)
            if m:
                comp = (comp[0], m.group(1), comp[2], comp[3])
            m = re.match(r"A: \S*:exported\([^)]*\)=(?:\(type 0x\w+\))?(\S+)", stripped)
            if m:
                value = m.group(1).lower()
                comp = (comp[0], comp[1], value in ("true", "0xffffffff"), comp[3])
    close()
    return found


def _aapt2() -> str:
    if os.environ.get("AAPT2"):
        return os.environ["AAPT2"]
    for var in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        sdk = os.environ.get(var)
        bt = os.path.join(sdk, "build-tools") if sdk else None
        if bt and os.path.isdir(bt):
            def ver(v):
                return [int(p) if p.isdigit() else 0 for p in v.replace("-", ".").split(".")]
            for v in sorted(os.listdir(bt), key=ver, reverse=True):
                cand = os.path.join(bt, v, "aapt2")
                if os.path.isfile(cand):
                    return cand
    return "aapt2"


def read_exported(apk: str) -> set[str]:
    if not os.path.isfile(apk):
        raise InputError(f"{apk} does not exist")
    try:
        out = subprocess.run(
            [_aapt2(), "dump", "xmltree", "--file", "AndroidManifest.xml", apk],
            capture_output=True, text=True, check=False)
    except OSError as e:
        raise InputError(f"cannot run aapt2: {e.strerror}") from None
    if out.returncode != 0:
        raise InputError(f"aapt2 exited with {out.returncode}")
    if "E: application" not in out.stdout:
        raise InputError("aapt2 output has no <application> element")
    return exported_components(out.stdout)


def verdict(found: set[str]) -> list[str]:
    problems = []
    for name in sorted(found - EXPORTED.keys()):
        problems.append(f"UNEXPECTED: {name} is exported and not on the reviewed list")
    for name in sorted(EXPORTED.keys() - found):
        problems.append(
            f"MISSING: {name} is on the list but not exported (list or manifest is stale)")
    return problems


def main(argv: list[str]) -> int:
    if argv == ["--self-test"]:
        return self_test()
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 1:
        print(__doc__)
        return 2
    try:
        found = read_exported(args[0])
    except InputError as e:
        print(f"FAIL (fail-closed): {e}")
        return 1
    problems = verdict(found)
    if problems:
        for p in problems:
            print(p)
        return 1
    print(f"Exported components match the reviewed list exactly ({len(found)}).")
    return 0


_NS = "http://schemas.android.com/apk/res/android"
_FIXTURE = f"""\
N: android={_NS}
  E: manifest (line=2)
    E: application (line=107)
      E: activity (line=121)
        A: {_NS}:name(0x01010003)="com.x.MainActivity" (Raw: "com.x.MainActivity")
        A: {_NS}:exported(0x01010010)=true
          E: intent-filter (line=141)
            E: action (line=142)
              A: {_NS}:name(0x01010003)="android.intent.action.MAIN" (Raw: "x")
      E: receiver (line=212)
        A: {_NS}:name(0x01010003)="com.x.PrivateReceiver" (Raw: "x")
        A: {_NS}:exported(0x01010010)=false
          E: intent-filter (line=217)
            E: action (line=218)
              A: {_NS}:name(0x01010003)="a.b.C" (Raw: "x")
      E: receiver (line=230)
        A: {_NS}:name(0x01010003)="com.x.ImplicitReceiver" (Raw: "x")
          E: intent-filter (line=232)
            E: action (line=233)
              A: {_NS}:name(0x01010003)="a.b.D" (Raw: "x")
      E: service (line=240)
        A: {_NS}:name(0x01010003)="com.x.NoFilterNoAttr" (Raw: "x")
      E: provider (line=250)
        A: {_NS}:name(0x01010003)="com.x.Provider" (Raw: "x")
        A: {_NS}:exported(0x01010010)=(type 0x12)0xffffffff
      E: meta-data (line=260)
        A: {_NS}:name(0x01010003)="not.a.component" (Raw: "x")
"""


def self_test() -> int:
    failures = []

    def expect(label, got, want):
        if got != want:
            failures.append(f"{label}: got {got!r}, wanted {want!r}")

    found = exported_components(_FIXTURE)
    expect("exported / implicit / provider parsed", found,
           {"com.x.MainActivity", "com.x.ImplicitReceiver", "com.x.Provider"})
    expect("an attribute of a child element is not the component's own",
           "a.b.C" in found, False)
    expect("a service with neither filter nor attribute is private",
           "com.x.NoFilterNoAttr" in found, False)
    expect("meta-data is no component", "not.a.component" in found, False)
    expect("empty text finds nothing", exported_components(""), set())

    expect("the reviewed set passes", verdict(set(EXPORTED)), [])
    extra = verdict(set(EXPORTED) | {"com.evil.Receiver"})
    expect("an extra exported component fails",
           [p for p in extra if p.startswith("UNEXPECTED")],
           ["UNEXPECTED: com.evil.Receiver is exported and not on the reviewed list"])
    gone = verdict(set(EXPORTED) - {"com.crescendoalarm.crescendoalarm.DirectBootReceiver"})
    expect("a listed component no longer exported is reported as stale",
           [p.split(":")[0] for p in gone], ["MISSING"])
    expect("missing APK fails closed", main(["/nonexistent/app.apk"]), 1)

    if failures:
        for f in failures:
            print(f"SELF-TEST FAIL: {f}")
        return 1
    print("check_exported_components self-test: all cases behaved as expected.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
