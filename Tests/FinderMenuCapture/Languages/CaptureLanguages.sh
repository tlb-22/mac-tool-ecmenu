#!/bin/zsh

# 真实 Finder 菜单截图支持的语言。Finder 资源名和产品语言 ID 显式对应，
# 避免把 `zh-Hans` 与 Finder 的 `zh_CN.lproj` 当作同名资源。

typeset -gra _finder_menu_capture_language_ids=(
    en
    zh-Hans
)

finder_menu_capture_language_ids() {
    print -l -- "${_finder_menu_capture_language_ids[@]}"
}

finder_menu_capture_finder_resource_name() {
    case "$1" in
        en)
            print en
            ;;
        zh-Hans)
            print zh_CN
            ;;
        *)
            return 64
            ;;
    esac
}

# Finder 原生菜单中跨当前截图场景稳定存在的语言标志项。
finder_menu_capture_finder_marker_title() {
    case "$1" in
        en)
            print "Get Info"
            ;;
        zh-Hans)
            print "显示简介"
            ;;
        *)
            return 64
            ;;
    esac
}
