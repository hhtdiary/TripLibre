#!/usr/bin/env python3
"""Floor checks for `make calibrate-smoke` (synthetic fixture only; real-device numbers never reach CI)."""
import json
import sys

m = json.load(open(sys.argv[1]))
checks = {
    "time agreement ≥ 0.95": m["time_agreement"]["share"] >= 0.95,
    "visit F1 ≥ 0.9": (m["visits"]["f1"] or 0) >= 0.9,
    "trip F1 ≥ 0.9": (m["trips"]["f1"] or 0) >= 0.9,
    "visit arrival median abs ≤ 2 min": (m["visit_arrival_error"].get("median_abs_min") or 0) <= 2,
    "visit departure median abs ≤ 2 min": (m["visit_departure_error"].get("median_abs_min") or 0) <= 2,
}
for name, ok in checks.items():
    print(("ok   " if ok else "FAIL ") + name)
print(f"time agreement {m['time_agreement']['share']}, visits {m['visits']}, trips {m['trips']}")
sys.exit(0 if all(checks.values()) else 1)
