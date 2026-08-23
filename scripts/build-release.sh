#!/bin/zsh

set -euo pipefail

readonly script_directory="${0:A:h}"
readonly project_root="${script_directory:h}"
readonly derived_data_path="$project_root/.derivedData"
readonly run_timestamp="$(date '+%Y%m%d-%H%M%S')"
readonly log_directory="$project_root/.artifacts/scratch/logs"
readonly release_log="$log_directory/$run_timestamp-release-$$.log"
readonly verification_probe="$project_root/.artifacts/scratch/probes/$run_timestamp-release-verify-$$"
readonly build_settings_path="$verification_probe/build-settings.json"
readonly developer_directory="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
readonly destination="generic/platform=macOS"
readonly launch_services_register="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
readonly expected_application_name="ECMenu"
readonly expected_application_bundle_identifier="com.axiomace.ecmenu"
readonly expected_extension_bundle_identifier="com.axiomace.ecmenu.finderext"
readonly expected_application_group_identifier="GVPW27HJZ5.ecmenu"

fail() {
    local message="$1"

    print -u2 -r -- "$message"
    print -r -- "ERROR: $message" >>"$release_log"
    print -u2 "Release log: $release_log"
    tail -n 200 "$release_log" >&2 || true
    exit 1
}

log() {
    print -r -- "$1"
    print -r -- "$1" >>"$release_log"
}

plist_value() {
    local plist_path="$1"
    local key_path="$2"

    /usr/libexec/PlistBuddy \
        -c "Print :$key_path" \
        "$plist_path" \
        2>/dev/null || true
}

build_setting() {
    local entry_index="$1"
    local setting_name="$2"

    plutil \
        -extract "$entry_index.buildSettings.$setting_name" \
        raw \
        -o - \
        "$build_settings_path" \
        2>/dev/null || true
}

require_equal() {
    local actual="$1"
    local expected="$2"
    local description="$3"

    if [[ "$actual" != "$expected" ]]; then
        fail "$description: expected '$expected', found '${actual:-<empty>}'."
    fi
}

require_nonempty() {
    local value="$1"
    local description="$2"

    if [[ -z "$value" ]]; then
        fail "$description is empty."
    fi
}

code_signing_value() {
    local bundle_path="$1"
    local key="$2"

    codesign -dv "$bundle_path" 2>&1 \
        | sed -n "s/^$key=//p" \
        || true
}

signed_entitlement_value() {
    local bundle_path="$1"
    local entitlement_key="$2"

    codesign --display --entitlements - "$bundle_path" 2>&1 \
        | awk -v key="$entitlement_key" '
            index($0, "[Key] " key) { found = 1; next }
            found && /\[Key\]/ { exit }
            found && /\[(String|Bool)\]/ {
                sub(/^.*\[(String|Bool)\] /, "")
                print
                exit
            }
        ' \
        || true
}

