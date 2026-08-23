import AppKit
import FinderSync
import SwiftUI

/// 状态页左侧导航可以选择的产品设置分类。
enum StatusPagePane: String, CaseIterable, Identifiable {
    /// 软件总开关与系统权限入口。
    case general

    /// 每一项 Finder 右键命令的显示配置。
    case contextMenu

    /// SwiftUI 列表使用的稳定身份。
    var id: Self { self }

    /// 面向用户显示的分类名称。
    var title: String {
        switch self {
        case .general:
            "通用"
        case .contextMenu:
            "右键菜单"
        }
    }

    /// 左侧导航使用的 SF Symbol。
    var systemImageName: String {
        switch self {
        case .general:
            "gearshape"
        case .contextMenu:
            "contextualmenu.and.cursorarrow"
        }
    }
}

/// 读取系统与应用状态，并把确定的呈现值交给状态页内容。
struct StatusPage: View {
    /// 主应用注入的菜单配置真相源。
    @EnvironmentObject private var menuConfiguration: MenuConfigurationController

    /// 主应用注入的登录项系统状态真相源。
    @EnvironmentObject private var loginItemController: LoginItemController

    /// 上一次查看的设置分类；首次打开时进入“通用”。
    @AppStorage("status-page-selected-pane")
    private var selectedPaneRawValue = StatusPagePane.general.rawValue

    /// 系统当前报告的 Finder Extension 启用状态。
    @State private var isExtensionEnabled = FIFinderSyncController.isExtensionEnabled

    /// Launch Services 当前能够定位的外部应用 bundle identifier。
    @State private var availableApplicationIdentifiers: Set<String> = []

    /// 已安装外部应用的图标，由系统边界读取后交给纯呈现层。
    @State private var applicationIcons: [String: NSImage] = [:]

    /// 把持久化字符串转换为页面使用的有限分类。
    private var selectedPane: Binding<StatusPagePane> {
        Binding(
            get: {
                StatusPagePane(rawValue: selectedPaneRawValue) ?? .general
            },
            set: { pane in
                selectedPaneRawValue = pane.rawValue
            }
        )
    }

    /// 把产品状态和副作用回调注入纯呈现内容。
    var body: some View {
        StatusPageContent(
            displayName: ApplicationMetadata.displayName,
            version: ApplicationMetadata.version,
            selectedPane: selectedPane,
            isExtensionEnabled: isExtensionEnabled,
            loginItemState: loginItemController.state,
            descriptors: ExecutionComposition.handlers.descriptors,
            configuration: menuConfiguration.configuration,
            availableApplicationIdentifiers: availableApplicationIdentifiers,
            applicationIcons: applicationIcons,
            setEnabled: { isEnabled in
                menuConfiguration.setEnabled(isEnabled)
            },
            setLoginItemRequested: { isRequested in
                if !loginItemController.setRequested(isRequested) {
                    NSSound.beep()
                }
            },
            manageExtension: {
                FIFinderSyncController.showExtensionManagementInterface()
            },
            setVisibility: { isVisible, featureID in
                menuConfiguration.setVisible(isVisible, for: featureID)
            },
            openFullDiskAccessSettings: {
                if !FullDiskAccessSettings.open() {
                    NSSound.beep()
                }
            }
        )
        .onAppear {
            refreshSystemState()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            refreshSystemState()
        }
    }

    // MARK: - ==================== 副作用：刷新系统状态 ====================

    /// 在页面出现或应用重新激活时刷新全部外部系统事实。
    private func refreshSystemState() {
        isExtensionEnabled = FIFinderSyncController.isExtensionEnabled
        loginItemController.refresh()
        refreshExternalApplications()
    }

    /// 重新读取所有命令声明的外部应用可用状态与图标。
    private func refreshExternalApplications() {
        var identifiers: Set<String> = []
        var icons: [String: NSImage] = [:]

        for descriptor in ExecutionComposition.handlers.descriptors {
            guard
                let application = descriptor.requiredApplication,
                let applicationURL = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: application.bundleIdentifier
                )
            else {
                continue
            }

            identifiers.insert(application.bundleIdentifier)
            icons[application.bundleIdentifier] = NSWorkspace.shared.icon(
                forFile: applicationURL.path
            )
        }

        availableApplicationIdentifiers = identifiers
        applicationIcons = icons
    }
}

/// 集中保存跨区域复用、会共同影响状态页风格的关键参数。
enum StatusPageStyle {
    /// 左侧导航栏的固定宽度。
    static let sidebarWidth: CGFloat = 180

    /// 右侧设置内容的固定宽度。
    static let detailWidth: CGFloat = 480

