#!/bin/zsh

# 隐藏命令只在选中项目时出现。

finder_menu_capture_visibility_required_command_keys() {
    case "$1" in
        plain-file|directory|multiple-images)
            print -r -- command.hideItems
            ;;
    esac
}
