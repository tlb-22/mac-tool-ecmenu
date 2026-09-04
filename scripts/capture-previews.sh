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
readonly output_directory="$project_root/.artifacts/scratch/previews/$run_timestamp-localized-previews-$$"
readonly log_directory="$project_root/.artifacts/scratch/logs/$run_timestamp-localized-previews-$$"
readonly build_log="$log_directory/build.log"
readonly capture_log="$log_directory/capture.log"
readonly developer_directory="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
readonly destination="${XCODE_DESTINATION:-platform=macOS,arch=arm64}"
readonly -a languages=(en zh-Hans)

active_preview_pid=""

usage() {
    print "Usage: ./scripts/capture-previews.sh"
}

log() {
    print -r -- "$1"
    print -r -- "$1" >>"$capture_log"
}

fail() {
    local message="$1"

    print -u2 -r -- "$message"
    print -r -- "ERROR: $message" >>"$capture_log"
    print -u2 "Capture log: $capture_log"
    exit 1
}

terminate_active_preview() {
    local attempt
    local process_state
    local pid="${active_preview_pid:-}"

    [[ -n "$pid" ]] || return 0

    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true

        for attempt in {1..30}; do
            process_state="$(ps -p "$pid" -o state= 2>/dev/null || true)"
            if [[ -z "$process_state" || "$process_state" == *Z* ]]; then
                break
            fi
            sleep 0.1
        done

        process_state="$(ps -p "$pid" -o state= 2>/dev/null || true)"
        if [[ -n "$process_state" && "$process_state" != *Z* ]]; then
            kill -KILL "$pid" 2>/dev/null || true
        fi
    fi

    wait "$pid" 2>/dev/null || true
    active_preview_pid=""
}

cleanup() {
    terminate_active_preview
}

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

terminate_existing_previews() {
    local process_ids
    local pid

    process_ids="$(process_ids_for_preview_app)"
    if [[ -z "$process_ids" ]]; then
        return 0
    fi

    for pid in "${(@f)process_ids}"; do
        kill "$pid" 2>/dev/null || true
    done

    for _ in {1..30}; do
        if [[ -z "$(process_ids_for_preview_app)" ]]; then
            return 0
        fi
        sleep 0.1
    done

    fail "A previous Preview process did not exit: $preview_executable"
}

wait_for_ready_window() {
    local pid="$1"
    local stdout_log="$2"
    local attempt
    local window_id

    for attempt in {1..300}; do
        window_id="$(
            /usr/bin/awk '
                $1 == "READY" && $2 ~ /^[0-9]+$/ && NF == 2 {
                    print $2
                    exit
                }
            ' "$stdout_log"
        )"
        if [[ -n "$window_id" ]]; then
            print -r -- "$window_id"
            return 0
        fi
        if ! kill -0 "$pid" 2>/dev/null; then
            return 1
        fi
        sleep 0.1
    done

    return 1
}

wait_for_capture_verdict() {
    local pid="$1"
    local stdout_log="$2"
    local attempt
    local verdict

    for attempt in {1..100}; do
        verdict="$(
            /usr/bin/awk '
                ($1 == "CAPTURED" || $1 == "FOCUS_LOST") && $2 ~ /^[0-9]+$/ && NF == 2 {
                    print $1 " " $2
                    exit
                }
            ' "$stdout_log"
        )"
        if [[ -n "$verdict" ]]; then
            print -r -- "$verdict"
            return 0
        fi
        if ! kill -0 "$pid" 2>/dev/null; then
            return 1
        fi
        sleep 0.1
    done

    return 1
}

