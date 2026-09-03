#!/bin/zsh

set -euo pipefail

readonly script_directory="${0:A:h}"
readonly project_root="${script_directory:h}"
readonly derived_data_path="$project_root/.derivedData"
readonly run_timestamp="$(date '+%Y%m%d-%H%M%S')"
readonly log_directory="$project_root/.artifacts/scratch/logs"
readonly test_log="$log_directory/$run_timestamp-test-$$.log"
readonly preview_build_log="$log_directory/$run_timestamp-preview-build-$$.log"
readonly test_artifact_directory="$project_root/.artifacts/scratch/tests/$run_timestamp-xctest-$$"
readonly result_bundle_path="$test_artifact_directory/ECMenu.xcresult"
readonly preview_executable="$derived_data_path/Build/Products/Debug/ECMenuPreviews.app/Contents/MacOS/ECMenuPreviews"
readonly developer_directory="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
readonly destination="${XCODE_DESTINATION:-platform=macOS,arch=arm64}"

mkdir -p "$log_directory" "$test_artifact_directory"
cd "$project_root"

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
