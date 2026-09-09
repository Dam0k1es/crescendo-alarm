#!/usr/bin/env python3
"""Fail if mobsfscan's JSON report contains an un-excepted ERROR-severity
finding. mobsfscan itself always runs with --no-fail (see ci.yml) so it never
blocks the pipeline on its own; this script is what actually enforces
docs/REQUIREMENTS.md R1 ("no SAST finding at severity high-or-above may be
outstanding" - mobsfscan's ERROR severity is that bar). Exceptions are
recorded in .github/security-exceptions.json with a written, dated
rationale, never silently swallowed.
"""
import json
import sys


def main(report_path: str, exceptions_path: str) -> int:
    with open(report_path) as f:
        report = json.load(f)
    with open(exceptions_path) as f:
        exceptions = json.load(f).get("mobsfscan", {})

    unexcepted = []
    for rule_id, finding in report.get("results", {}).items():
        severity = finding.get("metadata", {}).get("severity")
        if severity != "ERROR" or not finding.get("files"):
            continue
        if rule_id in exceptions:
            print(f"ACCEPTED: {rule_id} (ERROR) - {exceptions[rule_id]}")
        else:
            print(f"UNACCEPTED: {rule_id} (ERROR) - not in {exceptions_path}")
            unexcepted.append(rule_id)

    if unexcepted:
        print(
            f"\n{len(unexcepted)} un-excepted ERROR-severity mobsfscan "
            f"finding(s). Fix them, or add a dated, reasoned exception to "
            f"{exceptions_path}."
        )
        return 1

    print("\nNo un-excepted ERROR-severity mobsfscan findings.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
