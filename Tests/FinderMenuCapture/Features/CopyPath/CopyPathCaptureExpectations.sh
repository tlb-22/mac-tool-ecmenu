#!/bin/zsh

# 复制路径命令适用于当前覆盖的全部 Finder 上下文。

finder_menu_capture_copy_path_required_command_keys() {
    case "$1" in
        container|plain-file|directory|multiple-images)
            print -r -- command.copyPath
            ;;
    esac
}
