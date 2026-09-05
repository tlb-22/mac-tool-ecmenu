#!/bin/zsh

set -euo pipefail

readonly script_path="${0:A}"
readonly script_directory="${script_path:h}"
readonly project_root="${script_directory:h}"
readonly run_timestamp="$(date '+%Y%m%d-%H%M%S')"
readonly log_directory="$project_root/.artifacts/scratch/logs"
readonly activation_log="$log_directory/$run_timestamp-activate-environment-$$.log"
readonly launch_services_register="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
readonly finder_executable="/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"
readonly debug_extension_identifier="com.axiomace.ecmenu.debug.finderext"
readonly release_application_identifier="com.axiomace.ecmenu"
readonly release_extension_identifier="com.axiomace.ecmenu.finderext"

source "$script_directory/lib/product-paths.sh"
source "$script_directory/lib/user-focus.sh"
source "$script_directory/lib/code-signing.sh"
source "$script_directory/lib/process-lifecycle.sh"
source "$script_directory/lib/finder-environment.sh"

usage() {
    print "Usage: ./scripts/activate-environment.sh <debug|release>"
}

fail() {
    print -u2 -r -- "$1"
    print -u2 "Activation log: $activation_log"
    tail -n 100 "$activation_log" >&2 || true
    exit 1
}

