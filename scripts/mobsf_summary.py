#!/usr/bin/env python3
"""Print a HIGH/WARNING summary from a MobSF static-analyzer JSON report, and
fail if any HIGH finding isn't recorded as an accepted exception in
.github/security-exceptions.json - see docs/REQUIREMENTS.md R1. Previously
this only printed counts with no threshold, so a new HIGH finding could
leave the pipeline green (docs/TODO.md T-11).
"""
import json
import sys


def main(report_path: str, exceptions_path: str | None) -> int:
    with open(report_path) as f:
        report = json.load(f)

    exceptions = {}
    if exceptions_path:
        with open(exceptions_path) as f:
            exceptions = json.load(f).get("mobsf", {})

    appsec = report.get("appsec", {})
    high = appsec.get("high", [])
    warning = appsec.get("warning", [])

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
        exc_desc = exceptions_path or "(no exceptions file given)"
        print(
            f"\n{len(unaccepted)} un-excepted HIGH finding(s). Fix them, or "
            f"add a dated, reasoned exception to {exc_desc}."
        )
        return 1

    print("\nNo un-excepted HIGH findings.")
    return 0


if __name__ == "__main__":
    exceptions_arg = sys.argv[2] if len(sys.argv) > 2 else None
    sys.exit(main(sys.argv[1], exceptions_arg))
