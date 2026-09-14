#!/bin/bash
#
# Watches a Retain recording and reports what the three power rules cost.
#
# Retain is meant to run for a whole school day on battery, and the three things
# that decide whether it can are not visible from inside the app: whether the
# power hint actually reached the bundle, whether anything is holding the
# display awake, and what the process draws over a real lecture. This runs
# alongside a recording and answers all three.
#
# Usage:
#     scripts/audio-acceptance.sh [minutes]          # default 90
#
# Start it, then start a recording from the menu bar. Leave the lid open and the
# machine on battery; the point is the number a student would actually pay.
#
# powermetrics needs root, so this asks for a password once. Nothing else here
# does.

set -uo pipefail

MINUTES="${1:-90}"
SECONDS_TOTAL=$(( MINUTES * 60 ))
SAMPLE_INTERVAL=30

OUT="${TMPDIR:-/tmp}/retain-acceptance-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

echo "Retain audio acceptance"
echo "  duration   ${MINUTES} minutes"
echo "  output     ${OUT}"
echo

# ---------------------------------------------------------------- hard rule 1

APP=$(mdfind "kMDItemCFBundleIdentifier == 'apps.levo-studio.Retain'" 2>/dev/null | head -1)
if [ -z "$APP" ]; then
    echo "! Retain.app not found by Spotlight. Build it, then run it once."
    exit 1
fi

echo "Bundle: $APP"
HINT=$(plutil -extract AudioHardwarePowerHint raw "$APP/Contents/Info.plist" 2>/dev/null)
if [ "$HINT" = "Favor Saving Power" ]; then
    echo "  rule 1  AudioHardwarePowerHint present"
else
    echo "  rule 1  FAILED — AudioHardwarePowerHint is '${HINT:-missing}'"
fi
echo

# ------------------------------------------------------------------- baseline

if ! pgrep -x Retain > /dev/null; then
    echo "Retain is not running. Start it and begin a recording, then run this again."
    exit 1
fi

PID=$(pgrep -x Retain | head -1)
echo "Retain is running as pid ${PID}. Start the recording now if you have not."
echo "Sampling every ${SAMPLE_INTERVAL}s for ${MINUTES} minutes."
echo

sudo -v || { echo "powermetrics needs root"; exit 1; }

sudo powermetrics --samplers cpu_power,tasks --show-process-energy \
    -i $(( SAMPLE_INTERVAL * 1000 )) -n $(( SECONDS_TOTAL / SAMPLE_INTERVAL )) \
    > "$OUT/powermetrics.txt" 2>&1 &
POWER_PID=$!

# ---------------------------------------------------------------------- watch

ELAPSED=0
ASSERTION_VIOLATIONS=0

while [ $ELAPSED -lt $SECONDS_TOTAL ]; do
    sleep $SAMPLE_INTERVAL
    ELAPSED=$(( ELAPSED + SAMPLE_INTERVAL ))

    if ! pgrep -x Retain > /dev/null; then
        echo "! Retain exited after ${ELAPSED}s"
        break
    fi

    # Hard rules 2 and 8: nothing Retain owns may keep the display awake.
    pmset -g assertions >> "$OUT/assertions.txt"
    if pmset -g assertions | grep -i -A2 "PreventUserIdleDisplaySleep" | grep -qi retain; then
        ASSERTION_VIOLATIONS=$(( ASSERTION_VIOLATIONS + 1 ))
        echo "! ${ELAPSED}s  RULE 2 VIOLATION: Retain holds a display-sleep assertion"
    fi

    # Hard rule 3: polling Core Audio shows up as coreaudiod burning CPU.
    COREAUDIO=$(ps -o %cpu= -p "$(pgrep -x coreaudiod | head -1)" 2>/dev/null | tr -d ' ')
    RETAIN_CPU=$(ps -o %cpu= -p "$PID" 2>/dev/null | tr -d ' ')
    RETAIN_RSS=$(ps -o rss= -p "$PID" 2>/dev/null | tr -d ' ')

    printf "%5ss  Retain %5s%% CPU  %6s KB RSS   coreaudiod %5s%%\n" \
        "$ELAPSED" "${RETAIN_CPU:-?}" "${RETAIN_RSS:-?}" "${COREAUDIO:-?}" \
        | tee -a "$OUT/samples.txt"
done

kill $POWER_PID 2>/dev/null
wait $POWER_PID 2>/dev/null

# --------------------------------------------------------------------- report

echo
echo "----------------------------------------------------------------"

RECORDINGS="$HOME/Library/Application Support/Retain/Recordings"
NEWEST=$(ls -t "$RECORDINGS"/*.caf 2>/dev/null | head -1)
if [ -n "$NEWEST" ]; then
    echo "Recording: $NEWEST"
    afinfo "$NEWEST" 2>/dev/null | grep -E "file format|estimated duration|data size|bit"
else
    echo "! No recording found in $RECORDINGS"
fi

echo
if [ "$ASSERTION_VIOLATIONS" -eq 0 ]; then
    echo "rule 2  clean — no display-sleep assertion from Retain in any sample"
else
    echo "rule 2  FAILED in ${ASSERTION_VIOLATIONS} samples — this is a P0"
fi

echo
echo "Energy impact over the run (powermetrics, Retain only):"
grep -i "retain" "$OUT/powermetrics.txt" 2>/dev/null | tail -20 || echo "  no samples captured"

echo
echo "Everything is in $OUT"
