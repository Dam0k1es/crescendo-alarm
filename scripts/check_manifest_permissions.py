#!/usr/bin/env python3
"""docs/TODO.md T-49 / docs/REQUIREMENTS.md R6, R7: fail unless the permissions
a built APK (or a merged AndroidManifest.xml) requests match an explicit
allow-list exactly.

Why exact, in both directions:
- An *extra* permission is how this app grew `INTERNET`,
  `ACCESS_NETWORK_STATE`, `RECORD_AUDIO` and ~17 launcher-badge permissions
  over time: a plugin's manifest merges it in, nobody's own code asks for it,
  and nothing noticed. `INTERNET` in particular contradicts R7's "fully
  offline" claim, which had no automated guard before this script.
- A *missing* permission breaks a feature silently. `WRITE_CALENDAR` looks
  unused (the app never writes to a calendar), but `device_calendar`'s
  `arePermissionsGranted()` requires it to be granted before it reads
  anything, so stripping it would leave the scheduler with no calendar at
  all. Such a permission is listed here with that reason, so "cleaning it up"
  fails this check instead of shipping.

Adding a permission to ALLOWED is a reviewed decision: give the feature that
needs it and the code path that uses it.

Usage: python3 scripts/check_manifest_permissions.py [--variant release|debug] <app.apk | AndroidManifest.xml>
       python3 scripts/check_manifest_permissions.py --self-test

An `.apk` is read with `aapt2 dump permissions` (aapt2 from $AAPT2, else the
newest build-tools under $ANDROID_HOME/$ANDROID_SDK_ROOT, else PATH) - that is
what actually ships. Any other path is parsed as a merged manifest XML; XML
comments are ignored (a plugin's commented-out `<uses-permission>` is not a
permission - a plain grep over the merged manifest gets that wrong).
`--variant debug` additionally allows the DEBUG_ONLY permissions (Flutter's
debug/profile manifests add `INTERNET` for the tool connection). It fails
closed: an unreadable/empty/malformed input or an aapt2 error is a failure.
"""
import os
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

_ANDROID_NS = "{http://schemas.android.com/apk/res/android}"

# Permission -> why the app needs it. `{package}` is replaced with the
# manifest's package name.
ALLOWED = {
    "android.permission.READ_CALENDAR":
        "calendar-derived wake times (device_calendar reads events)",
    "android.permission.WRITE_CALENDAR":
        "never used to write, but device_calendar's arePermissionsGranted()/"
        "requestPermissions() require it granted before any read - removing "
        "it makes every calendar read fail with NOT_AUTHORIZED",
    "android.permission.RECEIVE_BOOT_COMPLETED":
        "re-arming alarms after a reboot (alarm plugin, awesome_notifications)",
    "android.permission.WAKE_LOCK": "ringing the alarm with the screen off",
    "android.permission.VIBRATE": "alarm vibration",
    "android.permission.USE_FULL_SCREEN_INTENT": "ring screen over the lock screen",
    "android.permission.FOREGROUND_SERVICE": "alarm and Direct-Boot fallback services",
    "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK":
        "the mediaPlayback foreground service type of those services",
    "android.permission.POST_NOTIFICATIONS": "alarm and reminder notifications",
    "android.permission.USE_EXACT_ALARM": "exact alarms, API 33+",
    "android.permission.SCHEDULE_EXACT_ALARM": "exact alarms, API 31-32",
    "android.permission.ACCESS_NOTIFICATION_POLICY":
        "sleep-time Do Not Disturb (T-198)",
    "android.permission.CAMERA": "scanning the QR deactivation code",
    "{package}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION":
        "androidx.core's guard for RECEIVER_NOT_EXPORTED on API < 33; "
        "signature-level, held only by this app",
}

DEBUG_ONLY = {
    "android.permission.INTERNET":
        "debug/profile builds only: the Flutter tool's VM-service connection",
}

