#!/bin/zsh

# 新建文件父菜单在空白处和单项上下文中均应可用。

finder_menu_capture_new_file_required_command_keys() {
    case "$1" in
        container|plain-file|directory)
            print -r -- command.newFile
            ;;
    esac
}
