#!/bin/zsh

set -euo pipefail

readonly script_path="${0:A}"
readonly script_directory="${script_path:h}"
readonly project_root="${script_directory:h}"
readonly definitions_path="$project_root/Tests/FinderMenuCapture/FinderMenuCaptureComposition.sh"
readonly localization_catalog="$project_root/ECMenuFinderExtension/Localizable.xcstrings"
readonly operation_lock_directory="$project_root/.artifacts/scratch/probes"
readonly operation_lock="$operation_lock_directory/preview-operation.lock"
readonly derived_data_path="$project_root/.derivedData"
readonly developer_directory="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
readonly destination="${XCODE_DESTINATION:-platform=macOS,arch=arm64}"
readonly helper_bundle_identifier="com.axiomace.ecmenu.test.findermenuautomation"

source "$definitions_path"

typeset -a registered_scenario_ids=()
typeset -a selected_scenario_ids=()
typeset mode=capture
typeset run_name=""
typeset test_directory=""
typeset output_directory=""
typeset log_directory=""
typeset build_log=""
typeset build_settings_log=""
typeset capture_log=""
typeset helper_executable=""

usage() {
    print "Usage: ./scripts/capture-finder-menus.sh [--list | --check | <scenario-id> ...]"
}

fail() {
    local message="$1"

    print -u2 -r -- "$message"
    if [[ -n "$capture_log" ]]; then
        print -r -- "ERROR: $message" >>"$capture_log"
        print -u2 "Capture log: $capture_log"
    fi
    exit 1
}