resolve_installed_release() {
    local app_info_plist
    local candidate_app_path
    local -a release_candidates=()

    for app_info_plist in /Applications/*.app/Contents/Info.plist(N); do
        if [[ "$(ecmenu_plist_value "$app_info_plist" CFBundleIdentifier)" \
            == "$release_application_identifier" ]]; then
            candidate_app_path="${app_info_plist:h:h}"
            release_candidates+=("$candidate_app_path")
        fi
    done
    (( ${#release_candidates[@]} == 1 )) \
        || fail "Expected one installed Release application in /Applications; found ${#release_candidates[@]}."

    ecmenu_resolve_product_paths \
        /Applications \
        "${release_candidates[1]:t}" \
        >>"$activation_log" 2>&1 \
        || fail "Could not resolve the installed Release products."

    [[ "$ECMENU_PRODUCT_APPLICATION_BUNDLE_IDENTIFIER" \
        == "$release_application_identifier" ]] \
        || fail "The installed application is not the Release identity."
    [[ "$ECMENU_PRODUCT_EXTENSION_BUNDLE_IDENTIFIER" \
        == "$release_extension_identifier" ]] \
        || fail "The installed Finder Extension is not the Release identity."
}

reset_release_registration() {
    local parent_application_path
    local registered_extension_path
    local registered_paths_text

    registered_paths_text="$(
        ecmenu_extension_registration "$release_extension_identifier" \
            | sed -n 's/^[[:space:]]*Path = //p'
    )"
    ecmenu_register_product \
        "$ECMENU_PRODUCT_APP_PATH" "$ECMENU_PRODUCT_EXTENSION_PATH" \
        "$launch_services_register" >>"$activation_log" 2>&1 \
        || fail "Could not register the installed Release products."

    if [[ -n "$registered_paths_text" ]]; then
        for registered_extension_path in "${(@f)registered_paths_text}"; do
            [[ "$registered_extension_path" == "$ECMENU_PRODUCT_EXTENSION_PATH" ]] && continue
            pluginkit -r "$registered_extension_path" \
                >>"$activation_log" 2>&1 \
                || fail "Could not remove Release Finder Extension registration: $registered_extension_path"
            parent_application_path="${registered_extension_path%/Contents/PlugIns/*}"
            if [[ "$parent_application_path" != "$registered_extension_path" \
                && "$parent_application_path" != "$ECMENU_PRODUCT_APP_PATH" ]]; then
                "$launch_services_register" -u "$parent_application_path" \
                    >>"$activation_log" 2>&1 || true
            fi
        done
    fi

    pluginkit -e use -i "$release_extension_identifier" \
        >>"$activation_log" 2>&1 \
        || fail "Could not enable the Release Finder Extension."
}

verify_release_registration() {
    local registration
    local registered_paths_text
    local -a registered_paths=()

    registration="$(ecmenu_extension_registration "$release_extension_identifier")"
    registered_paths_text="$(
        print -r -- "$registration" | sed -n 's/^[[:space:]]*Path = //p'
    )"
    [[ -n "$registered_paths_text" ]] \
        && registered_paths=("${(@f)registered_paths_text}")
    (( ${#registered_paths[@]} == 1 )) \
        || fail "Expected one Release Finder Extension registration; found ${#registered_paths[@]}."
    [[ "$registered_paths[1]" == "$ECMENU_PRODUCT_EXTENSION_PATH" ]] \
        || fail "Release Finder Extension is registered from an unexpected path: $registered_paths[1]"
    print -r -- "$registration" | /usr/bin/grep -q '^[+!]' \
        || fail "Release Finder Extension is not enabled."

    registration="$(ecmenu_extension_registration "$debug_extension_identifier")"
    if print -r -- "$registration" | /usr/bin/grep -q '^[+!]'; then
        fail "Debug Finder Extension is still enabled."
    fi
}

if (( $# != 1 )); then
    usage >&2
    exit 64
fi
case "$1" in
    debug|release) ;;
    *)
        usage >&2
        exit 64
        ;;
esac

ecmenu_reexec_preserving_user_focus "$script_path" "$@"

mkdir -p "$log_directory"
: >"$activation_log"
cd "$project_root"

# 在改变启用状态前完成目标构建、定位和签名验证。
case "$1" in
    debug)
        "$script_directory/run-debug.sh" --build-only >>"$activation_log" 2>&1 \
            || fail "Could not prepare the Debug products."
        ;;
    release)
        resolve_installed_release
        ecmenu_verify_product_signatures >>"$activation_log" 2>&1 \
            || fail "The installed Release signing identity is invalid."
        ;;
esac

previous_debug_state="$(
    ecmenu_extension_state "$debug_extension_identifier" 2>>"$activation_log"
)" || fail "Could not read the current Debug Finder Extension state."
previous_release_state="$(
    ecmenu_extension_state "$release_extension_identifier" 2>>"$activation_log"
)" || fail "Could not read the current Release Finder Extension state."
readonly previous_debug_state previous_release_state
switch_pending=true

restore_on_exit() {
    local exit_status=$?
    local restore_status=0

    trap - EXIT
    trap '' HUP INT TERM
    if $switch_pending; then
        ecmenu_restore_extension_states \
            "$debug_extension_identifier" "$previous_debug_state" \
            "$release_extension_identifier" "$previous_release_state" \
            >>"$activation_log" 2>&1 || restore_status=1
        restart_gui_launch_service com.apple.Finder \
            >>"$activation_log" 2>&1 || restore_status=1
        if (( restore_status != 0 )); then
            print -u2 "Could not restore the original Finder Extension states. Log: $activation_log"
            (( exit_status != 0 )) || exit_status=1
        else
            print -u2 "Original Finder Extension states restored."
        fi
    fi
    exit "$exit_status"
}

trap restore_on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

case "$1" in
    debug)
        ecmenu_set_extension_state "$release_extension_identifier" disabled \
            >>"$activation_log" 2>&1 \
            || fail "Could not disable the Release Finder Extension."
        "$script_directory/run-debug.sh" --no-build --refresh-finder \
            >>"$activation_log" 2>&1 \
            || fail "Could not activate the prepared Debug products."
        ;;
    release)
        ecmenu_set_extension_state "$debug_extension_identifier" disabled \
            >>"$activation_log" 2>&1 \
            || fail "Could not disable the Debug Finder Extension."
        reset_release_registration

        previous_finder_pids="$(process_ids_for_executable "$finder_executable")"
        previous_extension_pids="$(
            process_ids_for_executable "$ECMENU_PRODUCT_EXTENSION_EXECUTABLE_PATH"
        )"
        terminate_process_ids "$previous_extension_pids"
        restart_gui_launch_service com.apple.Finder >>"$activation_log" 2>&1 \
            || fail "Could not restart Finder."
        wait_for_process_ids_to_exit "$previous_finder_pids" 150 \
            || fail "Previous Finder process did not exit."
        wait_for_process_ids_to_exit "$previous_extension_pids" 150 \
            || fail "Previous Release Finder Extension did not exit."

        open "$ECMENU_PRODUCT_APP_PATH" >>"$activation_log" 2>&1 \
            || fail "Could not open the installed Release application."
        open "$project_root" >>"$activation_log" 2>&1 \
            || fail "Could not reopen Finder."
        wait_for_process "$finder_executable" 150 \
            || fail "Finder did not restart."
        wait_for_process "$ECMENU_PRODUCT_MAIN_EXECUTABLE_PATH" 150 \
            || fail "Release application did not start."
        wait_for_process "$ECMENU_PRODUCT_EXTENSION_EXECUTABLE_PATH" 150 \
            || fail "Release Finder Extension did not load."
        verify_release_registration
        print "Release environment active: $ECMENU_PRODUCT_APP_PATH"
        ;;
esac

switch_pending=false
print "Finder environment activated: $1"
print "Activation log: $activation_log"
