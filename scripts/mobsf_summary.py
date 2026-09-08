#!/usr/bin/env python3
"""Print a short HIGH/WARNING summary from a MobSF static-analyzer JSON report."""
import json
import sys

with open(sys.argv[1]) as f:
    report = json.load(f)

appsec = report.get("appsec", {})
high = appsec.get("high", [])
warning = appsec.get("warning", [])

print(f"HIGH: {len(high)}")
for finding in high:
    print(f" - {finding['title']}")

print(f"WARNING: {len(warning)}")
for finding in warning:
    print(f" - {finding['title']}")
