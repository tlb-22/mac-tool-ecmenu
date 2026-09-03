import Foundation

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

    /// 跨进程 wire 保持的稳定字段名。
    private enum CodingKeys: String, CodingKey {
        case rawValue
    }

    /// 解码时重新验证非空约束，避免 wire 绕过领域构造边界。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawValue = try container.decode(String.self, forKey: .rawValue)
        guard !rawValue.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .rawValue,
                in: container,
                debugDescription: "A context-command feature ID cannot be empty"
            )
        }
        self.rawValue = rawValue
    }

    /// 编码为既有 keyed wire 形状。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawValue, forKey: .rawValue)
    }
}

/// 描述主应用界面和 Finder 菜单共同认识的命令身份。
nonisolated struct ContextCommandDescriptor: Equatable, Sendable {
    /// 持久化菜单可见性使用的稳定命令标识。
    let id: ContextCommandFeatureID

    /// Finder 菜单和主应用状态页共用的本地化产品名称。
    let title: LocalizedStringResource

    /// Finder 菜单使用的固定图标声明。
    let icon: ContextCommandIcon

    /// 命令依赖的外部应用；该事实直接由图标声明携带。
    var requiredApplication: ContextCommandApplicationRequirement? {
        icon.applicationRequirement
    }

    /// 创建一个共享命令身份。
    /// - Parameters:
    ///   - id: 跨版本保持不变的字符串标识。
    ///   - title: 两个界面共用的产品名称。
    ///   - icon: Finder 菜单使用的图标来源。
    init(
        id: String,
        title: LocalizedStringResource,
        icon: ContextCommandIcon
    ) {
        precondition(!title.key.isEmpty)
        switch icon {
        case .systemSymbol(let name):
            precondition(!name.isEmpty)
        case .application:
            break
        }

        self.id = ContextCommandFeatureID(rawValue: id)
        self.title = title
        self.icon = icon
    }
}

/// 声明 Finder 菜单图标的系统来源，不让共享契约依赖 AppKit 对象。
nonisolated enum ContextCommandIcon: Equatable, Sendable {
    /// 使用指定名称的 SF Symbol，并由 Finder 渲染器适配系统外观。
    case systemSymbol(name: String)

    /// 使用关联应用的软件图标；读取失败时由呈现端降级。
    case application(ContextCommandApplicationRequirement)

    /// 应用图标同时携带的运行依赖；系统符号没有应用依赖。
    var applicationRequirement: ContextCommandApplicationRequirement? {
        guard case .application(let requirement) = self else {
            return nil
        }
        return requirement
    }
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
