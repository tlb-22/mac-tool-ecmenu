#!/bin/zsh

set -euo pipefail

readonly script_path="${0:A}"
readonly script_directory="${script_path:h}"
readonly project_root="${script_directory:h}"
readonly derived_data_path="$project_root/.derivedData"
readonly run_timestamp="$(date '+%Y%m%d-%H%M%S')"
readonly log_directory="$project_root/.artifacts/scratch/logs"
readonly test_log="$log_directory/$run_timestamp-test-$$.log"
readonly preview_build_log="$log_directory/$run_timestamp-preview-build-$$.log"
readonly finder_menu_capture_check_log="$log_directory/$run_timestamp-finder-menu-capture-check-$$.log"
readonly readme_image_composer_log="$log_directory/$run_timestamp-readme-image-composer-$$.log"
readonly user_focus_restoration_log="$log_directory/$run_timestamp-user-focus-restoration-$$.log"
readonly environment_switch_log="$log_directory/$run_timestamp-environment-switch-$$.log"
readonly test_artifact_directory="$project_root/.artifacts/scratch/tests/$run_timestamp-xctest-$$"
readonly result_bundle_path="$test_artifact_directory/ECMenu.xcresult"
readonly preview_executable="$derived_data_path/Build/Products/Debug/ECMenuPreviews.app/Contents/MacOS/ECMenuPreviews"
readonly readme_image_composer_source="$project_root/Tests/READMEImageCapture/Support/READMEOverviewComposer.swift"
readonly readme_image_composer="$test_artifact_directory/READMEOverviewComposer"
readonly readme_image_module_cache="$test_artifact_directory/readme-image-module-cache"
readonly user_focus_model_source="$project_root/Tests/UserFocusRestoration/Support/UserFocusRestorationModel.swift"
readonly user_focus_restorer_source="$project_root/Tests/UserFocusRestoration/Support/UserFocusRestorer.swift"
readonly user_focus_tests_source="$project_root/Tests/UserFocusRestoration/Tests/UserFocusRestorationTests.swift"
readonly user_focus_restorer="$test_artifact_directory/UserFocusRestorer"
readonly user_focus_tests="$test_artifact_directory/UserFocusRestorationTests"
readonly user_focus_module_cache="$test_artifact_directory/user-focus-module-cache"
readonly developer_directory="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
readonly destination="${XCODE_DESTINATION:-platform=macOS,arch=arm64}"

source "$script_directory/lib/user-focus.sh"

ecmenu_reexec_preserving_user_focus "$script_path" "$@"

mkdir -p \
    "$log_directory" \
    "$test_artifact_directory" \
    "$readme_image_module_cache" \
    "$user_focus_module_cache"
cd "$project_root"

if python3 Tests/DevelopmentScripts/EnvironmentSwitchTests.py \
    >"$environment_switch_log" 2>&1; then
    :
else
    script_test_status=$?
    print -u2 "Environment switch tests failed. Log: $environment_switch_log"
    tail -n 200 "$environment_switch_log" >&2
    exit "$script_test_status"
fi

if DEVELOPER_DIR="$developer_directory" xcodebuild \
    -project ECMenu.xcodeproj \
    -scheme ECMenu \
    -configuration Debug \
    -destination "$destination" \
    -derivedDataPath "$derived_data_path" \
    -resultBundlePath "$result_bundle_path" \
    test -quiet >"$test_log" 2>&1; then
    :
else
    test_status=$?
    print -u2 "Tests failed. Log: $test_log"
    tail -n 200 "$test_log" >&2
    exit "$test_status"
fi

if DEVELOPER_DIR="$developer_directory" xcodebuild \
    -project ECMenu.xcodeproj \
    -scheme ECMenuPreviews \
    -configuration Debug \
    -destination "$destination" \
    -derivedDataPath "$derived_data_path" \
    CODE_SIGNING_ALLOWED=NO \
    build -quiet >"$preview_build_log" 2>&1; then
    :
else
    preview_build_status=$?
    print -u2 "Preview build failed. Log: $preview_build_log"
    tail -n 200 "$preview_build_log" >&2
    exit "$preview_build_status"
fi

if preview_ids="$("$preview_executable" --list 2>>"$preview_build_log")" \
    && [[ -n "$preview_ids" ]]; then
    {
        print
        print "Registered UI previews:"
        print "$preview_ids"
    } >>"$preview_build_log"
else
    preview_list_status=$?
    print -u2 "Preview registry smoke test failed. Log: $preview_build_log"
    tail -n 200 "$preview_build_log" >&2
    exit "${preview_list_status:-1}"
fi

if DEVELOPER_DIR="$developer_directory" xcrun swiftc \
    -module-cache-path "$readme_image_module_cache" \
    "$readme_image_composer_source" \
    -framework CoreGraphics \
    -framework ImageIO \
    -framework UniformTypeIdentifiers \
    -o "$readme_image_composer" \
    >"$readme_image_composer_log" 2>&1; then
    :
else
    readme_image_composer_status=$?
    print -u2 \
        "README image composer build failed. Log: $readme_image_composer_log"
    tail -n 200 "$readme_image_composer_log" >&2
    exit "$readme_image_composer_status"
fi

if DEVELOPER_DIR="$developer_directory" xcrun swiftc \
    -module-cache-path "$user_focus_module_cache" \
    "$user_focus_model_source" \
    "$user_focus_restorer_source" \
    -framework AppKit \
    -o "$user_focus_restorer" \
    >"$user_focus_restoration_log" 2>&1 \
    && DEVELOPER_DIR="$developer_directory" xcrun swiftc \
        -module-cache-path "$user_focus_module_cache" \
        "$user_focus_model_source" \
        "$user_focus_tests_source" \
        -o "$user_focus_tests" \
        >>"$user_focus_restoration_log" 2>&1 \
    && "$user_focus_tests" \
        >>"$user_focus_restoration_log" 2>&1; then
    :
else
    user_focus_restoration_status=$?
    print -u2 \
        "User focus restoration tests failed. Log: $user_focus_restoration_log"
    tail -n 200 "$user_focus_restoration_log" >&2
    exit "$user_focus_restoration_status"
fi

if "$script_directory/capture-finder-menus.sh" --check \
    >"$finder_menu_capture_check_log" 2>&1; then
    :
else
    finder_menu_capture_check_status=$?
    print -u2 \
        "Finder menu capture smoke test failed. Log: $finder_menu_capture_check_log"
    tail -n 200 "$finder_menu_capture_check_log" >&2
    exit "$finder_menu_capture_check_status"
fi

if passed_count="$(
    DEVELOPER_DIR="$developer_directory" xcrun xcresulttool \
        get test-results summary \
        --path "$result_bundle_path" \
        --format json \
        | plutil -extract passedTests raw -o - -
)" && [[ "$passed_count" == <-> ]]; then
    :
else
    print -u2 "Could not read the passed test count: $result_bundle_path"
    exit 1
fi

print "Tests passed: $passed_count"
print "Test log: $test_log"
print "Test result bundle: $result_bundle_path"
print "Preview build and registry smoke test passed. Log: $preview_build_log"
print "Finder menu capture smoke test passed. Log: $finder_menu_capture_check_log"
print "README image composer build passed. Log: $readme_image_composer_log"
print "User focus restoration tests passed. Log: $user_focus_restoration_log"
print "Environment switch tests passed. Log: $environment_switch_log"
