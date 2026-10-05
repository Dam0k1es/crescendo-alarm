#!/usr/bin/env python3
"""Print a HIGH/WARNING summary from a MobSF static-analyzer JSON report, and
fail if any HIGH finding isn't recorded as an accepted exception in
.github/security-exceptions.json - see docs/REQUIREMENTS.md R1. Previously
this only printed counts with no threshold, so a new HIGH finding could
leave the pipeline green (docs/TODO.md T-11).

It fails closed (audit of 2026-10-05): it used to read
`report.get("appsec", {})`, so a MobSF error reply such as
`{"error": "Invalid API Key"}` printed "HIGH: 0" and passed. Now anything
that is not a complete scan report - missing, empty, not JSON, an `error`
key, no `appsec` block, findings without a title - is a failure, and with
`--apk` the report must be about that exact file (its `sha256`).

MobSF's `appsec` findings carry a title, a description and a section, never a
file path, so exceptions here stay keyed by exact title. Manifest findings
name their component in the title (e.g. "Broadcast Receiver (...DirectBootReceiver)"),
so a new exported receiver still produces a new, un-accepted title.

Usage: python3 scripts/mobsf_summary.py <report.json> <exceptions.json> [--apk <app.apk>]
       python3 scripts/mobsf_summary.py --self-test
"""
import hashlib
import json
import os
import sys
import tempfile


class ReportError(Exception):
    pass


def load_json(path: str, what: str):
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except OSError as e:
        raise ReportError(f"cannot read {what} {path}: {e.strerror}") from None
    if not text.strip():
        raise ReportError(f"{what} {path} is empty")
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        raise ReportError(f"{what} {path} is not valid JSON (line {e.lineno})") from None


def validated_appsec(report, apk_sha256: str | None) -> dict:
    if not isinstance(report, dict):
        raise ReportError("report is not a JSON object")
    if "error" in report:
        raise ReportError(f"MobSF returned an error instead of a report: {report['error']!r}")
    appsec = report.get("appsec")
    if not isinstance(appsec, dict):
        raise ReportError("report has no 'appsec' block - not a completed scan")
    for key in ("high", "warning"):
        findings = appsec.get(key)
        if not isinstance(findings, list):
            raise ReportError(f"appsec.{key} is missing or not a list")
        for finding in findings:
            if not isinstance(finding, dict) or not isinstance(finding.get("title"), str):
                raise ReportError(f"appsec.{key} has a finding without a title")
    if apk_sha256 is not None:
        got = report.get("sha256")
        if got != apk_sha256:
            raise ReportError(f"report is for sha256 {got!r}, not the scanned APK ({apk_sha256})")
    return appsec


def evaluate(report, exceptions: dict, apk_sha256: str | None = None) -> int:
    appsec = validated_appsec(report, apk_sha256)
    high, warning = appsec["high"], appsec["warning"]

    print(f"HIGH: {len(high)}")
    unaccepted = []
    for finding in high:
        title = finding["title"]
        if title in exceptions:
            print(f" - ACCEPTED: {title} - {exceptions[title]}")
        else:
            print(f" - UNACCEPTED: {title}")
            unaccepted.append(title)

    print(f"WARNING: {len(warning)}")
    for finding in warning:
        print(f" - {finding['title']}")

    if unaccepted:
        print(
            f"\n{len(unaccepted)} un-excepted HIGH finding(s). Fix them, or "
            f"add a dated, reasoned exception to .github/security-exceptions.json."
        )
        return 1

    print("\nNo un-excepted HIGH findings.")
    return 0