load_registry() {
    local scenario_id
    local scenario_ids_text
    local -A seen_ids=()

    if scenario_ids_text="$(finder_menu_capture_scenario_ids)"; then
        :
    else
        fail "Finder menu capture could not load its scenario registry."
    fi
    if [[ -n "$scenario_ids_text" ]]; then
        for scenario_id in "${(@f)scenario_ids_text}"; do
            [[ -n "$scenario_id" ]] \
                || fail "Finder menu capture registered an empty scenario ID."
            [[ "$scenario_id" =~ '^[a-z0-9]+(-[a-z0-9]+)*$' ]] \
                || fail "Finder menu capture registered an invalid scenario ID: $scenario_id"
            if (( ${+seen_ids[$scenario_id]} )); then
                fail "Finder menu capture registered a scenario twice: $scenario_id"
            fi
            seen_ids[$scenario_id]=1
            registered_scenario_ids+=("$scenario_id")
        done
    fi

    (( ${#registered_scenario_ids[@]} > 0 )) \
        || fail "The Finder menu capture registry is empty."
}

select_requested_scenarios() {
    local requested_id
    local registered_id
    local is_registered
    local -A seen_requested_ids=()

    if (( $# == 0 )); then
        selected_scenario_ids=("${registered_scenario_ids[@]}")
        return
    fi

    for requested_id in "$@"; do
        is_registered=false
        for registered_id in "${registered_scenario_ids[@]}"; do
            if [[ "$requested_id" == "$registered_id" ]]; then
                is_registered=true
                break
            fi
        done
        $is_registered || fail "Unknown Finder menu capture scenario: $requested_id"
        if (( ${+seen_requested_ids[$requested_id]} )); then
            fail "Finder menu capture scenario was requested twice: $requested_id"
        fi
        seen_requested_ids[$requested_id]=1
        selected_scenario_ids+=("$requested_id")
    done
}

initialize_run_directories() {
    local run_timestamp

    run_timestamp="$(date '+%Y%m%d-%H%M%S')"
    run_name="$run_timestamp-finder-menu-capture-$$"
    test_directory="$project_root/.artifacts/scratch/tests/$run_name"
    output_directory="$project_root/.artifacts/scratch/previews/$run_name"
    log_directory="$project_root/.artifacts/scratch/logs/$run_name"
    build_log="$log_directory/build.log"
    build_settings_log="$log_directory/helper-build-settings.json"
    capture_log="$log_directory/capture.log"
    helper_executable="$derived_data_path/Build/Products/Debug/FinderMenuAutomation"

    mkdir -p "$test_directory/fixtures" "$log_directory"
    if [[ "$mode" == capture ]]; then
        mkdir -p "$output_directory"
    fi
}

build_automation_helper() {
    local build_status
    local resolved_product_type
    local resolved_bundle_identifier
    local resolved_info_plist_setting
    local resolved_signing_flags
    local resolved_team_identifier
    local embedded_bundle_identifier
    local signing_identifier
    local team_identifier
    local -a build_overrides=()

    if [[ "$mode" == check ]]; then
        build_overrides+=(CODE_SIGNING_ALLOWED=NO)
    else
        build_overrides+=(CODE_SIGNING_ALLOWED=YES)
    fi

    if DEVELOPER_DIR="$developer_directory" xcodebuild \
        -project "$project_root/ECMenu.xcodeproj" \
        -scheme FinderMenuAutomation \
        -configuration Debug \
        -destination "$destination" \
        -derivedDataPath "$derived_data_path" \
        "${build_overrides[@]}" \
        build -quiet \
        >"$build_log" 2>&1; then
        :
    else
        build_status=$?
        print -u2 "Finder automation helper build failed. Log: $build_log"
        tail -n 200 "$build_log" >&2
        exit "$build_status"
    fi

    [[ -x "$helper_executable" ]] \
        || fail "Finder automation helper is missing after the build."

    if DEVELOPER_DIR="$developer_directory" xcodebuild \
        -project "$project_root/ECMenu.xcodeproj" \
        -scheme FinderMenuAutomation \
        -configuration Debug \
        -destination "$destination" \
        -derivedDataPath "$derived_data_path" \
        "${build_overrides[@]}" \
        -showBuildSettings -json \
        >"$build_settings_log" 2>>"$build_log"; then
        :
    else
        fail "Could not resolve Finder automation helper build settings."
    fi
    resolved_product_type="$(/usr/bin/plutil \
        -extract 0.buildSettings.PRODUCT_TYPE raw -o - "$build_settings_log")" \
        || fail "Finder automation helper has no resolved product type."
    resolved_bundle_identifier="$(/usr/bin/plutil \
        -extract 0.buildSettings.PRODUCT_BUNDLE_IDENTIFIER raw -o - "$build_settings_log")" \
        || fail "Finder automation helper has no resolved bundle identifier."
    resolved_info_plist_setting="$(/usr/bin/plutil \
        -extract 0.buildSettings.CREATE_INFOPLIST_SECTION_IN_BINARY raw -o - "$build_settings_log")" \
        || fail "Finder automation helper has no embedded Info.plist setting."
    resolved_signing_flags="$(/usr/bin/plutil \
        -extract 0.buildSettings.OTHER_CODE_SIGN_FLAGS raw -o - "$build_settings_log")" \
        || fail "Finder automation helper has no resolved signing flags."
    resolved_team_identifier="$(/usr/bin/plutil \
        -extract 0.buildSettings.DEVELOPMENT_TEAM raw -o - "$build_settings_log")" \
        || fail "Finder automation helper has no Development Team."

    [[ "$resolved_product_type" == com.apple.product-type.tool \
        && "$resolved_bundle_identifier" == "$helper_bundle_identifier" \
        && "$resolved_info_plist_setting" == YES \
        && "$resolved_signing_flags" == *"--identifier $helper_bundle_identifier"* \
        && -n "$resolved_team_identifier" ]] \
        || fail "Finder automation helper does not have a stable TCC identity configuration."

    embedded_bundle_identifier="$(
        /usr/bin/otool -v -s __TEXT __info_plist "$helper_executable" \
            | /usr/bin/sed -n '/^<?xml /,$p' \
            | /usr/bin/plutil -extract CFBundleIdentifier raw -o - -- -
    )" || fail "Finder automation helper has no readable embedded Info.plist."
    [[ "$embedded_bundle_identifier" == "$helper_bundle_identifier" ]] \
        || fail "Finder automation helper embedded an unexpected bundle identifier."

    if [[ "$mode" == capture ]]; then
        codesign --verify --strict "$helper_executable" 2>>"$build_log" \
            || fail "Finder automation helper signature is invalid."
        signing_identifier="$(codesign -dv "$helper_executable" 2>&1 \
            | sed -n 's/^Identifier=//p')"
        team_identifier="$(codesign -dv "$helper_executable" 2>&1 \
            | sed -n 's/^TeamIdentifier=//p')"
        [[ "$signing_identifier" == "$helper_bundle_identifier" \
            && "$team_identifier" == "$resolved_team_identifier" ]] \
            || fail "Finder automation helper does not have its stable Development identity."
    fi
}

localized_command_title() {
    local command_key="$1"
    local language="$2"
    local escaped_key="${command_key//./\\.}"

    /usr/bin/plutil \
        -extract "strings.$escaped_key.localizations.$language.stringUnit.value" \
        raw \
        -o - \
        "$localization_catalog" \
        2>>"$capture_log"
}

prepare_and_validate_fixtures() {
    local scenario_id
    local fixture_directory
    local context_kind
    local basename
    local command_key
    local english_title
    local chinese_title
    local selected_basenames_text
    local required_command_keys_text
    local -a selected_basenames=()
    local -a required_command_keys=()
    local -a fixture_items=()

    for scenario_id in "${selected_scenario_ids[@]}"; do
        fixture_directory="$test_directory/fixtures/$scenario_id"
        finder_menu_capture_create_fixture \
            "$scenario_id" \
            "$fixture_directory"
        [[ -d "$fixture_directory" ]] \
            || fail "Scenario did not create its fixture directory: $scenario_id"

        context_kind="$(finder_menu_capture_context_kind "$scenario_id")"
        [[ "$context_kind" == container || "$context_kind" == items ]] \
            || fail "Scenario has an invalid Finder context kind: $scenario_id"

        if selected_basenames_text="$(
            finder_menu_capture_selected_basenames "$scenario_id"
        )"; then
            :
        else
            fail "Scenario could not resolve selected items: $scenario_id"
        fi
        selected_basenames=()
        if [[ -n "$selected_basenames_text" ]]; then
            for basename in "${(@f)selected_basenames_text}"; do
                [[ -n "$basename" && "$basename" != */* ]] \
                    || fail "Scenario has an invalid selected basename: $scenario_id"
                [[ -e "$fixture_directory/$basename" ]] \
                    || fail "Scenario selected item does not exist: $scenario_id/$basename"
                selected_basenames+=("$basename")
            done
        fi

        if [[ "$context_kind" == container ]]; then
            (( ${#selected_basenames[@]} == 0 )) \
                || fail "Container scenario selects Finder items: $scenario_id"
            fixture_items=("$fixture_directory"/*(ND))
            (( ${#fixture_items[@]} > 0 )) \
                || fail "Container scenario has no opening item: $scenario_id"
        else
            (( ${#selected_basenames[@]} > 0 )) \
                || fail "Items scenario has no Finder selection: $scenario_id"
        fi

        if required_command_keys_text="$(
            finder_menu_capture_required_command_keys "$scenario_id"
        )"; then
            :
        else
            fail "Scenario could not resolve required commands: $scenario_id"
        fi
        required_command_keys=()
        if [[ -n "$required_command_keys_text" ]]; then
            for command_key in "${(@f)required_command_keys_text}"; do
                [[ -n "$command_key" ]] \
                    || fail "Scenario has an empty command key: $scenario_id"
                if english_title="$(localized_command_title "$command_key" en)" \
                    && chinese_title="$(localized_command_title "$command_key" zh-Hans)" \
                    && [[ -n "$english_title" && -n "$chinese_title" ]]; then
                    :
                else
                    fail "Scenario references an incomplete localized command: $scenario_id/$command_key"
                fi
                required_command_keys+=("$command_key")
            done
        fi
        (( ${#required_command_keys[@]} > 0 )) \
            || fail "Scenario has no required ECMenu commands: $scenario_id"
    done
}

helper_error_description() {
    local stdout_log="$1"
    local error_line
    local record
    local error_code
    local encoded_message
    local message

    error_line="$(/usr/bin/awk -F '\t' '$1 == "ERROR" && NF == 3 {
        print
        exit
    }' "$stdout_log")"
    [[ -n "$error_line" ]] || return 1
    IFS=$'\t' read -r record error_code encoded_message <<<"$error_line"
    message="$(print -rn -- "$encoded_message" | /usr/bin/base64 -D)" \
        || return 1
    print -r -- "$error_code: $message"
}

menu_titles_from_log() {
    local stdout_log="$1"
    local encoded_title

    while IFS=$'\t' read -r record encoded_title; do
        [[ "$record" == ITEM && -n "$encoded_title" ]] || continue
        print -rn -- "$encoded_title" | /usr/bin/base64 -D
        print
    done <"$stdout_log"
}

require_expected_menu_titles() {
    local scenario_id="$1"
    local stdout_log="$2"
    local image_path="$3"
    local command_key
    local english_title
    local chinese_title
    local actual_title
    local found
    local menu_titles_text
    local required_command_keys_text
    local -a menu_titles=()

    menu_titles_text="$(menu_titles_from_log "$stdout_log")" \
        || fail "Could not decode Finder menu titles: $scenario_id"
    if [[ -n "$menu_titles_text" ]]; then
        menu_titles=("${(@f)menu_titles_text}")
    fi

    if required_command_keys_text="$(
        finder_menu_capture_required_command_keys "$scenario_id"
    )"; then
        :
    else
        fail "Scenario could not resolve required commands: $scenario_id"
    fi
    if [[ -n "$required_command_keys_text" ]]; then
        for command_key in "${(@f)required_command_keys_text}"; do
            english_title="$(localized_command_title "$command_key" en)"
            chinese_title="$(localized_command_title "$command_key" zh-Hans)"
            found=false
            for actual_title in "${menu_titles[@]}"; do
                if [[ "$actual_title" == "$english_title" \
                    || "$actual_title" == "$chinese_title" ]]; then
                    found=true
                    break
                fi
            done
            if ! $found; then
                print -u2 "Finder menu items observed for $scenario_id:"
                for actual_title in "${menu_titles[@]}"; do
                    print -u2 -r -- "  $actual_title"
                done
                /bin/rm -f "$image_path"
                fail "Required ECMenu command is absent: $command_key"
            fi
        done
    fi
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

capture_scenario() {
    local scenario_id="$1"
    local fixture_directory="$test_directory/fixtures/$scenario_id"
    local stdout_log="$log_directory/$scenario_id.stdout.log"
    local stderr_log="$log_directory/$scenario_id.stderr.log"
    local image_path="$output_directory/$scenario_id.png"
    local context_kind
    local basename
    local image_dimensions
    local helper_status=0
    local helper_error
    local selected_basenames_text
    local -a selected_paths=()

    context_kind="$(finder_menu_capture_context_kind "$scenario_id")"
    if selected_basenames_text="$(
        finder_menu_capture_selected_basenames "$scenario_id"
    )"; then
        :
    else
        fail "Scenario could not resolve selected items: $scenario_id"
    fi
    if [[ -n "$selected_basenames_text" ]]; then
        for basename in "${(@f)selected_basenames_text}"; do
            selected_paths+=("$fixture_directory/$basename")
        done
    fi

    print -r -- "Capturing $scenario_id" | tee -a "$capture_log"
    if [[ "$context_kind" == container ]]; then
        "$helper_executable" container "$image_path" "$fixture_directory" \
            >"$stdout_log" 2>"$stderr_log" || helper_status=$?
    else
        "$helper_executable" items "$image_path" "${selected_paths[@]}" \
            >"$stdout_log" 2>"$stderr_log" || helper_status=$?
    fi
    if (( helper_status != 0 )); then
        /bin/rm -f "$image_path"
        helper_error="$(helper_error_description "$stdout_log" || true)"
        fail "Finder menu capture failed: $scenario_id${helper_error:+ ($helper_error)}. Logs: $stdout_log, $stderr_log"
    fi

    if ! /usr/bin/grep -qx CAPTURED "$stdout_log"; then
        /bin/rm -f "$image_path"
        fail "Finder helper did not confirm a stable capture: $scenario_id"
    fi
    require_expected_menu_titles "$scenario_id" "$stdout_log" "$image_path"

    if [[ -s "$image_path" ]] \
        && image_dimensions="$(png_dimensions "$image_path")"; then
        :
    else
        /bin/rm -f "$image_path"
        fail "Screenshot is not a non-empty PNG: $image_path"
    fi

    print -r -- "Captured $scenario_id.png ($image_dimensions)" \
        | tee -a "$capture_log"
}

load_registry

case "${1:-}" in
    --help|-h)
        (( $# == 1 )) || {
            usage >&2
            exit 64
        }
        usage
        exit 0
        ;;
    --list)
        (( $# == 1 )) || {
            usage >&2
            exit 64
        }
        print -l -- "${registered_scenario_ids[@]}"
        exit 0
        ;;
    --check)
        (( $# == 1 )) || {
            usage >&2
            exit 64
        }
        mode=check
        shift
        ;;
    --*)
        usage >&2
        exit 64
        ;;
esac

select_requested_scenarios "$@"

if [[ "$mode" == capture \
    && "${ECMENU_FINDER_MENU_OPERATION_LOCK:-}" != "$operation_lock" ]]; then
    mkdir -p "$operation_lock_directory"
    exec /usr/bin/lockf \
        -k \
        -t 0 \
        "$operation_lock" \
        /usr/bin/env \
        ECMENU_FINDER_MENU_OPERATION_LOCK="$operation_lock" \
        "$script_path" \
        "${selected_scenario_ids[@]}"
fi

initialize_run_directories
build_automation_helper
prepare_and_validate_fixtures

if [[ "$mode" == check ]]; then
    print "Finder menu capture definitions and helper build passed."
    print "Check artifacts: $test_directory"
    print "Check logs: $log_directory"
    exit 0
fi

readonly preflight_stdout_log="$log_directory/preflight.stdout.log"
readonly preflight_stderr_log="$log_directory/preflight.stderr.log"
if "$helper_executable" preflight \
    >"$preflight_stdout_log" \
    2>"$preflight_stderr_log"; then
    :
else
    preflight_line="$(/usr/bin/awk -F '\t' '$1 == "PREFLIGHT" && NF == 3 {
        print
        exit
    }' "$preflight_stdout_log")"
    fail "Finder menu capture requires Accessibility and Screen Recording permission. Current status: ${preflight_line:-unavailable}. Logs: $preflight_stdout_log, $preflight_stderr_log"
fi

if "$script_directory/run-debug.sh" \
    >"$log_directory/run-debug.log" 2>&1; then
    :
else
    run_debug_status=$?
    print -u2 "Debug Finder Extension setup failed. Log: $log_directory/run-debug.log"
    tail -n 200 "$log_directory/run-debug.log" >&2
    exit "$run_debug_status"
fi

for scenario_id in "${selected_scenario_ids[@]}"; do
    capture_scenario "$scenario_id"
done

print "Finder menu screenshots: $output_directory"
print "Capture logs: $log_directory"
