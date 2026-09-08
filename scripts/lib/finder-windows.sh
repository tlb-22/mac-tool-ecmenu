#!/bin/zsh

# 为测试入口接入最外层 Finder 窗口保护会话。
# 通过重执行包装原命令，确保嵌套脚本共享同一次前后窗口核对。

ecmenu_reexec_checking_finder_windows() {
    local script_path="$1"
    shift

    [[ -n "${ECMENU_FINDER_WINDOW_SESSION:-}" ]] && return 0
    exec "${script_path:A:h}/lib/with-finder-windows-checked.sh" \
        "$script_path" "$@"
}
