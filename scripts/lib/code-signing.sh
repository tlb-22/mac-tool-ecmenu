#!/bin/zsh

ecmenu_code_signing_value() {
    local bundle_path="$1"
    local key="$2"

    codesign -dv "$bundle_path" 2>&1 \
        | sed -n "s/^$key=//p" \
        || true
}

# 产品路径已经由 product-paths.sh 解析；在登记或启用前验证实际签名。
ecmenu_verify_product_signatures() {
    local app_path="$ECMENU_PRODUCT_APP_PATH"
    local extension_path="$ECMENU_PRODUCT_EXTENSION_PATH"
    local app_identifier
    local extension_identifier
    local app_team
    local extension_team

    codesign --verify --strict "$app_path" || return $?
    codesign --verify --strict "$extension_path" || return $?
    app_identifier="$(ecmenu_code_signing_value "$app_path" Identifier)" || return $?
    extension_identifier="$(ecmenu_code_signing_value "$extension_path" Identifier)" || return $?
    app_team="$(ecmenu_code_signing_value "$app_path" TeamIdentifier)" || return $?
    extension_team="$(ecmenu_code_signing_value "$extension_path" TeamIdentifier)" || return $?

    if [[ "$app_identifier" != "$ECMENU_PRODUCT_APPLICATION_BUNDLE_IDENTIFIER" \
        || "$extension_identifier" != "$ECMENU_PRODUCT_EXTENSION_BUNDLE_IDENTIFIER" \
        || -z "$app_team" || "$app_team" == not\ set \
        || "$app_team" != "$extension_team" ]]; then
        print -u2 "Application and Finder Extension signing identities do not match the resolved products."
        return 1
    fi
    print -r -- "$app_team"
}
