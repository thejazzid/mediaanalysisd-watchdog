#!/bin/bash
# analysis-watchdog: keep Apple's photo/video analysis daemons suspended.
#
# macOS (with SIP on) will not let a user disable mediaanalysisd/photoanalysisd,
# and launchd restarts them on demand if they are killed. A SIGSTOP'd process
# still counts as "running" to launchd, so it is never respawned and does no work.
#
# Usage: analysis-watchdog.sh [run|once|status|resume]
#   run     loop forever, pausing targets as they appear (used by the LaunchAgent)
#   once    pause targets once and exit
#   status  show target processes and their state (T = paused)
#   resume  un-pause targets (they continue where they left off)
set -u

INTERVAL="${WATCHDOG_INTERVAL:-3}"   # seconds between checks
LOG="${WATCHDOG_LOG:-$HOME/Library/Logs/analysis-watchdog.log}"
MAX_LOG_BYTES=1048576                # rotate at 1 MB, keep one old file
TARGETS="mediaanalysisd photoanalysisd"
UID_NUM="$(id -u)"

log() {
    if [ -f "$LOG" ] && [ "$(stat -f %z "$LOG")" -gt "$MAX_LOG_BYTES" ]; then
        mv -f "$LOG" "$LOG.1"
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

# Send a signal to every target process not already in the wanted state.
# $1 = STOP|CONT
signal_targets() {
    local sig="$1" name pid state
    for name in $TARGETS; do
        for pid in $(pgrep -x -u "$UID_NUM" "$name"); do
            state="$(ps -o stat= -p "$pid" 2>/dev/null)" || continue
            case "$sig:$state" in
                STOP:T*|CONT:[!T]*) continue ;;   # already paused / already running
            esac
            if kill -"$sig" "$pid" 2>/dev/null; then
                log "$( [ "$sig" = STOP ] && echo paused || echo resumed ) $name pid=$pid"
            fi
        done
    done
}

status() {
    local name pid found=0
    printf '%-16s %7s %-6s %10s %s\n' NAME PID STATE CPU_TIME RUNNING_FOR
    for name in $TARGETS; do
        for pid in $(pgrep -x -u "$UID_NUM" "$name"); do
            found=1
            ps -o comm=,pid=,stat=,time=,etime= -p "$pid" |
                awk -v n="$name" '{s=($3 ~ /^T/) ? "paused" : "ACTIVE"; printf "%-16s %7s %-6s %10s %s\n", n, $2, s, $4, $5}'
        done
    done
    [ "$found" = 1 ] || echo "(no target processes running)"
}

case "${1:-run}" in
    run)
        log "watchdog started (pid $$, every ${INTERVAL}s)"
        # On stop (uninstall/bootout), leave nothing frozen behind.
        trap 'log "watchdog stopping; resuming targets"; signal_targets CONT; exit 0' TERM INT HUP
        while :; do
            signal_targets STOP
            sleep "$INTERVAL" & wait $!
        done
        ;;
    once)   signal_targets STOP ;;
    resume) signal_targets CONT ;;
    status) status ;;
    *) echo "usage: $0 [run|once|status|resume]" >&2; exit 2 ;;
esac
