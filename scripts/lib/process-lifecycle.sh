#!/bin/zsh

# 按精确可执行路径管理项目进程，避免按显示名误伤其他安装版本。

process_ids_for_executable() {
    local executable_path="$1"
    local command_path
    local pid

    while read -r pid command_path; do
        if [[ "$command_path" == "$executable_path" ]]; then
            print "$pid"
        fi
    done < <(ps -axo pid=,comm= 2>/dev/null)
}

terminate_process_ids() {
    local process_ids="$1"
    local pid

    if [[ -z "$process_ids" ]]; then
        return 0
    fi

    for pid in "${(@f)process_ids}"; do
        kill "$pid" 2>/dev/null || true
    done
}

restart_gui_launch_service() {
    local service_label="$1"
    local user_id

    user_id="$(/usr/bin/id -u)" || return $?
    # 直接启动 launchd service，不向应用发送 open/reopen 事件。
    /bin/launchctl kickstart -k "gui/$user_id/$service_label"
}

wait_for_process() {
    local executable_path="$1"
    local maximum_attempts="${2:-30}"
    local attempt

    for (( attempt = 1; attempt <= maximum_attempts; attempt++ )); do
        if [[ -n "$(process_ids_for_executable "$executable_path")" ]]; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

wait_for_process_ids_to_exit() {
    local process_ids="$1"
    local maximum_attempts="${2:-50}"
    local all_exited
    local attempt
    local pid

    if [[ -z "$process_ids" ]]; then
        return 0
    fi

    for (( attempt = 1; attempt <= maximum_attempts; attempt++ )); do
        all_exited=true
        for pid in "${(@f)process_ids}"; do
            if kill -0 "$pid" 2>/dev/null; then
                all_exited=false
                break
            fi
        done
        if $all_exited; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}
