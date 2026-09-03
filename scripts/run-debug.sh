#!/bin/zsh

set -euo pipefail

readonly script_directory="${0:A:h}"
readonly project_root="${script_directory:h}"
readonly derived_data_path="$project_root/.derivedData"
readonly debug_products_directory="$derived_data_path/Build/Products/Debug"
readonly run_timestamp="$(date '+%Y%m%d-%H%M%S')"
readonly finder_executable="/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"
readonly log_directory="$project_root/.artifacts/scratch/logs"
readonly build_log="$log_directory/$run_timestamp-run-debug-$$.log"
readonly developer_directory="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
readonly destination="${XCODE_DESTINATION:-platform=macOS,arch=arm64}"
readonly launch_services_register="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

source "$script_directory/lib/product-paths.sh"

refresh_finder=false
refresh_icon=false

usage() {
    print "Usage: ./scripts/run-debug.sh [--refresh-finder] [--refresh-icon]"
}

if (( $# > 2 )); then
    usage >&2
    exit 64
fi

for option in "$@"; do
    case "$option" in
        --refresh-finder)
            if $refresh_finder; then
                usage >&2
                exit 64
            fi
            refresh_finder=true
            ;;
        --refresh-icon)
            if $refresh_icon; then
                usage >&2
                exit 64
            fi
            refresh_icon=true
            ;;
        *)
            usage >&2
            exit 64
            ;;
    esac
done

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

terminate_process_ids() {
    local process_ids="$1"
    local pid

    if [[ -z "$process_ids" ]]; then
        return 0
    fi

    for pid in "${(@f)process_ids}"; do
        kill "$pid" 2>/dev/null || true
    done
}