def sha256_of(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main(argv: list[str]) -> int:
    if argv == ["--self-test"]:
        return self_test()
    apk = None
    if len(argv) == 4 and argv[2] == "--apk":
        apk, argv = argv[3], argv[:2]
    if len(argv) != 2:
        print(__doc__)
        return 2
    try:
        report = load_json(argv[0], "MobSF report")
        exc_file = load_json(argv[1], "exceptions file")
        exceptions = exc_file.get("mobsf") if isinstance(exc_file, dict) else None
        if not isinstance(exceptions, dict):
            raise ReportError("exceptions file has no 'mobsf' object")
        apk_sha = None
        if apk is not None:
            if not os.path.isfile(apk):
                raise ReportError(f"APK {apk} does not exist")
            apk_sha = sha256_of(apk)
        return evaluate(report, exceptions, apk_sha)
    except ReportError as e:
        print(f"FAIL (fail-closed): {e}")
        return 1


def self_test() -> int:
    accepted = "App can be installed on a vulnerable unpatched Android version 7.0, [minSdk=24]"
    exc = {"_comment": "x", "mobsf": {accepted: "2026-09-09: reason"}, "mobsfscan": {}}

    def report(high=(), warning=()):
        return {"sha256": "ab" * 32, "appsec": {
            "high": [{"title": t, "section": "manifest"} for t in high],
            "warning": [{"title": t} for t in warning]}}

    cases = [
        ("clean report passes", json.dumps(report()), True, None),
        ("accepted HIGH passes", json.dumps(report(high=[accepted], warning=["w"])), True, None),
        ("un-accepted HIGH fails", json.dumps(report(high=["Debug enabled"])), False, None),
        ("MobSF error reply fails", json.dumps({"error": "Invalid API Key"}), False, None),
        ("report without appsec fails", json.dumps({"sha256": "x"}), False, None),
        ("appsec without 'high' fails", json.dumps({"appsec": {"warning": []}}), False, None),
        ("appsec.high not a list fails", json.dumps({"appsec": {"high": {}, "warning": []}}), False, None),
        ("finding without a title fails",
         json.dumps({"appsec": {"high": [{"section": "x"}], "warning": []}}), False, None),
        ("JSON array fails", "[]", False, None),
        ("empty file fails", "", False, None),
        ("truncated JSON fails", '{"appsec": {"high": [', False, None),
        ("HTML error page fails", "<html>502 Bad Gateway</html>", False, None),
        ("report for the scanned APK passes", json.dumps(report()), True, "ab" * 32),
        ("report for another APK fails", json.dumps(report()), False, "cd" * 32),
    ]
    failures = []
    with tempfile.TemporaryDirectory() as d:
        exc_path = os.path.join(d, "exceptions.json")
        with open(exc_path, "w") as f:
            json.dump(exc, f)
        rep_path = os.path.join(d, "report.json")
        for name, text, want_ok, sha in cases:
            with open(rep_path, "w") as f:
                f.write(text)
            print(f"--- {name}")
            if sha is None:
                rc = main([rep_path, exc_path])
            else:
                try:
                    rc = evaluate(json.loads(text), exc["mobsf"], sha)
                except ReportError as e:
                    print(f"FAIL (fail-closed): {e}")
                    rc = 1
            if (rc == 0) != want_ok:
                failures.append(f"{name}: expected {'pass' if want_ok else 'fail'}, got rc={rc}")

        good = os.path.join(d, "good.json")
        with open(good, "w") as f:
            json.dump(report(), f)
        print("--- missing report file fails")
        if main([os.path.join(d, "nope.json"), exc_path]) == 0:
            failures.append("missing report file: expected fail, got pass")
        print("--- exceptions file without 'mobsf' fails")
        bad_exc = os.path.join(d, "bad_exc.json")
        with open(bad_exc, "w") as f:
            f.write("{}")
        if main([good, bad_exc]) == 0:
            failures.append("exceptions file without 'mobsf': expected fail, got pass")
        print("--- --apk with a missing APK fails")
        if main([good, exc_path, "--apk", os.path.join(d, "missing.apk")]) == 0:
            failures.append("--apk missing: expected fail, got pass")

    print()
    if failures:
        for f in failures:
            print(f"SELF-TEST FAILED: {f}")
        return 1
    print("mobsf_summary self-test: all cases behaved as expected.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