remove_archive_intermediate_registrations() {
    local archive_intermediates_root="${derived_data_path:A}/Build/Intermediates.noindex/ArchiveIntermediates"
    local application_info_plist
    local parent_application_path
    local registered_extension_path
    local registered_paths_text

    registered_paths_text="$(
        pluginkit -m -A -D -vv \
            -i "$expected_extension_bundle_identifier" \
            | sed -n 's/^[[:space:]]*Path = //p' \
            || true
    )"
    [[ -n "$registered_paths_text" ]] || return 0

    for registered_extension_path in "${(@f)registered_paths_text}"; do
        parent_application_path="${registered_extension_path%/Contents/PlugIns/*}"
        if [[ "$parent_application_path" == "$registered_extension_path" \
            || "${parent_application_path:A}" \
                != "$archive_intermediates_root"/*/InstallationBuildProductsLocation/Applications/*.app ]]; then
            continue
        fi

        application_info_plist="$parent_application_path/Contents/Info.plist"
        require_equal \
            "$(plist_value "$application_info_plist" CFBundleIdentifier)" \
            "$expected_application_bundle_identifier" \
            "Archive intermediate registration application identifier"
        require_equal \
            "$(plist_value "$registered_extension_path/Contents/Info.plist" CFBundleIdentifier)" \
            "$expected_extension_bundle_identifier" \
            "Archive intermediate registration extension identifier"

        if ! pluginkit -r "$registered_extension_path" \
            >>"$release_log" 2>&1; then
            fail "Could not remove the Archive intermediate Finder Extension registration: $registered_extension_path"
        fi
        if ! "$launch_services_register" -u "$parent_application_path" \
            >>"$release_log" 2>&1; then
            fail "Could not unregister the Archive intermediate application: $parent_application_path"
        fi
        log "Removed Archive intermediate registration: $parent_application_path"
    done
}

validate_info_plist() {
    local bundle_path="$1"
    local expected_bundle_identifier="$2"
    local description="$3"
    local info_plist="$bundle_path/Contents/Info.plist"

    [[ -f "$info_plist" ]] || fail "$description Info.plist is missing: $info_plist"
    require_equal \
        "$(plist_value "$info_plist" CFBundleIdentifier)" \
        "$expected_bundle_identifier" \
        "$description bundle identifier"
    require_equal \
        "$(plist_value "$info_plist" CFBundleShortVersionString)" \
        "$release_version" \
        "$description version"
    require_equal \
        "$(plist_value "$info_plist" CFBundleVersion)" \
        "$release_build" \
        "$description build"
    require_equal \
        "$(plist_value "$info_plist" CFBundleDisplayName)" \
        "$expected_application_name" \
        "$description display name"
    require_equal \
        "$(plist_value "$info_plist" ECMApplicationSigningIdentifier)" \
        "$expected_application_bundle_identifier" \
        "$description configured application signing identifier"
    require_equal \
        "$(plist_value "$info_plist" ECMFinderExtensionSigningIdentifier)" \
        "$expected_extension_bundle_identifier" \
        "$description configured Finder Extension signing identifier"
    require_equal \
        "$(plist_value "$info_plist" ECMApplicationGroupIdentifier)" \
        "$expected_application_group_identifier" \
        "$description configured App Group"
}

uuid_fingerprint() {
    local binary_path="$1"
    local output

    if ! output="$(
        DEVELOPER_DIR="$developer_directory" xcrun dwarfdump --uuid "$binary_path" 2>&1
    )"; then
        print -r -- "$output" >>"$release_log"
        return 1
    fi
    print -r -- "$output" >>"$release_log"
    print -r -- "$output" \
        | awk '/^UUID:/ { print $2, $3 }' \
        | LC_ALL=C sort
}

mkdir -p "$log_directory" "$verification_probe"
: >"$release_log"
cd "$project_root"

log "Resolving Release build settings."
if ! DEVELOPER_DIR="$developer_directory" xcodebuild \
    -project EnhancedContextMenu.xcodeproj \
    -scheme EnhancedContextMenu \
    -configuration Release \
    -destination "$destination" \
    -derivedDataPath "$derived_data_path" \
    -showBuildSettings \
    -json >"$build_settings_path" 2>>"$release_log"; then
    fail "Could not resolve Release build settings."
fi

typeset -i settings_index=0
typeset -i application_settings_index=-1
while target_name="$(
    plutil -extract "$settings_index.target" raw -o - "$build_settings_path" 2>/dev/null
)"; do
    candidate_bundle_identifier="$(
        build_setting "$settings_index" PRODUCT_BUNDLE_IDENTIFIER
    )"
    case "$candidate_bundle_identifier" in
        "$expected_application_bundle_identifier")
            (( application_settings_index == -1 )) \
                || fail "Release application build settings are ambiguous."
            application_settings_index=$settings_index
            ;;
    esac
    (( settings_index += 1 ))
done

(( application_settings_index >= 0 )) \
    || fail "Release application build settings were not found."

readonly release_version="$(
    build_setting "$application_settings_index" MARKETING_VERSION
)"
readonly release_build="$(
    build_setting "$application_settings_index" CURRENT_PROJECT_VERSION
)"
readonly application_full_product_name="$(
    build_setting "$application_settings_index" FULL_PRODUCT_NAME
)"
readonly application_development_team="$(
    build_setting "$application_settings_index" DEVELOPMENT_TEAM
)"

require_nonempty "$release_version" "Release version"
require_nonempty "$release_build" "Release build"
require_nonempty "$application_full_product_name" "Release application product name"
require_nonempty "$application_development_team" "Release development Team"
if [[ "$release_version" == .* || "$release_version" == *[^A-Za-z0-9._-]* ]]; then
    fail "Release version is unsafe for an artifact path: $release_version"
fi
if [[ "$release_build" == .* || "$release_build" == *[^A-Za-z0-9._-]* ]]; then
    fail "Release build is unsafe for an artifact path: $release_build"
fi

require_equal \
    "$(build_setting "$application_settings_index" CODE_SIGN_STYLE)" \
    Automatic \
    "Release application signing style"
require_equal \
    "$application_development_team" \
    "${expected_application_group_identifier%%.*}" \
    "Release Team and App Group prefix"

require_equal \
    "$(build_setting "$application_settings_index" ECMENU_APPLICATION_BUNDLE_IDENTIFIER)" \
    "$expected_application_bundle_identifier" \
    "Release configured application identifier"
require_equal \
    "$(build_setting "$application_settings_index" ECMENU_FINDER_EXTENSION_BUNDLE_IDENTIFIER)" \
    "$expected_extension_bundle_identifier" \
    "Release configured Finder Extension identifier"
require_equal \
    "$(build_setting "$application_settings_index" ECMENU_APPLICATION_GROUP_IDENTIFIER)" \
    "$expected_application_group_identifier" \
    "Release configured App Group"
require_equal \
    "$(build_setting "$application_settings_index" ECMENU_APPLICATION_NAME)" \
    "$expected_application_name" \
    "Release configured application name"

readonly release_directory="$project_root/.artifacts/releases/$release_version+$release_build"
readonly archive_path="$release_directory/ECMenu.xcarchive"
readonly zip_path="$release_directory/ECMenu-$release_version+$release_build.zip"
readonly checksum_path="$release_directory/SHA256SUMS"

if [[ -d "$release_directory" ]]; then
    existing_release_entries=("$release_directory"/*(DN))
    (( ${#existing_release_entries[@]} == 0 )) \
        || fail "Release directory is not empty; refusing to overwrite it: $release_directory"
elif [[ -e "$release_directory" || -L "$release_directory" ]]; then
    fail "Release artifact path exists and is not a directory: $release_directory"
fi
mkdir -p "$release_directory"

log "Archiving ECMenu $release_version ($release_build)."
if ! DEVELOPER_DIR="$developer_directory" xcodebuild \
    -project EnhancedContextMenu.xcodeproj \
    -scheme EnhancedContextMenu \
    -configuration Release \
    -destination "$destination" \
    -derivedDataPath "$derived_data_path" \
    -archivePath "$archive_path" \
    archive >>"$release_log" 2>&1; then
    fail "Release archive failed."
fi

readonly archive_info_plist="$archive_path/Info.plist"
[[ -f "$archive_info_plist" ]] || fail "Archive Info.plist is missing."
readonly archived_application_relative_path="$(
    plist_value "$archive_info_plist" ApplicationProperties:ApplicationPath
)"
require_nonempty "$archived_application_relative_path" "Archived application path"
case "/$archived_application_relative_path/" in
    */../* | */./*) fail "Archive contains an unsafe application path." ;;
esac
[[ "$archived_application_relative_path" != /* ]] \
    || fail "Archive application path must be relative."

readonly archive_products_path="${archive_path:A}/Products"
readonly application_path="$archive_products_path/$archived_application_relative_path"
[[ -d "$application_path" ]] || fail "Archived application is missing: $application_path"
[[ "${application_path:A}" == "$archive_products_path"/* ]] \
    || fail "Archived application resolves outside the archive Products directory."
require_equal \
    "${application_path:t}" \
    "$application_full_product_name" \
    "Archived application product name"
require_equal \
    "$(plist_value "$archive_info_plist" ApplicationProperties:CFBundleShortVersionString)" \
    "$release_version" \
    "Archive version"
require_equal \
    "$(plist_value "$archive_info_plist" ApplicationProperties:CFBundleVersion)" \
    "$release_build" \
    "Archive build"
require_equal \
    "$(plist_value "$archive_info_plist" ApplicationProperties:CFBundleIdentifier)" \
    "$expected_application_bundle_identifier" \
    "Archive application identifier"

forbidden_product="$(
    find "$archive_path" \
        \( -name '*.xctest' \
        -o -name '*.xctest.dSYM' \
        -o -name 'EnhancedContextMenuPreviews.app' \
        -o -name 'ContextCommandSender' \
        -o -name 'ContextCommandSender.dSYM' \) \
        -print -quit
)"
[[ -z "$forbidden_product" ]] \
    || fail "Archive contains a test, Preview, or helper product: $forbidden_product"

validate_info_plist \
    "$application_path" \
    "$expected_application_bundle_identifier" \
    "Release application"

readonly plugins_path="$application_path/Contents/PlugIns"
[[ -d "$plugins_path" ]] || fail "Archived application has no PlugIns directory."
embedded_extension_paths=()
while IFS= read -r -d '' candidate_extension_path; do
    candidate_info_plist="$candidate_extension_path/Contents/Info.plist"
    if [[ "$(plist_value "$candidate_info_plist" CFBundleIdentifier)" \
        == "$expected_extension_bundle_identifier" ]]; then
        embedded_extension_paths+=("$candidate_extension_path")
    fi
done < <(find "$plugins_path" -type d -name '*.appex' -prune -print0)
(( ${#embedded_extension_paths[@]} == 1 )) \
    || fail "Expected one embedded Release Finder Extension, found ${#embedded_extension_paths[@]}."
readonly extension_path="$embedded_extension_paths[1]"
validate_info_plist \
    "$extension_path" \
    "$expected_extension_bundle_identifier" \
    "Release Finder Extension"

if ! codesign --verify --strict --verbose=2 "$extension_path" \
    >>"$release_log" 2>&1; then
    fail "Release Finder Extension code signature is invalid."
fi
if ! codesign --verify --strict --verbose=2 "$application_path" \
    >>"$release_log" 2>&1; then
    fail "Release application code signature is invalid."
fi

readonly application_signing_identifier="$(
    code_signing_value "$application_path" Identifier
)"
readonly extension_signing_identifier="$(
    code_signing_value "$extension_path" Identifier
)"
readonly application_team_identifier="$(
    code_signing_value "$application_path" TeamIdentifier
)"
readonly extension_team_identifier="$(
    code_signing_value "$extension_path" TeamIdentifier
)"
require_equal \
    "$application_signing_identifier" \
    "$expected_application_bundle_identifier" \
    "Release application signing identifier"
require_equal \
    "$extension_signing_identifier" \
    "$expected_extension_bundle_identifier" \
    "Release Finder Extension signing identifier"
require_nonempty "$application_team_identifier" "Release application signing Team"
require_equal \
    "$extension_team_identifier" \
    "$application_team_identifier" \
    "Release signing Team"
require_equal \
    "$application_team_identifier" \
    "$application_development_team" \
    "Release signing and build-setting Team"

require_equal \
    "$(signed_entitlement_value "$application_path" 'com.apple.security.application-groups')" \
    "$expected_application_group_identifier" \
    "Release application signed App Group"
require_equal \
    "$(signed_entitlement_value "$extension_path" 'com.apple.security.application-groups')" \
    "$expected_application_group_identifier" \
    "Release Finder Extension signed App Group"
require_equal \
    "$(signed_entitlement_value "$extension_path" 'com.apple.security.app-sandbox')" \
    true \
    "Release Finder Extension sandbox entitlement"

readonly application_executable_name="$(
    plist_value "$application_path/Contents/Info.plist" CFBundleExecutable
)"
readonly extension_executable_name="$(
    plist_value "$extension_path/Contents/Info.plist" CFBundleExecutable
)"
require_nonempty "$application_executable_name" "Release application executable name"
require_nonempty "$extension_executable_name" "Release Finder Extension executable name"
readonly application_executable="$application_path/Contents/MacOS/$application_executable_name"
readonly extension_executable="$extension_path/Contents/MacOS/$extension_executable_name"
readonly application_dsym="$archive_path/dSYMs/${application_path:t}.dSYM"
readonly extension_dsym="$archive_path/dSYMs/${extension_path:t}.dSYM"
[[ -f "$application_executable" ]] \
    || fail "Release application executable is missing."
[[ -f "$extension_executable" ]] \
    || fail "Release Finder Extension executable is missing."
[[ -d "$application_dsym" ]] \
    || fail "Release application dSYM is missing: $application_dsym"
[[ -d "$extension_dsym" ]] \
    || fail "Release Finder Extension dSYM is missing: $extension_dsym"

if ! application_binary_uuids="$(uuid_fingerprint "$application_executable")"; then
    fail "Could not read Release application UUIDs."
fi
if ! application_dsym_uuids="$(uuid_fingerprint "$application_dsym")"; then
    fail "Could not read Release application dSYM UUIDs."
fi
if ! extension_binary_uuids="$(uuid_fingerprint "$extension_executable")"; then
    fail "Could not read Release Finder Extension UUIDs."
fi
if ! extension_dsym_uuids="$(uuid_fingerprint "$extension_dsym")"; then
    fail "Could not read Release Finder Extension dSYM UUIDs."
fi
require_nonempty "$application_binary_uuids" "Release application UUID set"
require_nonempty "$extension_binary_uuids" "Release Finder Extension UUID set"
require_equal \
    "$application_dsym_uuids" \
    "$application_binary_uuids" \
    "Release application dSYM UUIDs"
require_equal \
    "$extension_dsym_uuids" \
    "$extension_binary_uuids" \
    "Release Finder Extension dSYM UUIDs"

log "Creating release ZIP."
if ! ditto -c -k --sequesterRsrc --keepParent \
    "$application_path" "$zip_path" >>"$release_log" 2>&1; then
    fail "Could not create the release ZIP."
fi

readonly unpack_directory="$verification_probe/unpacked"
mkdir -p "$unpack_directory"
if ! ditto -x -k "$zip_path" "$unpack_directory" \
    >>"$release_log" 2>&1; then
    fail "Could not unpack the release ZIP for verification."
fi
readonly unpacked_application_path="$unpack_directory/${application_path:t}"
readonly extension_relative_path="${extension_path#$application_path/}"
readonly unpacked_extension_path="$unpacked_application_path/$extension_relative_path"
[[ -d "$unpacked_application_path" ]] \
    || fail "The release ZIP does not contain the application bundle."
[[ -d "$unpacked_extension_path" ]] \
    || fail "The release ZIP does not contain the Finder Extension."
if ! codesign --verify --strict --verbose=2 "$unpacked_extension_path" \
    >>"$release_log" 2>&1; then
    fail "Unpacked Finder Extension code signature is invalid."
fi
if ! codesign --verify --strict --verbose=2 "$unpacked_application_path" \
    >>"$release_log" 2>&1; then
    fail "Unpacked application code signature is invalid."
fi
require_equal \
    "$(code_signing_value "$unpacked_application_path" Identifier)" \
    "$expected_application_bundle_identifier" \
    "Unpacked application signing identifier"
require_equal \
    "$(code_signing_value "$unpacked_extension_path" Identifier)" \
    "$expected_extension_bundle_identifier" \
    "Unpacked Finder Extension signing identifier"

if ! (
    cd "$release_directory"
    shasum -a 256 "${zip_path:t}" >"${checksum_path:t}"
    shasum -a 256 -c "${checksum_path:t}"
) >>"$release_log" 2>&1; then
    fail "Could not create or verify SHA256SUMS."
fi

remove_archive_intermediate_registrations

log "Release archive verified: $archive_path"
log "Release ZIP verified: $zip_path"
log "SHA-256: $checksum_path"
log "Release log: $release_log"
