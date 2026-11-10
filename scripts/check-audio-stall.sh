#!/usr/bin/env bash
# Drive pause, play, seek and track changes on the running Waydroid session and
# report whether audioserver survived. Optionally suspend the host sink to force
# a PulseAudio stall.
#
# Run as your own user, not under sudo: pactl must reach your pipewire-pulse.
# The script calls `sudo waydroid shell` itself, so it may ask for your password.
#
# Usage: scripts/check-audio-stall.sh [-d SECONDS] [-s SECONDS] [-n]
#   -d SECONDS  how long to run (default 120)
#   -s SECONDS  suspend the default sink for this long, halfway through the run
#   -n          send no media commands (use with -s to check that playback
#               resumes on its own after the stall)
# Exit: 0 PASS, 1 FAIL, 2 could not run.
set -euo pipefail

duration=120
stall=0
commands=1
while getopts "d:s:nh" opt; do
    case $opt in
        d) duration=$OPTARG ;;
        s) stall=$OPTARG ;;
        n) commands=0 ;;
        *) sed -n '2,14p' "$0"; exit 2 ;;
    esac
done

if [[ $EUID -eq 0 ]]; then
    echo "Run this as your own user, not with sudo (pactl needs your audio session)." >&2
    exit 2
fi

wd() { sudo waydroid shell -- "$@" | tr -d '\r'; }
pid() { wd pidof audioserver || true; }
newest_tombstone() { wd sh -c 'ls -t /data/tombstones 2>/dev/null | head -n 1'; }
# waydroid shell drops the container command's exit status, so a failed dispatch is not visible here.
dispatch() { wd sh -c "$1" >/dev/null 2>&1; }
# Waydroid sink inputs on the host that are not corked, i.e. actually playing.
playing_streams() {
    pactl list sink-inputs | awk '/^Sink Input/ {c = ""} /Corked:/ {c = $2}
        /application.id = "id.waydro.waydroid"/ && c == "no" {n++} END {print n + 0}'
}

if ! waydroid status 2>/dev/null | grep -Eq 'Session:[[:space:]]+RUNNING'; then
    echo "Waydroid session is not running. Start it with 'waydroid session start' and play a track." >&2
    exit 2
fi

pid_before=$(pid)
if [[ -z $pid_before ]]; then
    echo "audioserver is not running in the container." >&2
    exit 2
fi
tomb_before=$(newest_tombstone)
# logcat prints the container's local time, so take the start time from the container.
start_time=$(wd date '+%m-%d %H:%M:%S.000')
if [[ $(playing_streams) -eq 0 ]]; then
    echo "No Waydroid stream is playing on the host. Start a track first." >&2
    exit 2
fi

sink=""  # the suspended sink, if any
resume_sink() {
    [[ -n $sink ]] || return 0
    if pactl suspend-sink "$sink" 0; then
        echo "sink $sink resumed"
    else
        echo "WARNING: could not resume sink $sink. Run: pactl suspend-sink $sink 0" >&2
    fi
    sink=""
}
trap resume_sink EXIT
trap 'exit 130' INT TERM

echo "audioserver pid $pid_before, newest tombstone '${tomb_before:-none}', start $start_time"
echo "running for ${duration}s, commands=$commands, stall=${stall}s"

end=$((SECONDS + duration))
stall_at=$((SECONDS + duration / 2))
stall_done=0
# Mostly pause and play, which corks and uncorks the stream; seeks and skips flush and refill it.
actions=(pause play pause play fast-forward rewind next previous)
while ((SECONDS < end)); do
    if ((stall > 0 && stall_done == 0 && SECONDS >= stall_at)); then
        s=$(pactl get-default-sink)
        echo "suspending sink $s for ${stall}s"
        if pactl suspend-sink "$s" 1; then sink=$s; else echo "could not suspend sink $s" >&2; fi
        sleep "$stall"
        resume_sink
        stall_done=1
        continue
    fi
    if ((commands == 1)); then
        action=${actions[RANDOM % ${#actions[@]}]}
        # Play again after anything but pause, so the next command hits a running stream.
        if [[ $action == pause ]]; then
            dispatch "cmd media_session dispatch pause"
        else
            dispatch "cmd media_session dispatch $action && cmd media_session dispatch play"
        fi
    fi
    sleep "$((RANDOM % 3)).$((RANDOM % 10))"
done
((commands == 0)) || dispatch "cmd media_session dispatch play"
sleep 3
playing_after=$(playing_streams)

pid_after=$(pid)
tomb_after=$(newest_tombstone)
log=$(wd logcat -d -T "$start_time" 2>/dev/null || true)
timecheck=$(grep -F 'TimeCheck timeout' <<<"$log" || true)
pulse=$(grep -E 'AHAL_StreamPulse.*(stalled|recovered|not ready|Failed to write)' <<<"$log" || true)

echo
echo "audioserver pid: before $pid_before, after ${pid_after:-none}"
echo "newest tombstone: before '${tomb_before:-none}', after '${tomb_after:-none}'"
[[ -z $timecheck ]] || printf 'watchdog lines:\n%s\n' "$timecheck"
[[ -z $pulse ]] || printf 'HAL stall lines:\n%s\n' "$pulse"
if ((stall > 0)) && ! grep -q stalled <<<"$pulse"; then
    echo "note: no stall warning was logged, so the sink suspend may not have stalled the stream"
fi

fail=()
[[ -n $pid_after ]] || fail+=("audioserver is not running")
[[ -z $pid_after || $pid_after == "$pid_before" ]] || fail+=("audioserver restarted, new pid $pid_after")
[[ $tomb_after == "$tomb_before" ]] || fail+=("new tombstone $tomb_after")
[[ -z $timecheck ]] || fail+=("watchdog timeout logged")
((playing_after > 0)) || fail+=("no Waydroid stream is playing on the host at the end")

if ((${#fail[@]})); then
    printf 'FAIL: %s\n' "${fail[@]}"
    exit 1
fi
echo "PASS"
