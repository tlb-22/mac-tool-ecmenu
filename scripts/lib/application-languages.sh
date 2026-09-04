#!/bin/zsh

# 对单个 application preference domain 的 AppleLanguages 键做精确事务操作。
# 快照只包含该键，不导入或覆盖应用的其他偏好。

ecmenu_snapshot_application_languages() {
    emulate -L zsh
    setopt local_options pipe_fail

    local domain="$1"
    local snapshot_path="$2"
    local domain_plist
    local value_type=""
    local count
    local index
    local value

    /usr/bin/plutil -create xml1 "$snapshot_path" || return $?
    if ! domain_plist="$(
        /usr/bin/defaults export "$domain" - 2>/dev/null
    )"; then
        /bin/rm -f "$snapshot_path"
        return 1
    fi
    value_type="$(
        print -rn -- "$domain_plist" \
            | /usr/bin/plutil -type AppleLanguages -- - \
                2>/dev/null || true
    )"

    case "$value_type" in
        "")
            /usr/bin/plutil \
                -insert present -bool false \
                "$snapshot_path" || return $?
            ;;
        array)
            /usr/bin/plutil \
                -insert present -bool true \
                "$snapshot_path" || return $?
            /usr/bin/plutil \
                -insert languages -array \
                "$snapshot_path" || return $?
            count="$(
                print -rn -- "$domain_plist" \
                    | /usr/bin/plutil \
                        -extract AppleLanguages raw -expect array -o - -- -
            )" || return $?
            for (( index = 0; index < count; index++ )); do
                value="$(
                    print -rn -- "$domain_plist" \
                        | /usr/bin/plutil \
                            -extract "AppleLanguages.$index" raw \
                            -expect string -o - -- -
                )" || return $?
                /usr/bin/plutil \
                    -insert languages -string "$value" -append \
                    "$snapshot_path" || return $?
            done
            ;;
        *)
            print -u2 \
                "AppleLanguages is not an array in preference domain: $domain"
            /bin/rm -f "$snapshot_path"
            return 65
            ;;
    esac
}

ecmenu_set_application_language() {
    emulate -L zsh
    setopt local_options pipe_fail

    local domain="$1"
    local language="$2"
    local actual_type
    local actual_language

    /usr/bin/defaults write "$domain" AppleLanguages -array "$language" \
        || return $?
    actual_type="$(
        /usr/bin/defaults read-type "$domain" AppleLanguages 2>/dev/null
    )" || return $?
    actual_language="$(
        /usr/bin/defaults read "$domain" AppleLanguages \
            | /usr/bin/plutil \
                -extract 0 raw -expect string -o - -- -
    )" || return $?
    if /usr/bin/defaults read "$domain" AppleLanguages \
        | /usr/bin/plutil -extract 1 raw -o - -- - \
            >/dev/null 2>&1; then
        return 1
    fi

    [[ "$actual_type" == "Type is array" \
        && "$actual_language" == "$language" ]]
}

ecmenu_restore_application_languages() {
    emulate -L zsh

    local domain="$1"
    local snapshot_path="$2"
    local present
    local count
    local index
    local value
    local -a languages=()

    present="$(
        /usr/bin/plutil \
            -extract present raw -expect bool -o - \
            "$snapshot_path"
    )" || return $?

    if [[ "$present" == false ]]; then
        /usr/bin/defaults delete "$domain" AppleLanguages \
            >/dev/null 2>&1 || true
        ecmenu_application_languages_match_snapshot \
            "$domain" \
            "$snapshot_path"
        return $?
    fi

    count="$(
        /usr/bin/plutil \
            -extract languages raw -expect array -o - \
            "$snapshot_path"
    )" || return $?
    for (( index = 0; index < count; index++ )); do
        value="$(
            /usr/bin/plutil \
                -extract "languages.$index" raw -expect string -o - \
                "$snapshot_path"
        )" || return $?
        languages+=("$value")
    done

    /usr/bin/defaults write "$domain" AppleLanguages -array "${languages[@]}" \
        || return $?
    ecmenu_application_languages_match_snapshot "$domain" "$snapshot_path"
}

ecmenu_application_languages_match_snapshot() {
    emulate -L zsh
    setopt local_options pipe_fail

    local domain="$1"
    local snapshot_path="$2"
    local current_path="${snapshot_path}.current"

    if ! ecmenu_snapshot_application_languages "$domain" "$current_path"; then
        /bin/rm -f "$current_path"
        return 1
    fi
    if /usr/bin/cmp -s "$snapshot_path" "$current_path"; then
        /bin/rm -f "$current_path"
        return 0
    fi
    /bin/rm -f "$current_path"
    return 1
}
