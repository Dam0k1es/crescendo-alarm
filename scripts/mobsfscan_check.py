#!/usr/bin/env python3
"""Fail if mobsfscan's JSON report contains an un-excepted ERROR-severity
finding. mobsfscan itself always runs with --no-fail (see
.github/workflows/security-gate.yml) so it never
blocks the pipeline on its own; this script is what actually enforces
docs/REQUIREMENTS.md R1 ("no SAST finding at severity high-or-above may be
outstanding" - mobsfscan's ERROR severity is that bar). Exceptions are
recorded in .github/security-exceptions.json with a written, dated
rationale, never silently swallowed.

Two properties added by the audit of 2026-10-05, each with a self-test case:
- **Fail closed.** A report that is missing, empty, not JSON, has no
  `results` object, or lists scan `errors` (part of the tree went
  unscanned) is a failure - it used to pass as "no findings". An ERROR rule
  reported without file locations is a finding too, not skipped.
- **Exceptions are scoped to files.** Each `mobsfscan` entry is
  `{"files": [...], "rationale": "..."}`; it accepts the rule only in the
  listed files (paths exactly as mobsfscan reports them, i.e. relative to
  the repository root because CI runs `mobsfscan android/`). A new instance
  of an accepted rule in another file fails. The old bare-string form, which
  accepted a rule everywhere, is rejected.

Usage: python3 scripts/mobsfscan_check.py <report.json> <exceptions.json>
       python3 scripts/mobsfscan_check.py --self-test
"""
import json
import os
import sys
import tempfile


class ReportError(Exception):
    pass


def _load(path: str, what: str):
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


def _exceptions(exc_file) -> dict[str, tuple[set[str], str]]:
    raw = exc_file.get("mobsfscan") if isinstance(exc_file, dict) else None
    if not isinstance(raw, dict):
        raise ReportError("exceptions file has no 'mobsfscan' object")
    out = {}
    for rule, entry in raw.items():
        if not (isinstance(entry, dict) and isinstance(entry.get("files"), list)
                and isinstance(entry.get("rationale"), str) and entry["rationale"].strip()
                and all(isinstance(p, str) for p in entry["files"])):
            raise ReportError(
                f"exception for {rule!r} must be {{\"files\": [...], \"rationale\": \"...\"}} "
                "- an unscoped exception would accept the rule in every file")
        out[rule] = (set(entry["files"]), entry["rationale"])
    return out


def evaluate(report, exceptions: dict[str, tuple[set[str], str]]) -> int:
    if not isinstance(report, dict):
        raise ReportError("report is not a JSON object")
    results = report.get("results")
    if not isinstance(results, dict):
        raise ReportError("report has no 'results' object - not a completed scan")
    errors = report.get("errors")
    if errors:
        raise ReportError(f"mobsfscan reported {len(errors)} scan error(s); part of the tree was not scanned")

    unexcepted = []
    for rule_id, finding in results.items():
        if not isinstance(finding, dict):
            raise ReportError(f"result {rule_id!r} is not an object")
        severity = finding.get("metadata", {}).get("severity")
        if severity != "ERROR":
            continue
        files = {f.get("file_path") for f in (finding.get("files") or []) if isinstance(f, dict)}
        if None in files or ("files" in finding and finding["files"] and not files):
            raise ReportError(f"result {rule_id!r} has a file entry without file_path")
        if rule_id not in exceptions:
            print(f"UNACCEPTED: {rule_id} (ERROR) in {sorted(files) or 'the app as a whole'}")
            unexcepted.append(rule_id)
            continue
        allowed, rationale = exceptions[rule_id]
        outside = sorted(files - allowed)
        if outside:
            print(f"UNACCEPTED: {rule_id} (ERROR) in {outside} - the exception covers only {sorted(allowed)}")
            unexcepted.append(rule_id)
        else:
            print(f"ACCEPTED: {rule_id} (ERROR) in {sorted(files)} - {rationale}")

    if unexcepted:
        print(
            f"\n{len(unexcepted)} un-excepted ERROR-severity mobsfscan "
            "finding(s). Fix them, or add a dated, reasoned, file-scoped exception "
            "to .github/security-exceptions.json."
        )
        return 1

    print("\nNo un-excepted ERROR-severity mobsfscan findings.")
    return 0


def main(argv: list[str]) -> int:
    if argv == ["--self-test"]:
        return self_test()
    if len(argv) != 2:
        print(__doc__)
        return 2
    try:
        report = _load(argv[0], "mobsfscan report")
        exceptions = _exceptions(_load(argv[1], "exceptions file"))
        return evaluate(report, exceptions)
    except ReportError as e:
        print(f"FAIL (fail-closed): {e}")
        return 1


def self_test() -> int:
    manifest = "android/app/src/main/AndroidManifest.xml"
    exc = {"mobsf": {}, "mobsfscan": {
        "android_task_hijacking2": {"files": [manifest], "rationale": "2026-09-09: reason"}}}

    def rep(results, errors=()):
        return json.dumps({"mobsfscan_version": "0.4", "results": results, "errors": list(errors)})

    def hit(severity, *paths):
        return {"metadata": {"severity": severity},
                "files": [{"file_path": p, "match_lines": [1, 1]} for p in paths] or None}

    cases = [
        ("no findings passes", rep({}), exc, True),
        ("INFO/WARNING findings pass", rep({"a": hit("INFO", "x.kt"), "b": hit("WARNING", "y.kt")}), exc, True),
        ("accepted rule in its recorded file passes", rep({"android_task_hijacking2": hit("ERROR", manifest)}), exc, True),
        ("accepted rule in another file fails",
         rep({"android_task_hijacking2": hit("ERROR", manifest, "android/app/src/debug/AndroidManifest.xml")}),
         exc, False),
        ("un-accepted ERROR fails", rep({"android_webview_debug": hit("ERROR", "x.kt")}), exc, False),
        ("ERROR without file locations fails", rep({"android_missing_x": hit("ERROR")}), exc, False),
        ("scan errors fail", rep({}, errors=[{"path": "x", "error": "parse"}]), exc, False),
        ("report without results fails", json.dumps({"errors": []}), exc, False),
        ("error reply fails", json.dumps({"error": "boom"}), exc, False),
        ("empty report fails", "", exc, False),
        ("malformed report fails", '{"results": {', exc, False),
        ("unscoped (string) exception is rejected",
         rep({"android_task_hijacking2": hit("ERROR", manifest)}),
         {"mobsfscan": {"android_task_hijacking2": "2026-09-09: reason"}}, False),
        ("exception without rationale is rejected",
         rep({}), {"mobsfscan": {"r": {"files": [], "rationale": ""}}}, False),
        ("exceptions file without 'mobsfscan' fails", rep({}), {"mobsf": {}}, False),
    ]
    failures = []
    with tempfile.TemporaryDirectory() as d:
        rp, ep = os.path.join(d, "report.json"), os.path.join(d, "exc.json")
        for name, text, exc_obj, want_ok in cases:
            with open(rp, "w") as f:
                f.write(text)
            with open(ep, "w") as f:
                json.dump(exc_obj, f)
            print(f"--- {name}")
            rc = main([rp, ep])
            if (rc == 0) != want_ok:
                failures.append(f"{name}: expected {'pass' if want_ok else 'fail'}, got rc={rc}")
        print("--- missing report file fails")
        if main([os.path.join(d, "nope.json"), ep]) == 0:
            failures.append("missing report file: expected fail, got pass")

    print()
    if failures:
        for f in failures:
            print(f"SELF-TEST FAILED: {f}")
        return 1
    print("mobsfscan_check self-test: all cases behaved as expected.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
