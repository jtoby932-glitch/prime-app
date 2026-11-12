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
shot 08-muscle-map 7 -demo -route muscle:chest
shot 09-rank-bench 7 -demo -route rank:barbell-bench-press
shot 10-exercise-squat 7 -demo -route exercise:barbell-back-squat
shot 11-records 6 -demo -route records
shot 13-reveal-analysis 6 -demo -reveal barbell-bench-press -revealStage analysis
shot 14-reveal-tier 7 -demo -reveal barbell-bench-press -revealStage reveal
shot 15-reveal-breakdown 7 -demo -reveal barbell-bench-press -revealStage breakdown
shot 16-presets 6 -demo -sheet presets
shot 17-search 6 -demo -sheet search
shot 18-category-back 6 -demo -route category:back
shot 19-methodology 6 -demo -route methodology
shot 20-preferences 6 -demo -route preferences
shot 21-exercise-plank 7 -demo -route exercise:plank
shot 22-guide-bench 7 -demo -guide barbell-bench-press
shot 23-detail-bench 7 -demo -route exercise:barbell-bench-press
# Last: the workout it starts persists and would cover later screens.
shot 24-active-workout 8 -demo -activeWorkout

# Short recordings of the motion, converted to GIFs for review.
record() {
  local name="$1" seconds="$2"; shift 2
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl io "$UDID" recordVideo --codec h264 --force "$OUT/$name.mp4" >/dev/null 2>&1 &
  local pid=$!
  sleep 1.5
  xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
  sleep "$seconds"
  kill -INT "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  if command -v ffmpeg >/dev/null && [ -s "$OUT/$name.mp4" ]; then
    ffmpeg -loglevel error -y -i "$OUT/$name.mp4" -vf "fps=12,scale=300:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer" "$OUT/$name.gif" \
      && rm -f "$OUT/$name.mp4" && echo "recorded $name"
  else
    echo "kept $name.mp4 (no ffmpeg)"
  fi
}

record m1-tour 14 -demo -tour
record m2-reveal 11 -demo -reveal barbell-bench-press -revealStage play
record m3-onboarding 6

# Crash reports, if any, help diagnose a blank screenshot.
find ~/Library/Logs/DiagnosticReports -name "PRIME*" -newer "$APP" -exec cp {} "$OUT/" \; 2>/dev/null || true
ls -1 "$OUT"
