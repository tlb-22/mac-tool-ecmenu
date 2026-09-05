#!/bin/zsh

ecmenu_extension_registration() {
    pluginkit -m -A -D -vv -i "$1"
}

# 目标先登记成功，调用方随后清理同身份的其他路径。
ecmenu_register_product() {
    local app_path="$1"
    local extension_path="$2"
    local registration_tool="$3"

    "$registration_tool" -f "$app_path" || return $?
    pluginkit -a "$extension_path" || return $?
}

# 返回实际启用状态；查询失败必须传给调用方，不能当作未启用。
ecmenu_extension_state() {
    local identifier="$1"
    local registration

    registration="$(ecmenu_extension_registration "$identifier")" || return $?
    if rg -q '^[+!]' <<<"$registration"; then
        print enabled
    elif rg -q '^[[:space:]]*Path = ' <<<"$registration"; then
        print disabled
    else
        print unregistered
    fi
}

ecmenu_set_extension_state() {
    local identifier="$1"
    local expected="$2"
    local current
    local election

    case "$expected" in
        enabled) election=use ;;
        disabled|unregistered) election=ignore ;;
        *) print -u2 "Invalid Finder Extension state: $expected"; return 64 ;;
    esac
    current="$(ecmenu_extension_state "$identifier")" || return $?
    [[ "$current" == "$expected" ]] && return 0
    if [[ "$current" == unregistered ]]; then
        [[ "$expected" != enabled ]] && return 0
        print -u2 "Cannot enable an unregistered Finder Extension: $identifier"
        return 1
    fi

    pluginkit -e "$election" -i "$identifier" || return $?
    current="$(ecmenu_extension_state "$identifier")" || return $?
    if [[ "$expected" == enabled ]]; then
        [[ "$current" == enabled ]]
    else
        [[ "$current" != enabled ]]
    fi
}

# 先停用原本未启用的身份，再恢复原本启用的身份。
ecmenu_restore_extension_states() {
    local first_identifier="$1"
    local first_state="$2"
    local second_identifier="$3"
    local second_state="$4"
    local restore_status=0

    if [[ "$first_state" != enabled ]]; then
        ecmenu_set_extension_state "$first_identifier" "$first_state" || restore_status=1
    fi
    if [[ "$second_state" != enabled ]]; then
        ecmenu_set_extension_state "$second_identifier" "$second_state" || restore_status=1
    fi
    # 停用失败时不能再启用另一个身份，否则可能贡献重复菜单。
    (( restore_status == 0 )) || return "$restore_status"
    if [[ "$first_state" == enabled ]]; then
        ecmenu_set_extension_state "$first_identifier" enabled || restore_status=1
    fi
    if [[ "$second_state" == enabled ]]; then
        ecmenu_set_extension_state "$second_identifier" enabled || restore_status=1
    fi
    return "$restore_status"
}