# Named explicitly in the failure message because each one would make a
# documented claim false, not merely add surface.
_CLAIM_BREAKERS = {
    "android.permission.INTERNET":
        "R7: the app is fully offline; a release build must not hold INTERNET",
    "android.permission.ACCESS_NETWORK_STATE": "R7: fully offline (T-49)",
    "android.permission.RECORD_AUDIO": "T-49: the microphone is never opened",
}


class InputError(Exception):
    pass


def permissions_from_manifest_xml(text: str) -> tuple[str, set[str]]:
    if not text.strip():
        raise InputError("manifest is empty")
    try:
        root = ET.fromstring(text)
    except ET.ParseError as e:
        raise InputError(f"manifest is not well-formed XML ({e.position})") from None
    if root.tag != "manifest":
        raise InputError(f"root element is <{root.tag}>, not <manifest>")
    package = root.get("package", "")
    perms = set()
    for tag in ("uses-permission", "uses-permission-sdk-23", "uses-permission-sdk-m"):
        for el in root.iter(tag):
            name = el.get(_ANDROID_NS + "name")
            if not name:
                raise InputError(f"<{tag}> without android:name")
            perms.add(name)
    return package, perms


def permissions_from_aapt2_dump(text: str) -> tuple[str, set[str]]:
    package = ""
    perms = set()
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("package:"):
            package = line.split(":", 1)[1].strip()
        elif line.startswith(("uses-permission:", "uses-permission-sdk-23:")):
            rest = line.split(":", 1)[1].strip()
            if not rest.startswith("name='"):
                raise InputError(f"unexpected aapt2 line: {line}")
            perms.add(rest[len("name='"):].split("'", 1)[0])
    if not package:
        raise InputError("aapt2 output has no 'package:' line")
    return package, perms


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


def read_permissions(path: str) -> tuple[str, set[str]]:
    if not os.path.isfile(path):
        raise InputError(f"{path} does not exist")
    if path.endswith(".apk"):
        try:
            out = subprocess.run([_aapt2(), "dump", "permissions", path],
                                 capture_output=True, text=True, check=False)
        except OSError as e:
            raise InputError(f"cannot run aapt2: {e.strerror}") from None
        if out.returncode != 0:
            raise InputError(f"aapt2 exited with {out.returncode}")
        return permissions_from_aapt2_dump(out.stdout)
    with open(path, encoding="utf-8") as f:
        return permissions_from_manifest_xml(f.read())


def verdict(package: str, perms: set[str], variant: str) -> list[str]:
    """Problems found; empty means the permission set is exactly as allowed."""
    allowed = {k.replace("{package}", package): v for k, v in ALLOWED.items()}
    optional = dict(DEBUG_ONLY) if variant == "debug" else {}
    problems = []
    for p in sorted(perms - allowed.keys() - optional.keys()):
        why = _CLAIM_BREAKERS.get(p, "not in the allow-list")
        problems.append(f"UNEXPECTED: {p} - {why}")
    for p in sorted(allowed.keys() - perms):
        problems.append(f"MISSING: {p} - needed for {allowed[p]}")
    return problems


def check(path: str, variant: str) -> int:
    try:
        package, perms = read_permissions(path)
    except InputError as e:
        print(f"FAIL: cannot read permissions from {path}: {e}")
        return 1
    print(f"{path}: package {package}, {len(perms)} permission(s), variant {variant}")
    for p in sorted(perms):
        print(f"  {p}")
    problems = verdict(package, perms, variant)
    if problems:
        print()
        for line in problems:
            print(line)
        print(f"\n{len(problems)} permission problem(s). Remove an unexpected one with "
              "tools:node=\"remove\" in android/app/src/main/AndroidManifest.xml, or "
              "add it to ALLOWED in this script with the feature that needs it.")
        return 1
    print("\nPermissions match the allow-list exactly.")
    return 0


