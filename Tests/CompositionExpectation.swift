/// 两个进程的 Composition 必须共同覆盖的产品命令身份测试基线。
nonisolated enum ProductContextCommandExpectation {
    /// 按 Finder 菜单产品顺序排列的稳定 ID。
    static let featureIDs = [
        "new-text-file",
        "copy-path",
        "hide-items",
        "show-items",
        "compress-images",
        "open-in-vscode",
        "open-in-iterm2",
    ]
}
