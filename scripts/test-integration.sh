#!/bin/zsh

set -euo pipefail

readonly script_path="${0:A}"
readonly script_directory="${script_path:h}"
readonly project_root="${script_directory:h}"
readonly derived_data_path="$project_root/.derivedData"
readonly debug_products_directory="$derived_data_path/Build/Products/Debug"
readonly run_timestamp="$(date '+%Y%m%d-%H%M%S')"
readonly log_directory="$project_root/.artifacts/scratch/logs"
readonly integration_log="$log_directory/$run_timestamp-ipc-integration-$$.log"
readonly fixture_root="$project_root/.artifacts/scratch/tests/$run_timestamp-ipc-integration-$$"
readonly resident_fixture="$fixture_root/resident-host"
readonly sender_path="$derived_data_path/Build/Products/Debug/ContextCommandSender"
readonly developer_directory="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
readonly destination="${XCODE_DESTINATION:-platform=macOS,arch=arm64}"

source "$script_directory/lib/product-paths.sh"
source "$script_directory/lib/code-signing.sh"
source "$script_directory/lib/user-focus.sh"

fail() {
    print -u2 "$1"
    print -u2 "Integration log: $integration_log"
    tail -n 200 "$integration_log" >&2
    exit 1
}

assert_single_text_file() {
    local directory_path="$1"
    local attempt
    local -a files

    for attempt in {1..100}; do
        files=("$directory_path"/untitled*.txt(N))
        if (( ${#files[@]} == 1 )); then
            sleep 0.5
            files=("$directory_path"/untitled*.txt(N))
            (( ${#files[@]} == 1 )) || return 1
            return 0
        fi
        (( ${#files[@]} < 2 )) || return 1
        sleep 0.05
    done
    return 1
}

ecmenu_reexec_preserving_user_focus "$script_path" "$@"

mkdir -p "$log_directory" "$resident_fixture"
: >"$integration_log"
cd "$project_root"

if ! "$script_directory/run-debug.sh" --refresh-finder >>"$integration_log" 2>&1; then
    fail "Could not build and run the Debug application."
fi

if ! DEVELOPER_DIR="$developer_directory" xcodebuild \
    -project ECMenu.xcodeproj \
    -scheme ContextCommandSender \
    -configuration Debug \
    -destination "$destination" \
    -derivedDataPath "$derived_data_path" \
    build -quiet >>"$integration_log" 2>&1; then
    fail "Could not build ContextCommandSender."
fi

if ! debug_build_settings="$(
    DEVELOPER_DIR="$developer_directory" xcodebuild \
        -project ECMenu.xcodeproj \
        -scheme ECMenu \
        -configuration Debug \
        -destination "$destination" \
        -derivedDataPath "$derived_data_path" \
        -showBuildSettings 2>>"$integration_log"
)"; then
    fail "Could not read the Debug application build settings."
fi
readonly expected_app_wrapper_name="$(
    print -r -- "$debug_build_settings" \
        | ecmenu_target_build_setting_value \
            ECMenu \
            FULL_PRODUCT_NAME
)"
if [[ -z "$expected_app_wrapper_name" ]]; then
    fail "The Debug application FULL_PRODUCT_NAME is missing."
fi

if ! ecmenu_resolve_product_paths \
    "$debug_products_directory" \
    "$expected_app_wrapper_name" \
    >>"$integration_log" 2>&1; then
    fail "Could not uniquely resolve the built Debug products."
fi

readonly debug_extension_path="$ECMENU_PRODUCT_EXTENSION_PATH"

extension_bundle_id="$(
    ecmenu_plist_value \
        "$debug_extension_path/Contents/Info.plist" \
        CFBundleIdentifier
)"
extension_signing_identifier="$(
    ecmenu_code_signing_value "$debug_extension_path" Identifier
)"
extension_team="$(
    ecmenu_code_signing_value "$debug_extension_path" TeamIdentifier
)"
sender_signing_identifier="$(ecmenu_code_signing_value "$sender_path" Identifier)"
sender_team="$(ecmenu_code_signing_value "$sender_path" TeamIdentifier)"

if [[ -z "$extension_bundle_id" \
    || -z "$extension_signing_identifier" \
    || -z "$extension_team" ]]; then
    fail "Could not read the built Debug Finder Extension signing identity."
fi
if [[ "$extension_signing_identifier" != "$extension_bundle_id" ]]; then
    fail "The Debug Finder Extension signing identifier does not match its Info.plist."
fi
if [[ "$sender_signing_identifier" != "$extension_signing_identifier" ]]; then
    fail "ContextCommandSender does not have the Debug Finder Extension signing identifier."
fi
if [[ "$sender_team" != "$extension_team" ]]; then
    fail "ContextCommandSender does not have the Debug Finder Extension signing Team."
fi

if ! "$sender_path" "$resident_fixture" >>"$integration_log" 2>&1; then
    fail "The authenticated one-way command send failed."
fi
if ! assert_single_text_file "$resident_fixture"; then
    fail "The one-way command did not create exactly one TXT file."
fi

if ! "$sender_path" --menu-configuration >>"$integration_log" 2>&1; then
    fail "The authenticated client could not fetch the menu configuration."
fi

print "Authenticated IPC integration scenarios passed: 2"
print "Fixtures: $fixture_root"
print "Integration log: $integration_log"
