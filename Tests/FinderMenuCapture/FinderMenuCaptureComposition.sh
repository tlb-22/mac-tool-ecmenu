#!/bin/zsh

# Finder 菜单截图场景的唯一注册表。fixture 与命令期望分别留在所属上下文和 Feature 中。

typeset -gr _finder_menu_capture_definition_directory="${${(%):-%x}:A:h}"

source \
    "$_finder_menu_capture_definition_directory/Contexts/BasicContextScenarios.sh"
source \
    "$_finder_menu_capture_definition_directory/Features/ImageCompression/ImageCompressionCaptureScenario.sh"
source \
    "$_finder_menu_capture_definition_directory/Features/CopyPath/CopyPathCaptureExpectations.sh"
source \
    "$_finder_menu_capture_definition_directory/Features/NewTextFile/NewTextFileCaptureExpectations.sh"
source \
    "$_finder_menu_capture_definition_directory/Features/Visibility/VisibilityCaptureExpectations.sh"

typeset -gra _finder_menu_capture_scenario_providers=(
    finder_menu_capture_basic_context
    finder_menu_capture_image_compression
)

typeset -gra _finder_menu_capture_expectation_providers=(
    finder_menu_capture_new_text_file
    finder_menu_capture_copy_path
    finder_menu_capture_visibility
    finder_menu_capture_image_compression
)

# 每行输出一个稳定场景 ID，顺序即批量截图顺序。
finder_menu_capture_scenario_ids() {
    local provider

    for provider in "${_finder_menu_capture_scenario_providers[@]}"; do
        "${provider}_scenario_ids" || return $?
    done
}

# 在传入的尚不存在目录中创建场景 fixture。
finder_menu_capture_create_fixture() {
    local scenario_id="$1"
    local fixture_directory="$2"
    local provider

    provider="$(_finder_menu_capture_provider_for "$scenario_id")" \
        || return $?
    "${provider}_create_fixture" "$scenario_id" "$fixture_directory"
}

# 输出 `container` 或 `items`。
finder_menu_capture_context_kind() {
    local scenario_id="$1"
    local provider

    provider="$(_finder_menu_capture_provider_for "$scenario_id")" \
        || return $?
    "${provider}_context_kind" "$scenario_id"
}

# 每行输出一个需要在 Finder 中选择的 fixture basename；container 不输出。
finder_menu_capture_selected_basenames() {
    local scenario_id="$1"
    local provider

    provider="$(_finder_menu_capture_provider_for "$scenario_id")" \
        || return $?
    "${provider}_selected_basenames" "$scenario_id"
}

# 每行输出一个必须出现在菜单中的 Localizable.xcstrings command key。
finder_menu_capture_required_command_keys() {
    local scenario_id="$1"
    local provider

    _finder_menu_capture_provider_for "$scenario_id" >/dev/null \
        || return $?

    for provider in "${_finder_menu_capture_expectation_providers[@]}"; do
        "${provider}_required_command_keys" "$scenario_id" || return $?
    done
}

# 把稳定 ID 定向到唯一提供者；重复注册属于场景定义错误。
_finder_menu_capture_provider_for() {
    local scenario_id="$1"
    local provider
    local provider_scenario_ids
    local registered_id
    local matched_provider=""

    for provider in "${_finder_menu_capture_scenario_providers[@]}"; do
        if provider_scenario_ids="$("${provider}_scenario_ids")"; then
            :
        else
            return $?
        fi
        if [[ -n "$provider_scenario_ids" ]]; then
            for registered_id in "${(@f)provider_scenario_ids}"; do
                if [[ "$registered_id" == "$scenario_id" ]]; then
                    if [[ -n "$matched_provider" ]]; then
                        print -u2 -r -- \
                            "Finder menu capture scenario is registered twice: $scenario_id"
                        return 70
                    fi
                    matched_provider="$provider"
                fi
            done
        fi
    done

    if [[ -z "$matched_provider" ]]; then
        print -u2 -r -- \
            "Unknown Finder menu capture scenario: $scenario_id"
        return 64
    fi
    print -r -- "$matched_provider"
}
