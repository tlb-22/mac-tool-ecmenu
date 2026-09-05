#!/bin/zsh

set -euo pipefail

readonly script_path="${0:A}"
readonly script_directory="${script_path:h}"
readonly project_root="${script_directory:h}"
readonly preview_operation_lock_directory="$project_root/.artifacts/scratch/probes"
readonly preview_operation_lock="$preview_operation_lock_directory/preview-operation.lock"

if [[ "${ECMENU_PREVIEW_OPERATION_LOCK:-}" != "$preview_operation_lock" ]]; then
    mkdir -p "$preview_operation_lock_directory"
    exec /usr/bin/lockf \
        -k \
        -t 0 \
        "$preview_operation_lock" \
        /usr/bin/env \
        ECMENU_PREVIEW_OPERATION_LOCK="$preview_operation_lock" \
        "$script_path" \
        "$@"
fi

readonly derived_data_path="$project_root/.derivedData"
readonly run_timestamp="$(date '+%Y%m%d-%H%M%S')"
readonly app_path="$derived_data_path/Build/Products/Debug/ECMenuPreviews.app"
readonly preview_executable="$app_path/Contents/MacOS/ECMenuPreviews"
readonly log_directory="$project_root/.artifacts/scratch/logs"
readonly build_log="$log_directory/$run_timestamp-preview-ui-$$.log"
readonly developer_directory="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
readonly destination="${XCODE_DESTINATION:-platform=macOS,arch=arm64}"

usage() {
    print "Usage: ./scripts/preview-ui.sh <preview-id> [--language <en|zh-Hans>]"
    print "       ./scripts/preview-ui.sh --list"
    print "Examples:"
    print "  ./scripts/preview-ui.sh --list"
    print "  ./scripts/preview-ui.sh context-command-progress-single"
    print "  ./scripts/preview-ui.sh status-page-general --language en"
    print "  ./scripts/preview-ui.sh status-page-context-menu --language zh-Hans"
}

if (( $# == 0 )) || [[ -z "$1" ]]; then
    usage >&2
    exit 64
fi

readonly preview_id="$1"
language=""

if [[ "$preview_id" == --list ]]; then
    if (( $# != 1 )); then
        usage >&2
        exit 64
    fi
elif [[ "$preview_id" == --* ]]; then
    usage >&2
    exit 64
elif (( $# == 1 )); then
    :
elif (( $# == 3 )) && [[ "$2" == --language ]]; then
    case "$3" in
        en|zh-Hans)
            language="$3"
            ;;
        *)
            print -u2 "Unsupported preview language: $3"
            usage >&2
            exit 64
            ;;
    esac
else
    usage >&2
    exit 64
fi

readonly language

source "$script_directory/lib/process-lifecycle.sh"

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

previous_preview_pids="$(process_ids_for_executable "$preview_executable")"
terminate_process_ids "$previous_preview_pids"
if ! wait_for_process_ids_to_exit "$previous_preview_pids" 30; then
    print -u2 "Previous preview app did not exit: $preview_executable"
    exit 1
fi

launch_arguments=(--preview-ui "$preview_id")
if [[ -n "$language" ]]; then
    launch_arguments+=(-AppleLanguages "($language)")
fi

open -n "$app_path" --args "${launch_arguments[@]}"

if ! wait_for_process "$preview_executable"; then
    print -u2 "Preview app did not start: $preview_executable"
    exit 2
fi

preview_pids=("${(@f)$(process_ids_for_executable "$preview_executable")}")
if (( ${#preview_pids[@]} != 1 )); then
    print -u2 "Expected one preview app process, found ${#preview_pids[@]}."
    exit 3
fi

preview_command="$(ps -p "$preview_pids[1]" -o command=)"
expected_command="$preview_executable ${(j: :)launch_arguments}"
if [[ "$preview_command" != "$expected_command" ]]; then
    print -u2 "Preview app has unexpected arguments: $preview_command"
    exit 4
fi

print "UI preview running: $preview_id"
if [[ -n "$language" ]]; then
    print "Language: $language"
else
    print "Language: system"
fi
print "Preview app: $preview_pids[1]"
print "Build log: $build_log"