wait_for_process() {
    local executable_path="$1"
    local maximum_attempts="${2:-30}"
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
    local maximum_attempts="${2:-50}"
    local all_exited
    local attempt
    local pid

    if [[ -z "$process_ids" ]]; then
        return 0
    fi

    for (( attempt = 1; attempt <= maximum_attempts; attempt++ )); do
        all_exited=true
        for pid in "${(@f)process_ids}"; do
            if kill -0 "$pid" 2>/dev/null; then
                all_exited=false
                break
            fi
        done
        if $all_exited; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

code_signing_value() {
    local bundle_path="$1"
    local key="$2"

    codesign -dv "$bundle_path" 2>&1 \
        | sed -n "s/^$key=//p" \
        || true
}

all_finder_extension_registration_paths() {
    pluginkit -m -A -D -vv -p com.apple.FinderSync \
        | sed -n 's/^[[:space:]]*Path = //p'
}

reject_enabled_other_product_extensions() {
    local candidate_app_path
    local candidate_app_bundle_id
    local candidate_app_configured_app_id
    local candidate_app_configured_extension_id
    local candidate_app_group_id
    local candidate_app_signing_identifier
    local candidate_app_team_identifier
    local candidate_extension_bundle_id
    local candidate_extension_configured_app_id
    local candidate_extension_configured_extension_id
    local candidate_extension_group_id
    local candidate_extension_path
    local candidate_extension_signing_identifier
    local candidate_extension_team_identifier
    local candidate_registration
    local release_app_group_id="${configured_app_group_id%.debug}"
    local release_main_bundle_id="${main_bundle_id%.debug}"
    local release_extension_bundle_id="${main_bundle_id%.debug}.finderext"
    local registered_paths_text
    local -A reported_bundle_ids=()
    local -a enabled_others=()

    registered_paths_text="$(all_finder_extension_registration_paths)"
    if [[ -z "$registered_paths_text" ]]; then
        return 0
    fi

    for candidate_extension_path in "${(@f)registered_paths_text}"; do
        if [[ "$candidate_extension_path" == "$extension_path" ]]; then
            continue
        fi

        candidate_app_path="${candidate_extension_path%/Contents/PlugIns/*}"
        if [[ "$candidate_app_path" == "$candidate_extension_path" ]]; then
            continue
        fi

        candidate_app_bundle_id="$(
            ecmenu_plist_value \
                "$candidate_app_path/Contents/Info.plist" \
                CFBundleIdentifier
        )"
        candidate_extension_bundle_id="$(
            ecmenu_plist_value \
                "$candidate_extension_path/Contents/Info.plist" \
                CFBundleIdentifier
        )"
        if [[ "$candidate_app_bundle_id" != "$release_main_bundle_id" \
            || "$candidate_extension_bundle_id" \
                != "$release_extension_bundle_id" ]]; then
            continue
        fi

        candidate_app_configured_app_id="$(
            ecmenu_plist_value \
                "$candidate_app_path/Contents/Info.plist" \
                ECMApplicationSigningIdentifier
        )"
        candidate_app_configured_extension_id="$(
            ecmenu_plist_value \
                "$candidate_app_path/Contents/Info.plist" \
                ECMFinderExtensionSigningIdentifier
        )"
        candidate_app_group_id="$(
            ecmenu_plist_value \
                "$candidate_app_path/Contents/Info.plist" \
                ECMApplicationGroupIdentifier
        )"
        candidate_extension_configured_app_id="$(
            ecmenu_plist_value \
                "$candidate_extension_path/Contents/Info.plist" \
                ECMApplicationSigningIdentifier
        )"
        candidate_extension_configured_extension_id="$(
            ecmenu_plist_value \
                "$candidate_extension_path/Contents/Info.plist" \
                ECMFinderExtensionSigningIdentifier
        )"
        candidate_extension_group_id="$(
            ecmenu_plist_value \
                "$candidate_extension_path/Contents/Info.plist" \
                ECMApplicationGroupIdentifier
        )"
        if [[ "$candidate_app_configured_app_id" \
                != "$release_main_bundle_id" \
            || "$candidate_app_configured_extension_id" \
                != "$release_extension_bundle_id" \
            || "$candidate_extension_configured_app_id" \
                != "$release_main_bundle_id" \
            || "$candidate_extension_configured_extension_id" \
                != "$release_extension_bundle_id" \
            || "$candidate_app_group_id" != "$release_app_group_id" \
            || "$candidate_extension_group_id" != "$release_app_group_id" ]]; then
            continue
        fi

        candidate_app_signing_identifier="$(
            code_signing_value "$candidate_app_path" Identifier
        )"
        candidate_extension_signing_identifier="$(
            code_signing_value "$candidate_extension_path" Identifier
        )"
        candidate_app_team_identifier="$(
            code_signing_value "$candidate_app_path" TeamIdentifier
        )"
        candidate_extension_team_identifier="$(
            code_signing_value "$candidate_extension_path" TeamIdentifier
        )"
        if [[ "$candidate_app_signing_identifier" != "$release_main_bundle_id" \
            || "$candidate_extension_signing_identifier" \
                != "$release_extension_bundle_id" \
            || "$candidate_app_team_identifier" != "$extension_team_identifier" \
            || "$candidate_extension_team_identifier" \
                != "$extension_team_identifier" ]]; then
            continue
        fi

        if (( ${+reported_bundle_ids[$candidate_extension_bundle_id]} )); then
            continue
        fi

        candidate_registration="$(
            pluginkit -m -A -D -vv \
                -i "$candidate_extension_bundle_id" || true
        )"
        if print -r -- "$candidate_registration" | rg -q '^[+!]'; then
            reported_bundle_ids[$candidate_extension_bundle_id]=1
            enabled_others+=(
                "$candidate_extension_bundle_id ($candidate_extension_path)"
            )
        fi
    done

    if (( ${#enabled_others[@]} == 0 )); then
        return 0
    fi

    print -u2 \
        "Another ECMenu Finder Extension identity is enabled:"
    local enabled_extension
    for enabled_extension in "${enabled_others[@]}"; do
        print -u2 "  $enabled_extension"
    done
    print -u2 \
        "Disable it in System Settings before running the Debug Extension."
    print -u2 "No non-Debug registration was changed."
    return 13
}

extension_registration() {
    pluginkit -m -A -D -vv -i "$extension_bundle_id"
}

extension_registration_paths() {
    extension_registration | sed -n 's/^[[:space:]]*Path = //p'
}

reset_extension_registration() {
    local candidate_bundle_id
    local candidate_extension_path
    local registered_app_path
    local registered_path
    local registered_paths_text
    local -A app_paths_to_remove=()
    local -A extension_paths_to_remove=()
    local -A queried_app_paths=()
    local -A queried_extension_paths=()

    registered_paths_text="$(extension_registration_paths)"
    if [[ -n "$registered_paths_text" ]]; then
        for registered_path in "${(@f)registered_paths_text}"; do
            extension_paths_to_remove[$registered_path]=1
            queried_extension_paths[$registered_path]=1
            registered_app_path="${registered_path%/Contents/PlugIns/*}"
            if [[ "$registered_app_path" != "$registered_path" ]]; then
                app_paths_to_remove[$registered_app_path]=1
                queried_app_paths[$registered_app_path]=1
            fi
        done
    fi

    while IFS= read -r -d '' candidate_extension_path; do
        candidate_bundle_id="$(
            ecmenu_plist_value \
                "$candidate_extension_path/Contents/Info.plist" \
                CFBundleIdentifier
        )"
        if [[ "$candidate_bundle_id" != "$extension_bundle_id" ]]; then
            continue
        fi

        registered_app_path="${candidate_extension_path%/Contents/PlugIns/*}"
        if [[ "$registered_app_path" != "$candidate_extension_path" ]]; then
            app_paths_to_remove[$registered_app_path]=1
            extension_paths_to_remove[$candidate_extension_path]=1
        fi
    done < <(
        find "$derived_data_path" \
            -type d \
            -name '*.appex' \
            -prune \
            -print0
    )

    for registered_path in "${(@k)extension_paths_to_remove}"; do
        if ! pluginkit -r "$registered_path" >/dev/null 2>&1; then
            if (( ${+queried_extension_paths[$registered_path]} )); then
                print -u2 \
                    "Failed to remove registered Finder Extension: $registered_path"
            fi
        fi
    done

    for registered_app_path in "${(@k)app_paths_to_remove}"; do
        if ! "$launch_services_register" -u "$registered_app_path" \
            >/dev/null 2>&1; then
            if (( ${+queried_app_paths[$registered_app_path]} )); then
                print -u2 \
                    "Failed to remove registered parent app: $registered_app_path"
            fi
        fi
    done

    "$launch_services_register" -f "$app_path"
    pluginkit -a "$extension_path"
    pluginkit -e use -i "$extension_bundle_id"
    print "Finder Extension registration reset to current Debug app."
}

verify_extension_registration() {
    local registration
    local registered_path
    local registered_paths_text
    local -a registered_paths=()

    registration="$(extension_registration)"
    registered_paths_text="$(
        print -r -- "$registration" | sed -n 's/^[[:space:]]*Path = //p'
    )"
    if [[ -n "$registered_paths_text" ]]; then
        registered_paths=("${(@f)registered_paths_text}")
    fi

    if (( ${#registered_paths[@]} != 1 )); then
        print -u2 \
            "Expected one Finder Extension registration, found ${#registered_paths[@]}."
        for registered_path in "${registered_paths[@]}"; do
            print -u2 "Path = $registered_path"
        done
        if ! $refresh_finder && ! $refresh_icon; then
            print -u2 "Run ./scripts/run-debug.sh --refresh-finder to repair registration."
        fi
        return 3
    fi

    if [[ "$registered_paths[1]" != "$extension_path" ]]; then
        print -u2 \
            "Finder Extension is not registered from the Debug app: $extension_path"
        print -u2 "Registered path: $registered_paths[1]"
        if ! $refresh_finder && ! $refresh_icon; then
            print -u2 "Run ./scripts/run-debug.sh --refresh-finder to repair registration."
        fi
        return 4
    fi

    if ! print -r -- "$registration" | rg -q '^[+!]'; then
        print -u2 "Finder Extension is registered but not enabled."
        return 8
    fi

    return 0
}

open_finder_directory() {
    local directory_path="$1"
    local attempt

    for attempt in {1..30}; do
        if open "$directory_path" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.2
    done
    return 1
}

mkdir -p "$log_directory"
cd "$project_root"

if DEVELOPER_DIR="$developer_directory" xcodebuild \
    -project ECMenu.xcodeproj \
    -scheme ECMenu \
    -configuration Debug \
    -destination "$destination" \
    -derivedDataPath "$derived_data_path" \
    build -quiet >"$build_log" 2>&1; then
    :
else
    build_status=$?
    print -u2 "Debug build failed. Log: $build_log"
    tail -n 200 "$build_log" >&2
    exit "$build_status"
fi

if debug_build_settings="$(
    DEVELOPER_DIR="$developer_directory" xcodebuild \
        -project ECMenu.xcodeproj \
        -scheme ECMenu \
        -configuration Debug \
        -destination "$destination" \
        -derivedDataPath "$derived_data_path" \
        -showBuildSettings 2>>"$build_log"
)"; then
    :
else
    print -u2 "Could not read the Debug application build settings."
    exit 20
fi
readonly expected_app_wrapper_name="$(
    print -r -- "$debug_build_settings" \
        | ecmenu_target_build_setting_value \
            ECMenu \
            FULL_PRODUCT_NAME
)"
if [[ -z "$expected_app_wrapper_name" ]]; then
    print -u2 "The Debug application FULL_PRODUCT_NAME is missing."
    exit 20
fi

if ! ecmenu_resolve_product_paths \
    "$debug_products_directory" \
    "$expected_app_wrapper_name"; then
    print -u2 "Could not uniquely resolve the built Debug products."
    exit 20
fi

readonly app_path="$ECMENU_PRODUCT_APP_PATH"
readonly extension_path="$ECMENU_PRODUCT_EXTENSION_PATH"
readonly main_executable="$ECMENU_PRODUCT_MAIN_EXECUTABLE_PATH"
readonly extension_executable="$ECMENU_PRODUCT_EXTENSION_EXECUTABLE_PATH"

readonly main_bundle_id="$(
    ecmenu_plist_value "$app_path/Contents/Info.plist" CFBundleIdentifier
)"
readonly extension_bundle_id="$(
    ecmenu_plist_value \
        "$extension_path/Contents/Info.plist" \
        CFBundleIdentifier
)"
readonly main_signing_identifier="$(
    code_signing_value "$app_path" Identifier
)"
readonly extension_signing_identifier="$(
    code_signing_value "$extension_path" Identifier
)"
readonly extension_team_identifier="$(
    code_signing_value "$extension_path" TeamIdentifier
)"
readonly main_team_identifier="$(
    code_signing_value "$app_path" TeamIdentifier
)"
readonly configured_main_bundle_id="$(
    ecmenu_plist_value \
        "$app_path/Contents/Info.plist" \
        ECMApplicationSigningIdentifier
)"
readonly configured_extension_bundle_id="$(
    ecmenu_plist_value \
        "$app_path/Contents/Info.plist" \
        ECMFinderExtensionSigningIdentifier
)"
readonly configured_app_group_id="$(
    ecmenu_plist_value \
        "$app_path/Contents/Info.plist" \
        ECMApplicationGroupIdentifier
)"

