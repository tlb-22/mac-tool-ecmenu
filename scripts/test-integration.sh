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
readonly visibility_fixture="$resident_fixture/visible-item"
readonly sender_path="$derived_data_path/Build/Products/Debug/ContextCommandSender"
readonly developer_directory="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
readonly destination="${XCODE_DESTINATION:-platform=macOS,arch=arm64}"

source "$script_directory/lib/product-paths.sh"
source "$script_directory/lib/code-signing.sh"
source "$script_directory/lib/process-lifecycle.sh"
source "$script_directory/lib/finder-windows.sh"
source "$script_directory/lib/user-focus.sh"

fail() {
    print -u2 "$1"
    print -u2 "Integration log: $integration_log"
    tail -n 200 "$integration_log" >&2
    exit 1
}

assert_hidden_file() {
    python3 - "$1" <<'PY'
import os
import stat
import sys
import time

path = sys.argv[1]
deadline = time.monotonic() + 5
while True:
    information = os.stat(path, follow_symlinks=False)
    if not stat.S_ISREG(information.st_mode):
        raise SystemExit("The visibility fixture is no longer a regular file")
    if information.st_flags & stat.UF_HIDDEN:
        break
    if time.monotonic() >= deadline:
        raise SystemExit("The visibility fixture did not acquire UF_HIDDEN")
    time.sleep(0.05)
PY
}

ecmenu_reexec_checking_finder_windows "$script_path" "$@"
ecmenu_reexec_preserving_user_focus "$script_path" "$@"

mkdir -p "$log_directory" "$resident_fixture"
: >"$integration_log"
cd "$project_root"

if ! "$script_directory/run-debug.sh" --build-only >>"$integration_log" 2>&1; then
    fail "Could not build and validate the Debug products."
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
readonly debug_app_path="$ECMENU_PRODUCT_APP_PATH"
readonly debug_main_executable="$ECMENU_PRODUCT_MAIN_EXECUTABLE_PATH"

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

previous_main_pids="$(process_ids_for_executable "$debug_main_executable")"
terminate_process_ids "$previous_main_pids"
if ! wait_for_process_ids_to_exit "$previous_main_pids"; then
    fail "The previous Debug application did not exit."
fi
if ! open -n "$debug_app_path" >>"$integration_log" 2>&1; then
    fail "Could not open the current Debug application."
fi
if ! wait_for_process "$debug_main_executable" 100; then
    fail "The current Debug application did not start."
fi

if ! "$sender_path" --wait-for-menu-configuration >>"$integration_log" 2>&1; then
    fail "The new Debug host did not provide an authenticated menu configuration."
fi

print -r -- "IPC visibility fixture" >"$visibility_fixture"
if ! "$sender_path" --hide-items "$visibility_fixture" >>"$integration_log" 2>&1; then
    fail "The authenticated one-way hide-items command send failed."
fi
if ! assert_hidden_file "$visibility_fixture" >>"$integration_log" 2>&1; then
    fail "The one-way command did not set the fixture's UF_HIDDEN flag."
fi

print "Authenticated IPC integration scenarios passed: 2"
print "Fixtures: $fixture_root"
print "Integration log: $integration_log"
