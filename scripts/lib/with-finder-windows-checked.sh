#!/bin/zsh

set -euo pipefail
unsetopt BG_NICE

readonly script_path="${0:A}"
readonly project_root="${script_path:h:h:h}"
readonly run_name="$(date '+%Y%m%d-%H%M%S')-finder-windows-$$"
readonly test_directory="$project_root/.artifacts/scratch/tests/$run_name"
readonly log_directory="$project_root/.artifacts/scratch/logs/$run_name"
readonly helper="$test_directory/FinderWindowCheck"
readonly source_directory="$project_root/Tests/FinderWindowPreservation"
readonly developer_directory="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if (( $# == 0 )); then
    print -u2 "Usage: with-finder-windows-checked.sh <test-command> [argument ...]"
    exit 64
fi
if [[ -n "${ECMENU_FINDER_WINDOW_SESSION:-}" ]]; then
    exec "$@"
fi
if [[ -n "${ECMENU_USER_FOCUS_SESSION:-}" ]]; then
    print -u2 "Finder window checking must start outside the focus-restoration session."
    exit 64
fi

mkdir -p "$test_directory/module-cache" "$log_directory"
if DEVELOPER_DIR="$developer_directory" xcrun swiftc \
    -module-cache-path "$test_directory/module-cache" \
    "$source_directory/FinderWindowSnapshot.swift" \
    "$source_directory/FinderWindowCheck.swift" \
    -framework AppKit -framework CoreGraphics \
    -o "$helper" >"$log_directory/build.log" 2>&1; then
    :
else
    build_status=$?
    print -u2 "Finder window check build failed: $log_directory/build.log"
    tail -n 100 "$log_directory/build.log" >&2
    exit "$build_status"
fi

if "$helper" capture "$test_directory/before.json" \
    >"$log_directory/windows.log" 2>&1; then
    :
else
    capture_status=$?
    print -u2 "Could not snapshot Finder windows: $log_directory/windows.log"
    exit "$capture_status"
fi

verify_finder_windows() {
    local exit_status=$?
    local verification_status=0

    trap - EXIT
    trap '' HUP INT TERM
    "$helper" verify "$test_directory/before.json" "$test_directory/after.json" \
        >>"$log_directory/windows.log" 2>&1 || verification_status=$?
    if (( verification_status != 0 )); then
        print -u2 "Finder window preservation check failed. Snapshots: $test_directory"
        cat "$log_directory/windows.log" >&2
        (( exit_status != 0 )) || exit_status=$verification_status
    else
        tail -n 1 "$log_directory/windows.log"
        print "Finder window snapshots: $test_directory"
    fi
    exit "$exit_status"
}

terminate_test() {
    local signal_name="$1"
    local signal_status="$2"

    trap '' HUP INT TERM
    if [[ -n "$child_pid" ]]; then
        # 测试入口的焦点包装器负责向整个测试进程组转发信号并等待清理。
        kill -s "$signal_name" "$child_pid" 2>/dev/null || true
        wait "$child_pid" 2>/dev/null || true
        child_pid=""
    fi
    exit "$signal_status"
}

trap verify_finder_windows EXIT
trap 'terminate_test HUP 129' HUP
trap 'terminate_test INT 130' INT
trap 'terminate_test TERM 143' TERM

child_pid=""
ECMENU_FINDER_WINDOW_SESSION="$run_name" "$@" &
child_pid=$!
if wait "$child_pid"; then
    child_status=0
else
    child_status=$?
fi
child_pid=""
exit "$child_status"