if [[ -z "$main_bundle_id" \
    || -z "$extension_bundle_id" \
    || -z "$main_team_identifier" \
    || -z "$extension_team_identifier" ]]; then
    print -u2 "Could not read the built Debug signing identity."
    exit 14
fi
if [[ "$main_bundle_id" != *.debug \
    || "$extension_bundle_id" != "$main_bundle_id.finderext" \
    || "$configured_app_group_id" != *.debug ]]; then
    print -u2 \
        "Refusing to manage a build that is not the isolated Debug identity tree."
    exit 17
fi
if [[ "$configured_main_bundle_id" != "$main_bundle_id" \
    || "$configured_extension_bundle_id" != "$extension_bundle_id" ]]; then
    print -u2 "Debug Info.plist signing identities do not match the products."
    exit 18
fi
if [[ "$main_signing_identifier" != "$main_bundle_id" ]]; then
    print -u2 \
        "Debug app signing identifier does not match its Info.plist: $main_signing_identifier"
    exit 15
fi
if [[ "$extension_signing_identifier" != "$extension_bundle_id" ]]; then
    print -u2 \
        "Debug Extension signing identifier does not match its Info.plist: $extension_signing_identifier"
    exit 16
fi
if [[ "$main_team_identifier" != "$extension_team_identifier" ]]; then
    print -u2 "Debug app and Extension are signed by different Teams."
    exit 19
