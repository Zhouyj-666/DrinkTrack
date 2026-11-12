#!/usr/bin/env python3
"""Pick an available iPhone simulator for CI.

Preference: iPhone 16 on iOS 18.5 > iPhone 16 on newest iOS 18.x > any iPhone 16
> any iPhone on the newest iOS runtime. Prints "UDID|runtime|name" to stdout.
"""
import json
import subprocess
import sys

data = json.loads(subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"]


def ios_version(runtime):
    if "iOS-" not in runtime:
        return None
    try:
        return tuple(int(p) for p in runtime.split("iOS-")[1].split("-"))
    except ValueError:
        return None


candidates = []
for runtime, devices in data.items():
    ver = ios_version(runtime)
    if ver is None:
        continue
    for d in devices:
        name = d.get("name", "")
        if not name.startswith("iPhone"):
            continue
        score = 0
        if name == "iPhone 16":
            score += 100
        if ver[0] == 18:
            score += 50
        if ver[:2] == (18, 5):
            score += 25
        candidates.append((score, ver, d["udid"], runtime, name))

if not candidates:
    sys.exit("No iPhone simulator available")

candidates.sort(key=lambda c: (c[0], c[1]), reverse=True)
best = candidates[0]
print(f"{best[2]}|{best[3]}|{best[4]}")
