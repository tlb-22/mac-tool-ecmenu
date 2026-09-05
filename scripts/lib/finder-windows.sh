#!/bin/zsh

# 在最外层测试入口记录 Finder 窗口；子脚本和焦点恢复完成后再核对。
ecmenu_reexec_checking_finder_windows() {
    local script_path="$1"
    shift

    [[ -n "${ECMENU_FINDER_WINDOW_SESSION:-}" ]] && return 0
    exec "${script_path:A:h}/lib/with-finder-windows-checked.sh" \
        "$script_path" "$@"
}
