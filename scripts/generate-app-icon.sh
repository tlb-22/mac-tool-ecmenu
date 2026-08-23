#!/bin/zsh

set -euo pipefail

readonly script_directory="${0:A:h}"
readonly project_root="${script_directory:h}"
readonly design_directory="$project_root/design/AppIcon"
readonly compose_script="$design_directory/compose.sh"
readonly generated_icon_package="$design_directory/output/ApplicationIcon.icon"
readonly generated_settings_icon="$design_directory/output/Preview/SettingsAppIcon.svg"
readonly target_icon_package="$project_root/EnhancedContextMenu/ApplicationIcon.icon"
readonly target_settings_directory="$project_root/EnhancedContextMenu/Assets.xcassets/SettingsAppIcon.imageset"
readonly target_settings_icon="$target_settings_directory/SettingsAppIcon.svg"

fail() {
    print -u2 -- "$1"
    exit 1
}

verify_design_output() {
    local -a required_files=(
        "$generated_icon_package/icon.json"
        "$generated_icon_package/Assets/ClickWaves.svg"
        "$generated_icon_package/Assets/Pointer.svg"
        "$generated_settings_icon"
    )
    local required_file
    for required_file in "${required_files[@]}"; do
        [[ -s "$required_file" ]] || fail "Missing AppIcon design output: $required_file"
    done
}

project_resources_match() {
    [[ -d "$target_icon_package" ]] \
        && /usr/bin/diff -qr "$generated_icon_package" "$target_icon_package" >/dev/null \
        && [[ -f "$target_settings_icon" ]] \
        && /usr/bin/cmp -s "$generated_settings_icon" "$target_settings_icon"
}

sync_project_resources() {
    if [[ -L "$target_icon_package" || ( -e "$target_icon_package" && ! -d "$target_icon_package" ) ]]; then
        fail "ApplicationIcon target must be a real directory: $target_icon_package"
    fi
    /bin/mkdir -p "$target_icon_package" "$target_settings_directory"

    if ! /usr/bin/diff -qr "$generated_icon_package" "$target_icon_package" >/dev/null; then
        /usr/bin/rsync -a --delete "$generated_icon_package/" "$target_icon_package/"
    fi

    if [[ -L "$target_settings_icon" || ( -e "$target_settings_icon" && ! -f "$target_settings_icon" ) ]]; then
        fail "Settings AppIcon target must be a regular file: $target_settings_icon"
    fi
    if [[ ! -f "$target_settings_icon" ]] \
        || ! /usr/bin/cmp -s "$generated_settings_icon" "$target_settings_icon"; then
        /bin/cp "$generated_settings_icon" "$target_settings_icon"
    fi
}

if (( $# > 1 )) || [[ -n "${1:-}" && "${1:-}" != "--check" ]]; then
    print -u2 "Usage: $0 [--check]"
    exit 2
fi

[[ -x "$compose_script" ]] || fail "AppIcon composition script is not executable: $compose_script"
"$compose_script"
verify_design_output

if [[ "${1:-}" == "--check" ]]; then
    project_resources_match \
        || fail "Project AppIcon resources differ from design/AppIcon/output. Run ./scripts/generate-app-icon.sh."
    print "Project AppIcon resources match the design output."
    exit 0
fi

sync_project_resources
project_resources_match \
    || fail "Project AppIcon resources do not match the design output after synchronization."

print "Project AppIcon resources synchronized from: $design_directory/output"
print "Design previews: $design_directory/output/Preview"