fi

reject_enabled_other_product_extensions

previous_main_pids="$(process_ids_for_executable "$main_executable")"
terminate_process_ids "$previous_main_pids"
if ! wait_for_process_ids_to_exit "$previous_main_pids"; then
    print -u2 "Previous Debug main app did not exit: $main_executable"
    exit 9
fi

if $refresh_icon; then
    user_cache_directory="$(getconf DARWIN_USER_CACHE_DIR)"
    normalized_user_cache_directory="${user_cache_directory:A}"
    case "$normalized_user_cache_directory" in
        /private/var/folders/*/C | /var/folders/*/C) ;;
        *)
            print -u2 "Unexpected user cache directory: $user_cache_directory"
            exit 7
            ;;
    esac

    icon_services_cache="$normalized_user_cache_directory/com.apple.iconservices"
    dock_icon_cache="$normalized_user_cache_directory/com.apple.dock.iconcache"

    "$launch_services_register" -u "$app_path" || true
    killall iconservicesagent 2>/dev/null || true
    killall Dock 2>/dev/null || true
    if [[ -e "$icon_services_cache" || -L "$icon_services_cache" ]]; then
        rm -rf -- "$icon_services_cache"
    fi
    if [[ -e "$dock_icon_cache" || -L "$dock_icon_cache" ]]; then
        rm -rf -- "$dock_icon_cache"
    fi
