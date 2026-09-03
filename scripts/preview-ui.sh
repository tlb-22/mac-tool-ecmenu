#!/bin/zsh

set -euo pipefail

readonly script_directory="${0:A:h}"
readonly project_root="${script_directory:h}"
readonly derived_data_path="$project_root/.derivedData"
readonly run_timestamp="$(date '+%Y%m%d-%H%M%S')"
readonly app_path="$derived_data_path/Build/Products/Debug/ECMenuPreviews.app"
readonly preview_executable="$app_path/Contents/MacOS/ECMenuPreviews"
readonly log_directory="$project_root/.artifacts/scratch/logs"
readonly build_log="$log_directory/$run_timestamp-preview-ui-$$.log"
readonly developer_directory="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
readonly destination="${XCODE_DESTINATION:-platform=macOS,arch=arm64}"

usage() {
    print "Usage: ./scripts/preview-ui.sh <preview-id|--list>"
    print "Examples:"
    print "  ./scripts/preview-ui.sh --list"
    print "  ./scripts/preview-ui.sh context-command-progress"
}

if (( $# != 1 )) || [[ -z "$1" ]] || [[ "$1" == --* && "$1" != --list ]]; then
    usage >&2
    exit 64
fi

readonly preview_id="$1"

process_ids_for_preview_app() {
    local candidates
    local command_path
    local pid

    candidates="$(pgrep -f "$preview_executable" 2>/dev/null || true)"
    if [[ -z "$candidates" ]]; then
        return 0
    fi

    for pid in "${(@f)candidates}"; do
        command_path="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
        if [[ "$command_path" == "$preview_executable" ]]; then
            print "$pid"
        fi
    done
}

wait_for_process() {
    local attempt

    for attempt in {1..30}; do
        if [[ -n "$(process_ids_for_preview_app)" ]]; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

wait_for_process_exit() {
    local attempt

    for attempt in {1..30}; do
        if [[ -z "$(process_ids_for_preview_app)" ]]; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

terminate_preview_processes() {
    local process_ids
    local pid

    process_ids="$(process_ids_for_preview_app)"
    if [[ -z "$process_ids" ]]; then
        return 0
    fi

    for pid in "${(@f)process_ids}"; do
        kill "$pid" 2>/dev/null || true
    done
}

mkdir -p "$log_directory"
cd "$project_root"

if DEVELOPER_DIR="$developer_directory" xcodebuild \
    -project ECMenu.xcodeproj \
    -scheme ECMenuPreviews \
    -configuration Debug \
    -destination "$destination" \
    -derivedDataPath "$derived_data_path" \
    build -quiet >"$build_log" 2>&1; then
    :
else
    build_status=$?
    print -u2 "Preview build failed. Log: $build_log"
    tail -n 200 "$build_log" >&2
    exit "$build_status"
fi

if [[ "$preview_id" == --list ]]; then
    "$preview_executable" --list
    print "Build log: $build_log"
    exit 0
fi

terminate_preview_processes
if ! wait_for_process_exit; then
    print -u2 "Previous preview app did not exit: $preview_executable"
    exit 1
fi

open -n "$app_path" --args --preview-ui "$preview_id"

if ! wait_for_process; then
    print -u2 "Preview app did not start: $preview_executable"
    exit 2
fi

preview_pids=("${(@f)$(process_ids_for_preview_app)}")
if (( ${#preview_pids[@]} != 1 )); then
    print -u2 "Expected one preview app process, found ${#preview_pids[@]}."
    exit 3
fi

preview_command="$(ps -p "$preview_pids[1]" -o command=)"
expected_command="$preview_executable --preview-ui $preview_id"
if [[ "$preview_command" != "$expected_command" ]]; then
    print -u2 "Preview app has unexpected arguments: $preview_command"
    exit 4
fi

print "UI preview running: $preview_id"
print "Preview app: $preview_pids[1]"
print "Build log: $build_log"
