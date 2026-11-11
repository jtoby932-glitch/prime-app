#!/bin/bash
# Installs a Debug simulator build and captures every main screen with demo data.
# Usage: tools/screenshots.sh <simulator-udid> <path/to/PRIME.app> <output-dir>
set -uo pipefail
UDID="$1"; APP="$2"; OUT="$3"
BUNDLE=com.savonstudios.prime
mkdir -p "$OUT"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" appearance dark || true
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$UDID" "$APP"

shot() {
  local name="$1" wait="$2"; shift 2
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
  sleep "$wait"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null 2>&1 && echo "captured $name"
}

shot 01-onboarding 6
shot 02-home 12 -demo -tab home
shot 03-workouts 6 -demo -tab workouts
shot 04-exercises 6 -demo -tab exercises
shot 05-rankings 7 -demo -tab rankings
shot 06-profile 6 -demo -tab profile
shot 07-analytics 7 -demo -route analytics
shot 08-muscle-map 7 -demo -route muscleMap
shot 09-rank-bench 7 -demo -route rank:barbell-bench-press
shot 10-exercise-squat 7 -demo -route exercise:barbell-back-squat
shot 11-records 6 -demo -route records
shot 12-active-workout 8 -demo -activeWorkout

# Crash reports, if any, help diagnose a blank screenshot.
find ~/Library/Logs/DiagnosticReports -name "PRIME*" -newer "$APP" -exec cp {} "$OUT/" \; 2>/dev/null || true
ls -1 "$OUT"
