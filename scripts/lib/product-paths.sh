# Shared product discovery for scripts that consume an existing Xcode build.

ecmenu_plist_value() {
    local plist_path="$1"
    local key="$2"

    /usr/libexec/PlistBuddy \
        -c "Print :$key" \
        "$plist_path" \
        2>/dev/null || true
}

ecmenu_target_build_setting_value() {
    local target_name="$1"
    local setting_name="$2"

    awk -v target_name="$target_name" -v setting_name="$setting_name" '
        /^Build settings for action .* and target / {
            in_target = ($0 == "Build settings for action build and target " target_name ":")
            next
        }
        in_target && $0 ~ "^[[:space:]]*" setting_name " = " {
            sub("^[[:space:]]*" setting_name " = ", "")
            print
            exit
        }
    '
}

ecmenu_resolve_product_paths() {
    emulate -L zsh
    setopt local_options null_glob

    local products_directory="$1"
    local expected_app_wrapper_name="${2:-}"
    local app_info_path
    local candidate_app_path
    local candidate_bundle_id
    local candidate_configured_app_id
    local candidate_configured_extension_id
    local candidate_group_id
    local extension_info_path
    local candidate_extension_path
    local extension_bundle_id
    local extension_configured_app_id
    local extension_configured_extension_id
    local extension_group_id
    local main_executable_name
    local extension_executable_name
    local candidate_path
    local -a app_candidates=()
    local -a extension_candidates=()

    if [[ ! -d "$products_directory" ]]; then
        print -u2 "Built products directory does not exist: $products_directory"
        return 65
    fi

    local -a app_info_paths=()
    if [[ -n "$expected_app_wrapper_name" ]]; then
        if [[ "$expected_app_wrapper_name" != "${expected_app_wrapper_name:t}" \
            || "$expected_app_wrapper_name" != *.app ]]; then
            print -u2 \
                "Invalid application FULL_PRODUCT_NAME: $expected_app_wrapper_name"
            return 66
        fi
        app_info_paths+=(
            "$products_directory/$expected_app_wrapper_name/Contents/Info.plist"
        )
    else
        app_info_paths=(
            "$products_directory"/*.app/Contents/Info.plist(N)
        )
    fi

    for app_info_path in "${app_info_paths[@]}"; do
        [[ -f "$app_info_path" ]] || continue
        candidate_app_path="${app_info_path:h:h}"
        candidate_bundle_id="$(
            ecmenu_plist_value "$app_info_path" CFBundleIdentifier
        )"
        candidate_configured_app_id="$(
            ecmenu_plist_value \
                "$app_info_path" \
                ECMApplicationSigningIdentifier
        )"
        candidate_configured_extension_id="$(
            ecmenu_plist_value \
                "$app_info_path" \
                ECMFinderExtensionSigningIdentifier
        )"
        candidate_group_id="$(
            ecmenu_plist_value "$app_info_path" ECMApplicationGroupIdentifier
        )"

        if [[ -n "$candidate_bundle_id" \
            && "$candidate_configured_app_id" == "$candidate_bundle_id" \
            && -n "$candidate_configured_extension_id" \
            && "$candidate_configured_extension_id" != "$candidate_bundle_id" \
            && -n "$candidate_group_id" ]]; then
            app_candidates+=("$candidate_app_path")
        fi
    done

    if (( ${#app_candidates[@]} != 1 )); then
        print -u2 \
            "Expected one built ECMenu application in $products_directory; found ${#app_candidates[@]}."
        for candidate_path in "${app_candidates[@]}"; do
            print -u2 "  $candidate_path"
        done
        return 66
    fi

    candidate_app_path="$app_candidates[1]"
    app_info_path="$candidate_app_path/Contents/Info.plist"
    candidate_bundle_id="$(
        ecmenu_plist_value "$app_info_path" CFBundleIdentifier
    )"
    candidate_configured_extension_id="$(
        ecmenu_plist_value \
            "$app_info_path" \
            ECMFinderExtensionSigningIdentifier
    )"
    candidate_group_id="$(
        ecmenu_plist_value "$app_info_path" ECMApplicationGroupIdentifier
    )"

    for extension_info_path in \
        "$candidate_app_path"/Contents/PlugIns/*.appex/Contents/Info.plist(N); do
        candidate_extension_path="${extension_info_path:h:h}"
        extension_bundle_id="$(
            ecmenu_plist_value "$extension_info_path" CFBundleIdentifier
        )"
        extension_configured_app_id="$(
            ecmenu_plist_value \
                "$extension_info_path" \
                ECMApplicationSigningIdentifier
        )"
        extension_configured_extension_id="$(
            ecmenu_plist_value \
                "$extension_info_path" \
                ECMFinderExtensionSigningIdentifier
        )"
        extension_group_id="$(
            ecmenu_plist_value \
                "$extension_info_path" \
                ECMApplicationGroupIdentifier
        )"

        if [[ "$extension_bundle_id" == "$candidate_configured_extension_id" \
            && "$extension_configured_app_id" == "$candidate_bundle_id" \
            && "$extension_configured_extension_id" == "$extension_bundle_id" \
            && "$extension_group_id" == "$candidate_group_id" ]]; then
            extension_candidates+=("$candidate_extension_path")
        fi
    done

    if (( ${#extension_candidates[@]} != 1 )); then
        print -u2 \
            "Expected one matching Finder Extension in $candidate_app_path; found ${#extension_candidates[@]}."
        for candidate_path in "${extension_candidates[@]}"; do
            print -u2 "  $candidate_path"
        done
        return 67
    fi

    candidate_extension_path="$extension_candidates[1]"
    extension_info_path="$candidate_extension_path/Contents/Info.plist"
    extension_bundle_id="$(
        ecmenu_plist_value "$extension_info_path" CFBundleIdentifier
    )"
    main_executable_name="$(
        ecmenu_plist_value "$app_info_path" CFBundleExecutable
    )"
    extension_executable_name="$(
        ecmenu_plist_value "$extension_info_path" CFBundleExecutable
    )"

    if [[ -z "$main_executable_name" \
        || "$main_executable_name" != "${main_executable_name:t}" \
        || -z "$extension_executable_name" \
        || "$extension_executable_name" != "${extension_executable_name:t}" ]]; then
        print -u2 "A built ECMenu product has an invalid CFBundleExecutable."
        return 68
    fi

    typeset -g ECMENU_PRODUCT_APP_PATH="$candidate_app_path"
    typeset -g ECMENU_PRODUCT_EXTENSION_PATH="$candidate_extension_path"
    typeset -g ECMENU_PRODUCT_MAIN_EXECUTABLE_PATH="${candidate_app_path}/Contents/MacOS/${main_executable_name}"
    typeset -g ECMENU_PRODUCT_EXTENSION_EXECUTABLE_PATH="${candidate_extension_path}/Contents/MacOS/${extension_executable_name}"
    typeset -g ECMENU_PRODUCT_APPLICATION_BUNDLE_IDENTIFIER="$candidate_bundle_id"
    typeset -g ECMENU_PRODUCT_EXTENSION_BUNDLE_IDENTIFIER="$extension_bundle_id"
    typeset -g ECMENU_PRODUCT_APPLICATION_GROUP_IDENTIFIER="$candidate_group_id"

    if [[ ! -x "$ECMENU_PRODUCT_MAIN_EXECUTABLE_PATH" \
        || ! -x "$ECMENU_PRODUCT_EXTENSION_EXECUTABLE_PATH" ]]; then
        print -u2 "A built ECMenu product executable is missing or not executable."
        return 69
    fi
}
