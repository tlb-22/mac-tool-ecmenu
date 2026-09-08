#!/bin/zsh

# 声明新建文件父菜单在空白处和单项选择截图场景中的可用性。
# 输出稳定本地化键，供截图入口核对父菜单标题。

finder_menu_capture_new_file_required_command_keys() {
    case "$1" in
        container|plain-file|directory)
            print -r -- command.newFile
            ;;
    esac
}
