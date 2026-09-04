#!/bin/zsh

# Re-executes the outermost GUI automation script through the focus guard.
ecmenu_reexec_preserving_user_focus() {
    local script_path="$1"
    shift

    [[ -n "${ECMENU_USER_FOCUS_SESSION:-}" ]] && return 0
    exec "${script_path:A:h}/lib/with-user-focus-restored.sh" \
        "$script_path" \
        "$@"
}
