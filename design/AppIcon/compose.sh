#!/bin/zsh

set -euo pipefail
umask 022

readonly design_directory="${0:a:h}"
readonly source_svg="$design_directory/AppIcon.svg"
readonly manifest_template="$design_directory/IconComposer.template.json"
readonly output_directory="$design_directory/output"
readonly manifest_background_placeholder="__FROM_APP_ICON_SVG__"
readonly settings_view_id="settings-app-icon-view"
readonly developer_directory="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
readonly icon_composer_tool="${developer_directory:h}/Applications/Icon Composer.app/Contents/Executables/ictool"
readonly xml_tool="/usr/bin/xmllint"
readonly json_tool="/usr/bin/jq"

typeset staged_output=""

cleanup() {
    local exit_status=$?
    trap - EXIT
    if [[ -n "$staged_output" && -d "$staged_output" ]]; then
        /bin/rm -rf "$staged_output"
    fi
    exit "$exit_status"
}

trap cleanup EXIT

fail() {
    print -u2 -- "$1"
    exit 1
}

require_unique_group() {
    local element_id="$1"
    local count
    count="$($xml_tool --xpath "count(//*[local-name()='g' and @id='$element_id'])" "$source_svg")"
    [[ "$count" == "1" ]] || fail "AppIcon.svg must contain exactly one group with id '$element_id'."
}

icon_color_from_hex() {
    local hex_color="${1#\#}"
    if [[ ! "$hex_color" =~ '^[[:xdigit:]]{6}$' ]]; then
        print -u2 "Invalid AppIcon background color: $1"
        return 1
    fi

    local red=$(( 16#${hex_color[1,2]} ))
    local green=$(( 16#${hex_color[3,4]} ))
    local blue=$(( 16#${hex_color[5,6]} ))
    LC_NUMERIC=C printf \
        'srgb:%.5f,%.5f,%.5f,1.00000' \
        "$(( red / 255.0 ))" \
        "$(( green / 255.0 ))" \
        "$(( blue / 255.0 ))"
}

write_svg_document() {
    local output_path="$1"
    local width="$2"
    local height="$3"
    local view_box="$4"
    local include_definitions="$5"
    shift 5

    {
        print -r -- '<?xml version="1.0" encoding="UTF-8"?>'
        print -r -- '<svg xmlns="http://www.w3.org/2000/svg" width="'"$width"'" height="'"$height"'" viewBox="'"$view_box"'">'

        if [[ "$include_definitions" == true ]]; then
            $xml_tool \
                --xpath '/*[local-name()="svg"]/*[local-name()="defs"]' \
                "$source_svg"
            print
        fi

        local element_id
        for element_id in "$@"; do
            $xml_tool \
                --xpath "//*[local-name()='g' and @id='$element_id']" \
                "$source_svg"
            print
        done

        print -r -- '</svg>'
    } > "$output_path"

    $xml_tool --noout "$output_path"
}

[[ -f "$source_svg" ]] || fail "Missing AppIcon design source: $source_svg"
[[ -f "$manifest_template" ]] || fail "Missing Icon Composer template: $manifest_template"
[[ -x "$icon_composer_tool" ]] || fail "Icon Composer is unavailable: $icon_composer_tool"
if [[ -L "$output_directory" || ( -e "$output_directory" && ! -d "$output_directory" ) ]]; then
    fail "AppIcon output must be a real directory when it exists: $output_directory"
fi

$xml_tool --noout "$source_svg"
require_unique_group "background-layer"
require_unique_group "click-wave-layer"
require_unique_group "pointer-layer"

readonly source_width="$($xml_tool --xpath 'string(/*[local-name()="svg"]/@width)' "$source_svg")"
readonly source_height="$($xml_tool --xpath 'string(/*[local-name()="svg"]/@height)' "$source_svg")"
readonly source_view_box="$($xml_tool --xpath 'string(/*[local-name()="svg"]/@viewBox)' "$source_svg")"
[[ -n "$source_width" && -n "$source_height" && -n "$source_view_box" ]] \
    || fail "AppIcon.svg must declare width, height, and viewBox."
readonly settings_view_count="$($xml_tool \
    --xpath "count(/*[local-name()='svg']/*[local-name()='view' and @id='$settings_view_id'])" \
    "$source_svg")"
[[ "$settings_view_count" == "1" ]] \
    || fail "AppIcon.svg must contain exactly one view with id '$settings_view_id'."
readonly settings_icon_view_box="$($xml_tool \
    --xpath "string(/*[local-name()='svg']/*[local-name()='view' and @id='$settings_view_id']/@viewBox)" \
    "$source_svg")"
[[ -n "$settings_icon_view_box" ]] \
    || fail "The '$settings_view_id' view must declare a viewBox."

readonly template_background="$($json_tool -er '.fill.solid | strings' "$manifest_template")"
[[ "$template_background" == "$manifest_background_placeholder" ]] \
    || fail "Icon Composer template fill.solid must contain the background placeholder."

staged_output="$(/usr/bin/mktemp -d "$design_directory/.compose-staging.XXXXXX")"
readonly staged_icon_package="$staged_output/ApplicationIcon.icon"
readonly staged_icon_assets="$staged_icon_package/Assets"
readonly staged_preview_directory="$staged_output/Preview"
readonly staged_app_preview="$staged_preview_directory/ApplicationIcon-Default.png"
readonly staged_settings_icon="$staged_preview_directory/SettingsAppIcon.svg"
/bin/mkdir -p "$staged_icon_assets" "$staged_preview_directory"

write_svg_document \
    "$staged_icon_assets/ClickWaves.svg" \
    "$source_width" \
    "$source_height" \
    "$source_view_box" \
    true \
    "click-wave-layer"
write_svg_document \
    "$staged_icon_assets/Pointer.svg" \
    "$source_width" \
    "$source_height" \
    "$source_view_box" \
    false \
    "pointer-layer"
write_svg_document \
    "$staged_settings_icon" \
    "$source_width" \
    "$source_height" \
    "$settings_icon_view_box" \
    true \
    "click-wave-layer" \
    "pointer-layer"

readonly background_hex="$($xml_tool \
    --xpath 'string(//*[local-name()="g" and @id="background-layer"]/@fill)' \
    "$source_svg")"
readonly background_color="$(icon_color_from_hex "$background_hex")"
$json_tool \
    --arg background_color "$background_color" \
    '.fill.solid = $background_color' \
    "$manifest_template" > "$staged_icon_package/icon.json"

"$icon_composer_tool" \
    "$staged_icon_package" \
    --export-image \
    --output-file "$staged_app_preview" \
    --platform macOS \
    --rendition Default \
    --width "$source_width" \
    --height "$source_height" \
    --scale 1 >/dev/null
[[ -s "$staged_app_preview" ]] \
    || fail "Icon Composer preview rendering failed: $staged_app_preview"

if [[ ! -d "$output_directory" ]] \
    || ! /usr/bin/diff -qr "$staged_output" "$output_directory" >/dev/null; then
    /bin/rm -rf "$output_directory"
    /bin/mv "$staged_output" "$output_directory"
    staged_output=""
fi
print "AppIcon design output generated at: $output_directory"
