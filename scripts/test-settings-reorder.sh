#!/bin/zsh

# 构建独立的设置排序诊断工具，在用户批准后拖动或点击指定 Preview 窗口并保存截图。
# --check 只查询现有输入权限；编译产物与截图保存在本次 scratch 目录，不操作产品配置。

set -euo pipefail

readonly script_path="${0:A}"
readonly project_root="${script_path:h:h}"
readonly developer_directory="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

usage() {
    print "Usage: ./scripts/test-settings-reorder.sh --check"
    print "       ./scripts/test-settings-reorder.sh --click <preview-pid> <x> <y>"
    print "       ./scripts/test-settings-reorder.sh <preview-pid> <from-x> <from-y> <to-x> <to-y> <duration-seconds> [--cancel]"
    print "Coordinates are relative to the Preview window's top-left corner; duration is 0.5–10 seconds."
    print "Mouse input requires explicit user approval and targets only com.axiomace.ecmenu.test.preview."
}

if (( $# == 1 )) && [[ "$1" == --help || "$1" == -h ]]; then
    usage
    exit 0
fi

if (( $# == 1 )) && [[ "$1" == --check ]]; then
    :
elif (( $# == 4 )) && [[ "$1" == --click ]]; then
    :
elif (( $# == 6 )) || { (( $# == 7 )) && [[ "$7" == --cancel ]]; }; then
    :
else
    usage >&2
    exit 64
fi

readonly run_name="$(date '+%Y%m%d-%H%M%S')-settings-reorder-$$"
readonly probe_directory="$project_root/.artifacts/scratch/probes/$run_name"
readonly build_log="$project_root/.artifacts/scratch/logs/$run_name.log"
readonly helper_path="$probe_directory/SettingsReorderAutomation"

mkdir -p "$probe_directory/module-cache" "${build_log:h}"
cd "$project_root"

if DEVELOPER_DIR="$developer_directory" xcrun swiftc \
    -parse-as-library \
    -module-cache-path "$probe_directory/module-cache" \
    "$project_root/Tests/SettingsReordering/SettingsReorderAutomation.swift" \
    -o "$helper_path" >"$build_log" 2>&1; then
    :
else
    build_status=$?
    print -u2 "Settings reorder tool build failed. Log: $build_log"
    tail -n 100 "$build_log" >&2
    exit "$build_status"
fi

print "Build log: $build_log"
if (( $# == 1 )); then
    exec "$helper_path" --check
fi
if [[ "$1" == --click ]]; then
    exec "$helper_path" "$@" "$probe_directory/click.png"
fi

drag_arguments=("${@:1:6}" "$probe_directory/drag.png")
if (( $# == 7 )); then
    drag_arguments+=(--cancel)
fi
exec "$helper_path" "${drag_arguments[@]}"