    /// 整个页面的固定高度。
    static let pageHeight: CGFloat = 400

    /// 页面主要内容区共用的外边距。
    static let contentPadding: CGFloat = 24

    /// 两组设置之间的垂直间距。
    static let sectionSpacing: CGFloat = 16

    /// 设置行的最小高度。
    static let rowHeight: CGFloat = 36

    /// 行内图标、标题和尾部控件共用的间距。
    static let rowSpacing: CGFloat = 8

    /// 所有设置图标共用的正方形画布边长。
    static let iconCanvasLength: CGFloat = 20

    /// 所有设置 SF Symbol 共用的光学字号。
    static let iconSymbolPointSize: CGFloat = 16

    /// 设置行内容与容器左右边缘之间的空白。
    static let rowHorizontalPadding: CGFloat = 8

    /// 状态页顶部产品图标的正方形槽位边长。
    static let appIconFrameSize: CGFloat = 50
}

/// 把状态页图标渲染到统一设置界面画布。
///
/// 所有设置图标共用 `StatusPageStyle` 的字号和画布，以及 Finder
/// 菜单已验证的自然尺寸、语义居中和越界裁切算法。
enum StatusPageIconRenderer {
    /// 状态页导航、设置行与命令预览共用的画布尺寸。
    static let canvasSize = NSSize(
        width: StatusPageStyle.iconCanvasLength,
        height: StatusPageStyle.iconCanvasLength
    )

    /// 渲染一个可跟随 SwiftUI 前景色的单色设置图标。
    /// - Parameter name: SF Symbols 中的稳定符号名称。
    /// - Returns: 语义居中的 template 图像；系统不支持该符号时为 `nil`。
    static func monochromeSystemSymbol(named name: String) -> NSImage? {
        systemSymbol(
            named: name,
            renderingConfiguration: .preferringMonochrome()
        )
    }

    /// 渲染一个使用系统层级明度的分层设置图标。
    /// - Parameters:
    ///   - name: SF Symbols 中的稳定符号名称。
    ///   - hierarchicalColor: 分层渲染使用的基础系统颜色。
    /// - Returns: 保持自然尺寸的方形图像；系统不支持该符号时为 `nil`。
    static func hierarchicalSystemSymbol(
        named name: String,
        hierarchicalColor: NSColor = .labelColor
    ) -> NSImage? {
        systemSymbol(
            named: name,
            renderingConfiguration: NSImage.SymbolConfiguration(
                hierarchicalColor: hierarchicalColor
            )
        )
    }

    /// 将统一字号、字重和 Symbol 比例与具体颜色模式合并后生成源图。
    /// - Parameters:
    ///   - name: SF Symbols 中的稳定符号名称。
    ///   - renderingConfiguration: 单色或分层颜色配置。
    /// - Returns: 语义主体已烘焙到画布中心的图像。
    private static func systemSymbol(
        named name: String,
        renderingConfiguration: NSImage.SymbolConfiguration
    ) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: StatusPageStyle.iconSymbolPointSize,
            weight: .regular,
            scale: .small
        ).applying(renderingConfiguration)
        guard let sourceIcon = NSImage(
            systemSymbolName: name,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration) else {
            return nil
        }

        return AppKitIconCanvasRenderer.semanticCenteredSymbol(
            sourceIcon,
            canvasSize: canvasSize
        )
    }

    /// 把应用图标保持比例地居中适配到统一设置图标画布。
    /// - Parameter sourceIcon: Launch Services 返回的应用图标。
    /// - Returns: 不放大、不拉伸的方形图像；源尺寸无效时为 `nil`。
    static func applicationIcon(_ sourceIcon: NSImage) -> NSImage? {
        AppKitIconCanvasRenderer.proportionallyFittedImage(
            sourceIcon,
            canvasSize: canvasSize
        )
    }
}

/// 只根据注入的值和用户操作回调呈现主应用状态页。
///
/// 该类型不读取 Finder、Launch Services、偏好存储或分布式通知，
/// 因此产品容器和独立界面预览都可以复用同一呈现实现。
struct StatusPageContent: View {
    /// 页面显示的产品名称。
    let displayName: String

    /// 页面左侧显示的产品版本号。
    let version: String

    /// 当前选中的设置分类。
    @Binding var selectedPane: StatusPagePane

    /// Finder Extension 当前是否已启用。
    let isExtensionEnabled: Bool

    /// 主应用登录项当前的登记和系统批准状态。
    let loginItemState: LoginItemRegistrationState

    /// 按声明顺序显示的所有右键命令。
    let descriptors: [ContextCommandDescriptor]

    /// 当前产品总开关与菜单可见性快照。
    let configuration: MenuConfiguration