fi

if $refresh_finder || $refresh_icon; then
    reset_extension_registration
    verify_extension_registration
fi

if $refresh_finder; then
    previous_extension_pids="$(
        process_ids_for_executable "$extension_executable"
    )"
    previous_finder_pids="$(process_ids_for_executable "$finder_executable")"
    terminate_process_ids "$previous_extension_pids"
    terminate_process_ids "$previous_finder_pids"

    if ! wait_for_process_ids_to_exit "$previous_extension_pids" 100; then
        print -u2 \
            "Previous Debug Finder Extension did not exit: $extension_executable"
        exit 10
    fi
    if ! wait_for_process_ids_to_exit "$previous_finder_pids" 100; then
        print -u2 "Previous Finder did not exit."
        exit 11
    fi
fi

open -n "$app_path"

if $refresh_finder || $refresh_icon; then
    if ! open_finder_directory "$project_root"; then
        print -u2 "Finder did not become ready to open: $project_root"
        exit 6
    fi
fi

if $refresh_finder && ! wait_for_process "$finder_executable" 150; then
    print -u2 "Finder did not restart: $finder_executable"
    exit 12
fi

if ! wait_for_process "$main_executable" 100; then
    print -u2 "Main app did not start: $main_executable"
    exit 1
fi

if ! $refresh_finder && ! $refresh_icon; then
    verify_extension_registration
fi

if ! wait_for_process "$extension_executable" 150; then
    if $refresh_finder; then
        print -u2 "Finder Extension did not load after a complete Finder refresh."
    else
        print -u2 "Finder Extension is not running. Run with --refresh-finder."
    fi
    exit 2
fi

verify_extension_registration

main_pids_text="$(process_ids_for_executable "$main_executable")"
extension_pids_text="$(process_ids_for_executable "$extension_executable")"
main_pids=()
extension_pids=()
if [[ -n "$main_pids_text" ]]; then
    main_pids=("${(@f)main_pids_text}")
fi
if [[ -n "$extension_pids_text" ]]; then
    extension_pids=("${(@f)extension_pids_text}")
fi
if (( ${#main_pids[@]} != 1 || ${#extension_pids[@]} != 1 )); then
    print -u2 \
        "Expected one main app and one Finder Extension process; found ${#main_pids[@]} and ${#extension_pids[@]}."
    exit 5
fi

print "Debug app running: $main_pids[1]"
print "Finder Extension running: $extension_pids[1]"
if $refresh_icon; then
    print "Dock app icon refreshed."
fi
print "Build log: $build_log"