def _manifest(perms: list[str], extra: str = "") -> str:
    lines = "\n".join(f'  <uses-permission android:name="{p}" />' for p in perms)
    return ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android" '
            'package="com.example.app">\n' + lines + "\n" + extra + "</manifest>\n")


def self_test() -> int:
    pkg = "com.example.app"
    good = [k.replace("{package}", pkg) for k in ALLOWED]
    failures = []

    def expect(name, text, variant, want_ok, kind="xml"):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "AndroidManifest.xml")
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
            if kind == "xml":
                rc = check(path, variant)
            else:
                try:
                    package, perms = permissions_from_aapt2_dump(text)
                    rc = 1 if verdict(package, perms, variant) else 0
                except InputError:
                    rc = 1
        if (rc == 0) != want_ok:
            failures.append(f"{name}: expected {'pass' if want_ok else 'fail'}, got rc={rc}")

    expect("exact allow-list passes", _manifest(good), "release", True)
    expect("INTERNET fails a release build", _manifest(good + ["android.permission.INTERNET"]),
           "release", False)
    expect("INTERNET passes a debug build", _manifest(good + ["android.permission.INTERNET"]),
           "debug", True)
    expect("a launcher-badge permission fails",
           _manifest(good + ["com.sec.android.provider.badge.permission.READ"]), "release", False)
    expect("an extra permission fails a debug build too",
           _manifest(good + ["android.permission.RECORD_AUDIO"]), "debug", False)
    expect("missing WRITE_CALENDAR fails",
           _manifest([p for p in good if not p.endswith("WRITE_CALENDAR")]), "release", False)
    expect("a commented-out permission is not a permission",
           _manifest(good, '  <!-- <uses-permission android:name="android.permission.INTERNET"/> -->\n'),
           "release", True)
    expect("uses-permission-sdk-23 counts",
           _manifest(good, '  <uses-permission-sdk-23 android:name="android.permission.INTERNET"/>\n'),
           "release", False)
    expect("another package's receiver permission fails",
           _manifest(good + ["com.other.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"]), "release", False)
    expect("empty manifest fails", "", "release", False)
    expect("malformed manifest fails", "<manifest><uses-permission", "release", False)
    expect("non-manifest root fails", "<resources/>", "release", False)
    expect("<uses-permission> without a name fails",
           _manifest(good, "  <uses-permission />\n"), "release", False)

    dump = f"package: {pkg}\n" + "".join(f"uses-permission: name='{p}'\n" for p in good)
    expect("aapt2 dump: exact allow-list passes", dump, "release", True, "aapt2")
    expect("aapt2 dump: INTERNET fails",
           dump + "uses-permission: name='android.permission.INTERNET'\n", "release", False, "aapt2")
    expect("aapt2 dump: maxSdk suffix still parsed",
           dump + "uses-permission: name='android.permission.WRITE_EXTERNAL_STORAGE' maxSdkVersion='28'\n",
           "release", False, "aapt2")
    expect("aapt2 dump: declared <permission> is not a use",
           dump + f"permission: {pkg}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION\n", "release", True, "aapt2")
    expect("aapt2 dump: no package line fails", "uses-permission: name='x'\n", "release", False, "aapt2")
    expect("aapt2 dump: empty output fails", "", "release", False, "aapt2")

    rc_missing = check("/nonexistent/AndroidManifest.xml", "release")
    if rc_missing == 0:
        failures.append("missing input file: expected fail, got pass")

    print()
    if failures:
        for f in failures:
            print(f"SELF-TEST FAILED: {f}")
        return 1
    print("check_manifest_permissions self-test: all cases behaved as expected.")
    return 0


def main(argv: list[str]) -> int:
    if argv == ["--self-test"]:
        return self_test()
    variant = "release"
    if len(argv) == 3 and argv[0] == "--variant" and argv[1] in ("release", "debug"):
        variant, argv = argv[1], argv[2:]
    if len(argv) != 1:
        print(__doc__)
        return 2
    return check(argv[0], variant)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