    /// Launch Services 当前可定位的外部应用 bundle identifier。
    let availableApplicationIdentifiers: Set<String>

    /// 已安装外部应用的系统图标，以 bundle identifier 索引。
    let applicationIcons: [String: NSImage]

    /// 用户更改产品总开关时的回调。
    let setEnabled: (Bool) -> Void

    /// 用户更改“登录时打开”时的回调。
    let setLoginItemRequested: (Bool) -> Void

    /// 用户请求打开 Finder Extension 管理界面时的回调。
    let manageExtension: () -> Void

    /// 用户更改一项命令可见性时的回调。
    let setVisibility: (Bool, ContextCommandFeatureID) -> Void

    /// 用户请求打开完全磁盘访问设置时的回调。
    let openFullDiskAccessSettings: () -> Void

    /// 构造不含外部读写的双栏设置界面。
    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            detail
                .frame(width: StatusPageStyle.detailWidth, height: StatusPageStyle.pageHeight)
        }
        .frame(height: StatusPageStyle.pageHeight)
    }

    /// 显示产品身份与两个设置分类的窄侧栏。
    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(spacing: StatusPageStyle.rowSpacing) {
                Image("SettingsAppIcon")
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(
                        width: StatusPageStyle.appIconFrameSize,
                        height: StatusPageStyle.appIconFrameSize
                    )
                    .accessibilityLabel(displayName)

                Text("V\(version)")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, StatusPageStyle.contentPadding)

            List(StatusPagePane.allCases, selection: $selectedPane) { pane in
                HStack(spacing: StatusPageStyle.rowSpacing) {
                    monochromeSystemIcon(pane.systemImageName)

                    Text(pane.title)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .tag(pane)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if selectedPane != pane {
                                selectedPane = pane
                            }
                        }
                )
            }
            .listStyle(.sidebar)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .frame(width: StatusPageStyle.sidebarWidth, height: StatusPageStyle.pageHeight)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// 根据侧栏选择显示对应设置内容。
    @ViewBuilder
    private var detail: some View {
        switch selectedPane {
        case .general:
            generalSettings
        case .contextMenu:
            contextMenuSettings
        }
    }

    /// 显示产品总开关与两个必要的系统设置入口。
    private var generalSettings: some View {
        VStack(spacing: StatusPageStyle.sectionSpacing) {
            GroupBox {
                VStack(spacing: 0) {
                    settingRow {
                        settingLabel("启用 \(displayName)") {
                            systemRowIcon("power")
                        }
                        .foregroundStyle(
                            isExtensionEnabled
                                ? Color.primary
                                : Color.secondary
                        )
                    } trailing: {
                        compactToggle(
                            "启用 \(displayName)",
                            isOn: Binding(
                                get: { configuration.isEnabled },
                                set: setEnabled
                            )
                        )
                    }
                    .disabled(!isExtensionEnabled)

                    Divider()

                    settingRow {
                        settingLabel("登录时打开") {
                            systemRowIcon("person")
                        }
                    } trailing: {
                        HStack(spacing: StatusPageStyle.rowSpacing) {
                            if let title = loginItemState.pendingApprovalTitle {
                                Text(title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            compactToggle(
                                "登录时打开",
                                isOn: Binding(
                                    get: { loginItemState.isRequested },
                                    set: setLoginItemRequested
                                )
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            GroupBox {
                VStack(spacing: 0) {
                    settingRow {
                        settingLabel("Finder 扩展") {
                            systemRowIcon("puzzlepiece.extension")
                            .foregroundStyle(
                                isExtensionEnabled ? .green : .secondary
                            )
                        }
                    } trailing: {
                        Button("设置...") {
                            manageExtension()
                        }
                    }

                    Divider()

                    settingRow {
                        settingLabel("完全磁盘访问") {
                            systemRowIcon("folder.badge.person.crop")
                        }
                    } trailing: {
                        Button("设置...") {
                            openFullDiskAccessSettings()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(StatusPageStyle.contentPadding)
    }

    /// 显示每项 Finder 右键命令的图标、外部依赖状态与开关。
    private var contextMenuSettings: some View {
        ScrollView {
            GroupBox {
                VStack(spacing: 0) {
                    ForEach(descriptors, id: \.id) { descriptor in
                        contextMenuRow(for: descriptor)

                        if descriptor.id != descriptors.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(StatusPageStyle.contentPadding)
    }

    /// 构造一项右键命令设置行。
    /// - Parameter descriptor: 当前命令的共享产品声明。
    /// - Returns: 不读取系统状态的设置行。
    private func contextMenuRow(
        for descriptor: ContextCommandDescriptor
    ) -> some View {
        let isDependencyAvailable = descriptor.requiredApplication.map {
            availableApplicationIdentifiers.contains($0.bundleIdentifier)
        } ?? true

        return settingRow {
            settingLabel(descriptor.title) {
                commandIcon(for: descriptor)
            }
            .foregroundStyle(
                isDependencyAvailable ? Color.primary : Color.secondary
            )
        } trailing: {
            HStack(spacing: StatusPageStyle.rowSpacing) {
                if descriptor.requiredApplication != nil {
                    Text(isDependencyAvailable ? "已安装" : "未安装")
                        .font(.caption)
                        .foregroundStyle(
                            isDependencyAvailable ? .green : .secondary
                        )
                }

                compactToggle(
                    "显示\(descriptor.title)",
                    isOn: Binding(
                        get: { configuration.isVisible(descriptor.id) },
                        set: { isVisible in
                            setVisibility(isVisible, descriptor.id)
                        }
                    )
                )
                .disabled(
                    !configuration.isEnabled || !isDependencyAvailable
                )
            }
        }
        .disabled(!isDependencyAvailable)
    }

    /// 使用同一骨架对齐设置标题与尾部控件。
    @ViewBuilder
    private func settingRow<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: StatusPageStyle.rowSpacing) {
            leading()

            Spacer(minLength: StatusPageStyle.rowSpacing)

            trailing()
        }
        .padding(.horizontal, StatusPageStyle.rowHorizontalPadding)
        .frame(maxWidth: .infinity, minHeight: StatusPageStyle.rowHeight)
    }

    /// 使用固定图标槽位构造设置行左侧标签。
    @ViewBuilder
    private func settingLabel<Icon: View>(
        _ title: String,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        HStack(spacing: StatusPageStyle.rowSpacing) {
            icon()
            Text(title)
        }
    }

    /// 构造状态页统一使用的小型开关。
    private func compactToggle(
        _ accessibilityTitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(accessibilityTitle, isOn: isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
    }

    /// 以自然字号把通用页 SF Symbol 居中放入统一槽位。
    private func systemRowIcon(_ name: String) -> some View {
        monochromeSystemIcon(name)
    }

    /// 使用统一字号、画布和语义居中算法构造单色设置图标。
    @ViewBuilder
    private func monochromeSystemIcon(_ name: String) -> some View {
        if let image = StatusPageIconRenderer.monochromeSystemSymbol(
            named: name
        ) {
            Image(nsImage: image)
                .renderingMode(.template)
                .frame(
                    width: StatusPageStyle.iconCanvasLength,
                    height: StatusPageStyle.iconCanvasLength
                )
                .accessibilityHidden(true)
        } else {
            emptyStatusIcon
        }
    }

    /// 把共享图标声明转换为状态页中的图标视图。
    /// - Parameter descriptor: 当前命令声明。
    /// - Returns: SF Symbol、应用图标或应用缺失占位符。
    @ViewBuilder
    private func commandIcon(
        for descriptor: ContextCommandDescriptor
    ) -> some View {
        switch descriptor.icon {
        case .systemSymbol(let name):
            if let image = StatusPageIconRenderer.hierarchicalSystemSymbol(
                named: name
            ) {
                renderedCommandIcon(image)
            } else {
                emptyStatusIcon
            }

        case .requiredApplication:
            if
                let application = descriptor.requiredApplication,
                let sourceImage = applicationIcons[application.bundleIdentifier],
                let image = StatusPageIconRenderer.applicationIcon(
                    sourceImage
                )
            {
                renderedCommandIcon(image)
            } else if let image = StatusPageIconRenderer.hierarchicalSystemSymbol(
                named: "questionmark.app.dashed",
                hierarchicalColor: .secondaryLabelColor
            ) {
                renderedCommandIcon(image)
            } else {
                emptyStatusIcon
            }
        }
    }

    /// 把已按统一设置算法生成的画布原尺寸放入设置行。
    /// - Parameter image: 固定行高画布上的 Symbol 或应用图标。
    /// - Returns: 不再缩放且不单独参与辅助功能语义的图标视图。
    private func renderedCommandIcon(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .frame(
                width: StatusPageStyle.iconCanvasLength,
                height: StatusPageStyle.iconCanvasLength
            )
            .accessibilityHidden(true)
    }

    /// 系统缺失声明符号时仍保留标题的统一起点。
    private var emptyStatusIcon: some View {
        Color.clear
            .frame(
                width: StatusPageStyle.iconCanvasLength,
                height: StatusPageStyle.iconCanvasLength
            )
            .accessibilityHidden(true)
    }
}