png_dimensions() {
    local image_path="$1"
    local metadata
    local metadata_line
    local image_format=""
    local pixel_width=""
    local pixel_height=""

    metadata="$(
        /usr/bin/sips \
            -g format \
            -g pixelWidth \
            -g pixelHeight \
            "$image_path" \
            2>>"$capture_log"
    )" || return 1

    for metadata_line in "${(@f)metadata}"; do
        case "$metadata_line" in
            *"format: "*)
                image_format="${metadata_line##*: }"
                ;;
            *"pixelWidth: "*)
                pixel_width="${metadata_line##*: }"
                ;;
            *"pixelHeight: "*)
                pixel_height="${metadata_line##*: }"
                ;;
        esac
    done

    if [[ "$image_format" != png \
        || "$pixel_width" != <-> \
        || "$pixel_height" != <-> ]] \
        || (( pixel_width <= 0 || pixel_height <= 0 )); then
        return 1
    fi

    print -r -- "${pixel_width}x${pixel_height}"
}

capture_preview() {
    local preview_id="$1"
    local language="$2"
    local preview_name="$preview_id-$language"
    local stdout_log="$log_directory/$preview_name.stdout.log"
    local stderr_log="$log_directory/$preview_name.stderr.log"
    local image_path="$output_directory/$preview_name.png"
    local window_id
    local focus_verdict
    local capture_status
    local image_dimensions

    log "Capturing $preview_id [$language]"
    "$preview_executable" \
        --preview-ui "$preview_id" \
        -AppleLanguages "($language)" \
        >"$stdout_log" \
        2>"$stderr_log" &
    active_preview_pid=$!

    if window_id="$(
        wait_for_ready_window "$active_preview_pid" "$stdout_log"
    )"; then
        :
    else
        fail "Preview did not report a ready window: $preview_name. Details: $stderr_log"
    fi

    if /usr/sbin/screencapture \
        -x \
        -o \
        -l "$window_id" \
        "$image_path" \
        >>"$capture_log" 2>&1; then
        :
    else
        capture_status=$?
        fail "Could not capture $preview_name (status $capture_status)."
    fi

    if ! kill -USR1 "$active_preview_pid" 2>/dev/null; then
        /bin/rm -f "$image_path"
        fail "Could not request focus verification: $preview_name. Details: $stderr_log"
    fi
    if focus_verdict="$(
        wait_for_capture_verdict "$active_preview_pid" "$stdout_log"
    )"; then
        :
    else
        /bin/rm -f "$image_path"
        fail "Preview did not verify capture focus: $preview_name. Details: $stderr_log"
    fi
    if [[ "$focus_verdict" != "CAPTURED $window_id" ]]; then
        /bin/rm -f "$image_path"
        fail "Preview lost focus while capturing: $preview_name"
    fi

    if [[ ! -s "$image_path" ]]; then
        fail "Screenshot is empty: $image_path"
    fi
    if image_dimensions="$(png_dimensions "$image_path")"; then
        :
    else
        fail "Screenshot is not a non-empty PNG with valid dimensions: $image_path"
    fi

    terminate_active_preview
    log "Captured $preview_name.png ($image_dimensions)"
}

if (( $# != 0 )); then
    usage >&2
    exit 64
fi

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$output_directory" "$log_directory"
cd "$project_root"

terminate_existing_previews

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

if preview_ids_text="$("$preview_executable" --list 2>>"$capture_log")"; then
    :
else
    list_status=$?
    fail "Could not list Preview IDs (status $list_status)."
fi

preview_ids=()
while IFS= read -r preview_id; do
    [[ -n "$preview_id" ]] || continue
    if [[ "$preview_id" == */* ]]; then
        fail "Preview ID cannot be used as a filename: $preview_id"
    fi
    preview_ids+=("$preview_id")
done <<<"$preview_ids_text"
readonly -a preview_ids

if (( ${#preview_ids[@]} == 0 )); then
    fail "The Preview registry is empty."
fi

log "Preview IDs: ${(j:, :)preview_ids}"
log "Languages: ${(j:, :)languages}"

for preview_id in "${preview_ids[@]}"; do
    for language in "${languages[@]}"; do
        capture_preview "$preview_id" "$language"
    done
done

print "Localized previews: $output_directory"
print "Capture logs: $log_directory"
