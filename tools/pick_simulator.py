#!/usr/bin/env python3
"""Prints the UDID of an available iPhone simulator on the newest iOS runtime."""
import json
import re
import subprocess

data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
best = None
for runtime, devices in data["devices"].items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in devices:
        if device.get("isAvailable", True) and device["name"].startswith("iPhone"):
            # Prefer the newest runtime, then a standard (non Plus/Pro Max) size.
            score = (version, "Max" not in device["name"] and "Plus" not in device["name"])
            if best is None or score > best[0]:
                best = (score, device["udid"])
if best is None:
    raise SystemExit("No iPhone simulator available")
print(best[1])
