/// 跨配置、传输和两个进程稳定标识一个右键命令。
nonisolated struct ContextCommandFeatureID: Codable, Hashable, Sendable {
    /// 持久化和跨进程协议使用的稳定字符串。
    let rawValue: String

    /// 创建一个跨版本保持不变的命令标识。
    /// - Parameter rawValue: 持久化与跨进程协议共用的字符串。
    init(rawValue: String) {
        precondition(!rawValue.isEmpty)

        self.rawValue = rawValue
    }
}

/// 描述主应用界面和 Finder 菜单共同认识的命令身份。
nonisolated struct ContextCommandDescriptor: Equatable, Sendable {
    /// 持久化菜单可见性使用的稳定命令标识。
    let id: ContextCommandFeatureID

    /// Finder 菜单和主应用状态页共用的产品名称。
    let title: String

    /// Finder 菜单使用的固定图标声明。
    let icon: ContextCommandIcon

    /// 命令依赖的外部应用；不依赖外部应用时为 `nil`。
    let requiredApplication: ContextCommandApplicationRequirement?

    /// 创建一个共享命令身份。
    /// - Parameters:
    ///   - id: 跨版本保持不变的字符串标识。
    ///   - title: 两个界面共用的产品名称。
    ///   - icon: Finder 菜单使用的图标来源。
    ///   - requiredApplication: 命令依赖的固定外部应用。
    init(
        id: String,
        title: String,
        icon: ContextCommandIcon,
        requiredApplication: ContextCommandApplicationRequirement? = nil
    ) {
        precondition(!title.isEmpty)
        switch icon {
        case .systemSymbol(let name):
            precondition(!name.isEmpty)
        case .requiredApplication:
            precondition(requiredApplication != nil)
        }

        self.id = ContextCommandFeatureID(rawValue: id)
        self.title = title
        self.icon = icon
        self.requiredApplication = requiredApplication
    }
}

/// 声明 Finder 菜单图标的系统来源，不让共享契约依赖 AppKit 对象。
nonisolated enum ContextCommandIcon: Equatable, Sendable {
    /// 使用指定名称的 SF Symbol，并由 Finder 渲染器适配系统外观。
    case systemSymbol(name: String)

    /// 使用 `requiredApplication` 指向的软件图标；读取失败时由呈现端降级。
    case requiredApplication
}

/// 描述一个右键命令依赖的固定 macOS 应用。
nonisolated struct ContextCommandApplicationRequirement: Equatable, Sendable {
    /// Launch Services 用于查找应用的稳定 bundle identifier。
    let bundleIdentifier: String

    /// 状态页和错误反馈使用的产品名称。
    let displayName: String

    /// 创建一个由共享命令声明的外部应用依赖。
    init(bundleIdentifier: String, displayName: String) {
        precondition(!bundleIdentifier.isEmpty)
        precondition(!displayName.isEmpty)

        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
    }
}

/// 一个可以通过通用命令信封跨进程传输的功能参数。
nonisolated protocol ContextCommandPayload: Codable, Sendable {
    /// 该命令类型唯一拥有的稳定身份与产品名称。
    static var descriptor: ContextCommandDescriptor { get }
}
