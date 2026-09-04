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

usage() {
    print "Usage: ./scripts/activate-environment.sh <debug|release>"
}

fail() {
    print -u2 -r -- "$1"
    print -u2 "Activation log: $activation_log"
    tail -n 100 "$activation_log" >&2 || true
    exit 1
}

code_signing_value() {
    local bundle_path="$1"
    local key="$2"

    codesign -dv "$bundle_path" 2>&1 \
        | sed -n "s/^$key=//p" \
        || true
}

extension_registration() {
    local bundle_identifier="$1"

    pluginkit -m -A -D -vv -i "$bundle_identifier" 2>>"$activation_log" \
        || true
}

disable_extension_if_registered() {
    local bundle_identifier="$1"
    local registration

    registration="$(extension_registration "$bundle_identifier")"
    if ! print -r -- "$registration" | rg -q '^[[:space:]]*Path = '; then
        return 0
    fi
    if print -r -- "$registration" | rg -q '^[+!]'; then
        pluginkit -e ignore -i "$bundle_identifier" \
            >>"$activation_log" 2>&1 \
            || fail "Could not disable Finder Extension: $bundle_identifier"
    fi
    registration="$(extension_registration "$bundle_identifier")"
    if print -r -- "$registration" | rg -q '^[+!]'; then
        fail "Finder Extension is still enabled: $bundle_identifier"
    fi
}

process_ids_for_executable() {
    local executable_path="$1"
    local command_path
    local pid

    while read -r pid command_path; do
        if [[ "$command_path" == "$executable_path" ]]; then
            print "$pid"
        fi
    done < <(ps -axo pid=,comm= 2>/dev/null)
}

wait_for_process() {
    local executable_path="$1"
    local maximum_attempts="${2:-150}"
    local attempt

    for (( attempt = 1; attempt <= maximum_attempts; attempt++ )); do
        if [[ -n "$(process_ids_for_executable "$executable_path")" ]]; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

wait_for_process_ids_to_exit() {
    local process_ids="$1"
    local maximum_attempts="${2:-100}"
    local all_exited
    local attempt
    local pid

    [[ -n "$process_ids" ]] || return 0
    for (( attempt = 1; attempt <= maximum_attempts; attempt++ )); do
        all_exited=true
        for pid in "${(@f)process_ids}"; do
            if kill -0 "$pid" 2>/dev/null; then
                all_exited=false
                break
            fi
        done
        $all_exited && return 0
        sleep 0.1
    done
    return 1
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
        extension_registration "$release_extension_identifier" \
            | sed -n 's/^[[:space:]]*Path = //p'
    )"
    if [[ -n "$registered_paths_text" ]]; then
        for registered_extension_path in "${(@f)registered_paths_text}"; do
            pluginkit -r "$registered_extension_path" \
                >>"$activation_log" 2>&1 \
                || fail "Could not remove Release Finder Extension registration: $registered_extension_path"
            parent_application_path="${registered_extension_path%/Contents/PlugIns/*}"
            if [[ "$parent_application_path" != "$registered_extension_path" ]]; then
                "$launch_services_register" -u "$parent_application_path" \
                    >>"$activation_log" 2>&1 || true
            fi
        done
    fi

    "$launch_services_register" -f "$ECMENU_PRODUCT_APP_PATH" \
        >>"$activation_log" 2>&1 \
        || fail "Could not register the installed Release application."
    pluginkit -a "$ECMENU_PRODUCT_EXTENSION_PATH" \
        >>"$activation_log" 2>&1 \
        || fail "Could not register the installed Release Finder Extension."
    pluginkit -e use -i "$release_extension_identifier" \
        >>"$activation_log" 2>&1 \
        || fail "Could not enable the Release Finder Extension."
}

verify_release_registration() {
    local registration
    local registered_paths_text
    local -a registered_paths=()

    registration="$(extension_registration "$release_extension_identifier")"
    registered_paths_text="$(
        print -r -- "$registration" | sed -n 's/^[[:space:]]*Path = //p'
    )"
    [[ -n "$registered_paths_text" ]] \
        && registered_paths=("${(@f)registered_paths_text}")
    (( ${#registered_paths[@]} == 1 )) \
        || fail "Expected one Release Finder Extension registration; found ${#registered_paths[@]}."
    [[ "$registered_paths[1]" == "$ECMENU_PRODUCT_EXTENSION_PATH" ]] \
        || fail "Release Finder Extension is registered from an unexpected path: $registered_paths[1]"
    print -r -- "$registration" | rg -q '^[+!]' \
        || fail "Release Finder Extension is not enabled."

    registration="$(extension_registration "$debug_extension_identifier")"
    if print -r -- "$registration" | rg -q '^[+!]'; then
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

case "$1" in
    debug)
        disable_extension_if_registered "$release_extension_identifier"
        exec "$script_directory/run-debug.sh" --refresh-finder
        ;;
    release)
        resolve_installed_release

        readonly release_application_signing_identifier="$(
            code_signing_value "$ECMENU_PRODUCT_APP_PATH" Identifier
        )"
        readonly release_extension_signing_identifier="$(
            code_signing_value "$ECMENU_PRODUCT_EXTENSION_PATH" Identifier
        )"
        readonly release_application_team="$(
            code_signing_value "$ECMENU_PRODUCT_APP_PATH" TeamIdentifier
        )"
        readonly release_extension_team="$(
            code_signing_value "$ECMENU_PRODUCT_EXTENSION_PATH" TeamIdentifier
        )"
        [[ "$release_application_signing_identifier" \
            == "$release_application_identifier" \
            && "$release_extension_signing_identifier" \
                == "$release_extension_identifier" \
            && -n "$release_application_team" \
            && "$release_extension_team" == "$release_application_team" ]] \
            || fail "The installed Release signing identity is invalid."

        disable_extension_if_registered "$debug_extension_identifier"
        reset_release_registration

        previous_finder_pids="$(process_ids_for_executable "$finder_executable")"
        for finder_pid in "${(@f)previous_finder_pids}"; do
            kill "$finder_pid" 2>/dev/null || true
        done
        wait_for_process_ids_to_exit "$previous_finder_pids" \
            || fail "Previous Finder process did not exit."

        open "$ECMENU_PRODUCT_APP_PATH" >>"$activation_log" 2>&1 \
            || fail "Could not open the installed Release application."
        open "$project_root" >>"$activation_log" 2>&1 \
            || fail "Could not reopen Finder."
        wait_for_process "$finder_executable" \
            || fail "Finder did not restart."
        wait_for_process "$ECMENU_PRODUCT_MAIN_EXECUTABLE_PATH" \
            || fail "Release application did not start."
        wait_for_process "$ECMENU_PRODUCT_EXTENSION_EXECUTABLE_PATH" \
            || fail "Release Finder Extension did not load."
        verify_release_registration

        print "Release environment active: $ECMENU_PRODUCT_APP_PATH"
        print "Activation log: $activation_log"
        ;;
esac
