import AppKit
import XCTest
@testable import ECMenuFinderExtension

/// 验证 Finder 声明树覆盖完整产品命令集合且保留要求的菜单顺序。
@MainActor
final class ContextMenuCompositionTests: XCTestCase {
    /// Finder Feature 的稳定 ID 应与两端共同测试基线完全一致。
    func testCurrentProductFeatures() {
        let menu = ContextMenuComposition.menu(
            commandClient: ContextCommandClient()
        )
        let featureIDs = menu.nodes
            .flatMap { $0.items }
            .map { $0.descriptor.id.featureID.rawValue }
            .reduce(into: [String]()) { result, featureID in
                if !result.contains(featureID) {
                    result.append(featureID)
                }
            }

        XCTAssertEqual(
            featureIDs,
            ProductContextCommandExpectation.featureIDs
        )
    }

    /// 简单菜单策略应只依赖同一次构建冻结的快照。
    func testSimpleFeaturesUseProvidedSnapshot() throws {
        let client = ContextCommandClient()
        let emptyItems = FinderContextReader.snapshot(
            for: .items,
            targetedURL: URL(fileURLWithPath: "/Users/example"),
            selectedURLs: []
        )
        let selection = try XCTUnwrap(
            FinderItemSelection(paths: ["/Users/example/file.txt"])
        )
        let selectedItem = FinderContextSnapshot.items(selection: selection)
        let evaluationContext = FinderContextMenuEvaluationContext(
            snapshot: selectedItem
        )

        XCTAssertNil(emptyItems)
        XCTAssertNotNil(
            CopyPathFeature(commandClient: client).command(
                in: evaluationContext
            )
        )
        XCTAssertNotNil(
            HideItemsFeature(
                commandClient: client,
                readSelectionFacts: { _ in
                    self.visibilityFacts(isHiddenValues: [false, true])
                }
            ).command(in: evaluationContext)
        )
        XCTAssertEqual(
            ShowItemsFeature(
                commandClient: client,
                readSelectionFacts: { _ in
                    self.visibilityFacts(isHiddenValues: [false, true])
                }
            ).command(in: evaluationContext)?.selection,
            selection
        )
    }

    /// 点号名称和未知状态不应促成任何可见性命令出现。
    func testVisibilityMenuFactsExcludeDotNamesAndUnknownStates() {
        let excludedOnly = VisibilitySelectionMenuFacts(
            items: [
                VisibilityMenuItemFacts(name: ".visible-dot", isHidden: false),
                VisibilityMenuItemFacts(name: ".hidden-dot", isHidden: true),
                VisibilityMenuItemFacts(name: "unknown", isHidden: nil),
            ]
        )

        XCTAssertFalse(excludedOnly.hasVisibleOrdinaryItem)
        XCTAssertFalse(excludedOnly.hasHiddenOrdinaryItem)

        let ordinaryStates = VisibilitySelectionMenuFacts(
            items: [
                VisibilityMenuItemFacts(name: ".ignored", isHidden: false),
                VisibilityMenuItemFacts(name: "visible", isHidden: false),
                VisibilityMenuItemFacts(name: "hidden", isHidden: true),
            ]
        )

        XCTAssertTrue(ordinaryStates.hasVisibleOrdinaryItem)
        XCTAssertTrue(ordinaryStates.hasHiddenOrdinaryItem)
    }

    /// 纯汇总同时确认可见和隐藏对象后应停止消费后续输入。
    func testVisibilityMenuFactsStopAfterBothStatesAreKnown() {
        var evaluatedCount = 0
        let items = [false, true, false].lazy.map { isHidden in
            evaluatedCount += 1
            return VisibilityMenuItemFacts(
                name: "item-\(evaluatedCount)",
                isHidden: isHidden
            )
        }

        let facts = VisibilitySelectionMenuFacts(items: items)

        XCTAssertTrue(facts.hasVisibleOrdinaryItem)
        XCTAssertTrue(facts.hasHiddenOrdinaryItem)
        XCTAssertEqual(evaluatedCount, 2)
    }

    /// 选中项只显示能够改变至少一个普通对象状态的命令。
    func testVisibilityItemsAreFilteredByState() throws {
        let snapshot = FinderContextSnapshot.items(
            selection: try XCTUnwrap(
                FinderItemSelection(paths: ["/Users/example/item"])
            )
        )
        let cases: [(
            facts: VisibilitySelectionMenuFacts,
            expectedTitles: [String]
        )] = [
            (
                facts: visibilityFacts(isHiddenValues: [false]),
                expectedTitles: ["隐藏项目"]
            ),
            (
                facts: visibilityFacts(isHiddenValues: [true]),
                expectedTitles: ["显示项目"]
            ),
            (
                facts: visibilityFacts(isHiddenValues: [false, true]),
                expectedTitles: ["隐藏项目", "显示项目"]
            ),
            (
                facts: visibilityFacts(isHiddenValues: [nil]),
                expectedTitles: []
            ),
        ]

        for testCase in cases {
            let menu = visibilityMenu(
                snapshot: snapshot,
                facts: testCase.facts
            )

            XCTAssertEqual(
                menu?.items.map(\.title) ?? [],
                testCase.expectedTitles
            )
            XCTAssertTrue(menu?.items.allSatisfy(\.isEnabled) ?? true)
            if testCase.expectedTitles.isEmpty {
                XCTAssertNil(menu)
            }
        }
    }

    /// 空白处和侧边栏不显示可见性命令，也不读取选择事实。
    func testVisibilityContainerAndSidebarAreOmitted() {
        let snapshots: [FinderContextSnapshot] = [
            .container(path: absolutePath("/Users/example/folder")),
            .sidebar(path: absolutePath("/Users/example/folder")),
        ]
        var readCount = 0
        let controller = visibilityController(
            readSelectionFacts: { _ in
                readCount += 1
                return self.visibilityFacts(isHiddenValues: [false, true])
            }
        )

        for snapshot in snapshots {
            XCTAssertNil(
                controller.menu(
                    for: snapshot,
                    action: #selector(NSApplication.terminate(_:))
                )
            )
        }
        XCTAssertEqual(readCount, 0)
    }

    /// 隐藏与显示 Action 在一次构建中共享事实，下一次构建重新读取。
    func testVisibilitySelectionFactsAreReadOncePerMenuBuild() throws {
        let selection = try XCTUnwrap(
            FinderItemSelection(paths: ["/Users/example/item"])
        )
        let snapshot = FinderContextSnapshot.items(selection: selection)
        let facts = visibilityFacts(isHiddenValues: [false, true])
        var readCount = 0
        let controller = visibilityController(
            readSelectionFacts: { receivedSelection in
                XCTAssertEqual(receivedSelection, selection)
                readCount += 1
                return facts
            }
        )

        XCTAssertNotNil(
            controller.menu(
                for: snapshot,
                action: #selector(NSApplication.terminate(_:))
            )
        )
        XCTAssertEqual(readCount, 1)

        XCTAssertNotNil(
            controller.menu(
                for: snapshot,
                action: #selector(NSApplication.terminate(_:))
            )
        )
        XCTAssertEqual(readCount, 2)
    }

    /// 两个可见性功能的独立配置开关应只删除对应菜单项。
    func testVisibilityConfigurationFiltersCommandsIndependently() throws {
        let snapshot = FinderContextSnapshot.items(
            selection: try XCTUnwrap(
                FinderItemSelection(paths: ["/Users/example/item"])
            )
        )
        let facts = visibilityFacts(isHiddenValues: [false, true])
        let cases: [(
            hiddenFeatureID: ContextCommandFeatureID,
            expectedTitles: [String]
        )] = [
            (HideItemsCommand.descriptor.id, ["显示项目"]),
            (ShowItemsCommand.descriptor.id, ["隐藏项目"]),
        ]

        for testCase in cases {
            let menu = visibilityMenu(
                snapshot: snapshot,
                facts: facts,
                isFeatureVisible: {
                    $0 != testCase.hiddenFeatureID
                }
            )
            XCTAssertEqual(menu?.items.map(\.title), testCase.expectedTitles)
        }

        let hiddenController = visibilityController(
            readSelectionFacts: { _ in facts },
            isFeatureVisible: { _ in false }
        )
        XCTAssertNil(
            hiddenController.menu(
                for: snapshot,
                action: #selector(NSApplication.terminate(_:))
            )
        )
    }

    /// 产品总开关关闭时不应贡献菜单，也不应读取具体功能事实。
    func testMasterDisableSuppressesEntireMenu() throws {
        let snapshot = FinderContextSnapshot.items(
            selection: try XCTUnwrap(
                FinderItemSelection(paths: ["/Users/example/item"])
            )
        )
        var readCount = 0
        let controller = visibilityController(
            readSelectionFacts: { _ in
                readCount += 1
                return self.visibilityFacts(isHiddenValues: [false])
            },
            isMenuEnabled: { false }
        )

        XCTAssertNil(
            controller.menu(
                for: snapshot,
                action: #selector(NSApplication.terminate(_:))
            )
        )
        XCTAssertEqual(readCount, 0)
    }

    /// 缺失外部应用时应省略命令，应用可用时才生成可执行叶子。
    func testOpenInApplicationCommandsRequireInstalledApplications() throws {
        let directoryPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .path
        let snapshot = FinderContextSnapshot.container(
            path: absolutePath(directoryPath)
        )
        let client = ContextCommandClient()

        let unavailableController = FinderContextMenuController(
            menu: FinderContextMenuDefinition {
                OpenInVSCodeFeature(
                    commandClient: client
                )
                OpenInITerm2Feature(
                    commandClient: client
                )
            },
            isFeatureVisible: { _ in true },
            isApplicationAvailable: { _ in false }
        )
        XCTAssertNil(
            unavailableController.menu(
                for: snapshot,
                action: #selector(NSApplication.terminate(_:))
            )
        )

        let availableController = FinderContextMenuController(
            menu: FinderContextMenuDefinition {
                OpenInVSCodeFeature(
                    commandClient: client
                )
                OpenInITerm2Feature(
                    commandClient: client
                )
            },
            isFeatureVisible: { _ in true },
            isApplicationAvailable: { _ in true }
        )
        let availableMenu = try XCTUnwrap(
            availableController.menu(
                for: snapshot,
                action: #selector(NSApplication.terminate(_:))
            )
        )

        XCTAssertEqual(
            availableMenu.items.map(\.title),
            ["进入 Visual Studio Code", "进入 iTerm2"]
        )
        XCTAssertTrue(availableMenu.items.allSatisfy(\.isEnabled))
    }

    /// Finder 原始字段只在读取边界解释，Feature 只能看到确定语义。
    func testFinderBoundaryBuildsSemanticSnapshots() throws {
        let residualSelection = URL(fileURLWithPath: "/residual-selected-folder")
        let visibleDirectory = URL(fileURLWithPath: "/visible/current")

        XCTAssertEqual(
            FinderContextReader.snapshot(
                for: .container,
                targetedURL: residualSelection,
                selectedURLs: [visibleDirectory]
            ),
            .container(path: absolutePath(visibleDirectory.path))
        )
        XCTAssertEqual(
            FinderContextReader.snapshot(
                for: .sidebar,
                targetedURL: visibleDirectory,
                selectedURLs: [residualSelection]
            ),
            .sidebar(path: absolutePath(visibleDirectory.path))
        )
        XCTAssertNil(
            FinderContextReader.snapshot(
                for: .items,
                targetedURL: visibleDirectory,
                selectedURLs: []
            )
        )
    }

    /// 每个 action 应投递菜单构建时已经准备好的命令。
    func testRenderedActionsKeepMenuBuildSnapshot() throws {
        let snapshot = FinderContextSnapshot.container(
            path: absolutePath("/visible/through-alias/current")
        )
        let transport = RecordingContextCommandTransport()
        let controller = FinderContextMenuController(
            menu: FinderContextMenuDefinition {
                CopyPathFeature(
                    commandClient: ContextCommandClient(transport: transport)
                )
            },
            isFeatureVisible: { _ in true }
        )

        let renderedMenu = try XCTUnwrap(
            controller.menu(
                for: snapshot,
                action: #selector(NSApplication.terminate(_:))
            )
        )
        let menuItem = try XCTUnwrap(renderedMenu.items.first)

        XCTAssertNotNil(controller.preparedAction(for: menuItem))
        controller.perform(menuItem)

        let request = try XCTUnwrap(transport.recordedRequests.first)
        let command = try request.command.decode(as: CopyPathCommand.self)
        XCTAssertEqual(command.paths, snapshot.absolutePaths)
        XCTAssertNil(controller.preparedAction(for: menuItem))
    }

    /// 后续菜单请求不得把旧空白菜单 action 改写为残余选中项语义。
    func testContainerActionSurvivesLaterItemsMenuBuild() throws {
        let containerPath = absolutePath("/clicked-background")
        let containerSnapshot = FinderContextSnapshot.container(
            path: containerPath
        )
        let selection = try XCTUnwrap(
            FinderItemSelection(paths: ["/residual-selected-folder"])
        )
        let itemsSnapshot = FinderContextSnapshot.items(selection: selection)
        let transport = RecordingContextCommandTransport()
        let controller = FinderContextMenuController(
            menu: FinderContextMenuDefinition {
                CopyPathFeature(
                    commandClient: ContextCommandClient(transport: transport)
                )
            },
            isFeatureVisible: { _ in true }
        )

        let containerMenu = try XCTUnwrap(
            controller.menu(
                for: containerSnapshot,
                action: #selector(NSApplication.terminate(_:))
            )
        )
        let containerItem = try XCTUnwrap(
            containerMenu.items.first { $0.title == "拷贝路径" }
        )

        let itemsMenu = try XCTUnwrap(
            controller.menu(
                for: itemsSnapshot,
                action: #selector(NSApplication.terminate(_:))
            )
        )
        let itemsItem = try XCTUnwrap(
            itemsMenu.items.first { $0.title == "拷贝路径" }
        )

        XCTAssertNotEqual(containerItem.tag, itemsItem.tag)
        controller.perform(containerItem)
        controller.perform(itemsItem)

        let commands = try transport.recordedRequests.map {
            try $0.command.decode(as: CopyPathCommand.self)
        }
        XCTAssertEqual(
            commands.map(\.paths),
            [[containerPath], selection.absolutePaths]
        )
    }

    /// 一个 Feature 可以声明递归子菜单，并让同一种 Command 携带不同参数。
    func testFeatureCanContributeParameterizedSubmenuActions() throws {
        let transport = RecordingContextCommandTransport()
        let feature = TestParameterizedFeature(
            commandClient: ContextCommandClient(transport: transport)
        )
        let snapshot = FinderContextSnapshot.container(
            path: absolutePath("/test")
        )
        let context = FinderContextMenuEvaluationContext(snapshot: snapshot)
        let typedActions = feature.nodes.flatMap { $0.items }

        XCTAssertEqual(
            typedActions.compactMap { $0.command(context)?.format },
            [.png, .jpeg]
        )

        let definition = FinderContextMenuDefinition { feature }
        XCTAssertEqual(
            definition.nodes
                .flatMap { $0.items }
                .map { $0.descriptor.id.featureID },
            [
                TestParameterizedCommand.descriptor.id,
                TestParameterizedCommand.descriptor.id,
            ]
        )

        let controller = FinderContextMenuController(
            menu: definition,
            isFeatureVisible: { _ in true }
        )
        let menu = try XCTUnwrap(
            controller.menu(
                for: snapshot,
                action: #selector(NSApplication.terminate(_:))
            )
        )
        let submenu = try XCTUnwrap(menu.items.first?.submenu)
        XCTAssertEqual(submenu.items.map(\.title), ["PNG", "JPEG"])
        XCTAssertEqual(
            submenu.items.compactMap {
                controller.preparedAction(for: $0)?
                    .descriptor.id.localID.rawValue
            },
            ["png", "jpeg"]
        )
        submenu.items.forEach { controller.perform($0) }
        let commands = try transport.recordedRequests.map {
            try $0.command.decode(as: TestParameterizedCommand.self)
        }
        XCTAssertEqual(commands.map(\.format), [.png, .jpeg])
        XCTAssertTrue(
            commands.allSatisfy { $0.targetPath == snapshot.absolutePaths.first }
        )
    }

    /// SF Symbol 应使用菜单行高画布，保持自然尺寸并允许附属图形被边界裁切。
    func testSymbolsUseMenuLineHeightCanvasWithoutScalingToFit() throws {
        let feature = TestParameterizedFeature(
            commandClient: ContextCommandClient()
        )
        let controller = FinderContextMenuController(
            menu: FinderContextMenuDefinition { feature },
            isFeatureVisible: { _ in true }
        )
        let menu = try XCTUnwrap(
            controller.menu(
                for: .container(path: absolutePath("/test")),
                action: #selector(NSApplication.terminate(_:))
            )
        )
        let submenu = try XCTUnwrap(menu.items.first?.submenu)
        let plainItem = try XCTUnwrap(submenu.items.first)
        let badgedItem = try XCTUnwrap(submenu.items.dropFirst().first)
        let plainImage = try XCTUnwrap(plainItem.image)
        let badgedImage = try XCTUnwrap(badgedItem.image)

        let menuFont = NSFont.menuFont(ofSize: 0)
        let canvasLength = ceil(
            menuFont.ascender - menuFont.descender + menuFont.leading
        )
        let canvasSize = NSSize(width: canvasLength, height: canvasLength)
        let canvasRect = NSRect(origin: .zero, size: canvasSize)
        XCTAssertEqual(plainImage.size, canvasSize)
        XCTAssertEqual(badgedImage.size, canvasSize)
        XCTAssertEqual(plainImage.alignmentRect, canvasRect)
        XCTAssertEqual(badgedImage.alignmentRect, canvasRect)
    }

    /// 不可用叶子应在递归布局阶段删除，只有保留叶子进入 action 路由。
    func testUnavailableLeavesAreRemovedBeforeRouting() throws {
        let feature = TestAvailabilityFeature(
            commandClient: ContextCommandClient()
        )
        let snapshot = FinderContextSnapshot.container(
            path: absolutePath("/test")
        )
        let controller = FinderContextMenuController(
            menu: FinderContextMenuDefinition { feature },
            isFeatureVisible: { _ in true }
        )
        let menu = try XCTUnwrap(
            controller.menu(
                for: snapshot,
                action: #selector(NSApplication.terminate(_:))
            )
        )
        let firstLevelMenu = try XCTUnwrap(menu.items.first?.submenu)
        XCTAssertEqual(firstLevelMenu.items.map(\.title), ["第二层"])
        let secondLevelMenu = try XCTUnwrap(firstLevelMenu.items.first?.submenu)
        let enabledItem = try XCTUnwrap(secondLevelMenu.items.first)

        XCTAssertFalse(menu.autoenablesItems)
        XCTAssertFalse(firstLevelMenu.autoenablesItems)
        XCTAssertFalse(secondLevelMenu.autoenablesItems)
        XCTAssertTrue(enabledItem.isEnabled)
        XCTAssertNotNil(enabledItem.action)
        XCTAssertEqual(enabledItem.tag, 1)
        XCTAssertEqual(
            controller.preparedAction(for: enabledItem)?
                .descriptor.id.localID.rawValue,
            "enabled"
        )
    }

    /// 构造只含两个可见性功能的真实 AppKit 菜单。
    private func visibilityMenu(
        snapshot: FinderContextSnapshot,
        facts: VisibilitySelectionMenuFacts,
        isFeatureVisible: @escaping (
            ContextCommandFeatureID
        ) -> Bool = { _ in true }
    ) -> NSMenu? {
        let controller = visibilityController(
            readSelectionFacts: { _ in facts },
            isFeatureVisible: isFeatureVisible
        )

        return controller.menu(
            for: snapshot,
            action: #selector(NSApplication.terminate(_:))
        )
    }

    /// 使用纯事实读取和纯配置查询构造可见性菜单运行时。
    private func visibilityController(
        readSelectionFacts: @escaping (
            FinderItemSelection
        ) -> VisibilitySelectionMenuFacts,
        isFeatureVisible: @escaping (
            ContextCommandFeatureID
        ) -> Bool = { _ in true },
        isMenuEnabled: @escaping () -> Bool = { true }
    ) -> FinderContextMenuController {
        let client = ContextCommandClient()
        let definition = FinderContextMenuDefinition {
            HideItemsFeature(
                commandClient: client,
                readSelectionFacts: readSelectionFacts
            )
            ShowItemsFeature(
                commandClient: client,
                readSelectionFacts: readSelectionFacts
            )
        }
        return FinderContextMenuController(
            menu: definition,
            isFeatureVisible: isFeatureVisible,
            isMenuEnabled: isMenuEnabled
        )
    }

    /// 使用普通文件名构造指定隐藏状态的纯菜单事实。
    private func visibilityFacts(
        isHiddenValues: [Bool?]
    ) -> VisibilitySelectionMenuFacts {
        VisibilitySelectionMenuFacts(
            items: isHiddenValues.enumerated().map { index, isHidden in
                VisibilityMenuItemFacts(
                    name: "item-\(index)",
                    isHidden: isHidden
                )
            }
        )
    }

    /// 把测试中的绝对路径字面量转为已验证值。
    private func absolutePath(_ rawValue: String) -> AbsoluteFilePath {
        guard let path = AbsoluteFilePath(path: rawValue) else {
            preconditionFailure("Test path must be absolute")
        }
        return path
    }
}

/// 仅用于证明同一命令类型可以承载不同菜单 Action 参数。
private struct TestParameterizedCommand: ContextCommandPayload, Equatable {
    /// 测试 Feature 的单一功能级身份。
    static let descriptor = ContextCommandDescriptor(
        id: "test-parameterized",
        title: "转换格式",
        icon: .systemSymbol(name: "arrow.triangle.2.circlepath")
    )

    /// 具体叶子写入的目标格式参数。
    let format: TestFormat

    /// Action 构建时绑定的目标。
    let targetPath: AbsoluteFilePath
}

/// 参数化测试命令支持的两个示例值。
private enum TestFormat: String, Codable, Equatable, Sendable {
    case png
    case jpeg
}

/// 用递归菜单声明两个参数化叶子的测试 Feature。
private final class TestParameterizedFeature: ContextMenuFeature {
    /// 两个 Action 共用同一种跨进程命令。
    typealias Command = TestParameterizedCommand

    /// 满足真实 Feature 的投递依赖。
    let commandClient: ContextCommandClient

    /// 注入测试客户端。
    init(commandClient: ContextCommandClient) {
        self.commandClient = commandClient
    }

    /// 用一个功能级子菜单集中声明所有参数化 Action。
    var nodes: [ContextMenuNode<ContextMenuAction<TestParameterizedCommand>>] {
        [
            .submenu(
                title: "转换格式",
                children: [
                    .item(
                        ContextMenuAction(
                            id: "png",
                            title: "PNG",
                            icon: .systemSymbol(name: "photo"),
                            command: { context in
                                guard let targetPath = context.snapshot
                                    .absolutePaths.first
                                else {
                                    return nil
                                }
                                return TestParameterizedCommand(
                                    format: .png,
                                    targetPath: targetPath
                                )
                            }
                        )
                    ),
                    .item(
                        ContextMenuAction(
                            id: "jpeg",
                            title: "JPEG",
                            icon: .systemSymbol(
                                name: "photo.badge.arrow.down"
                            ),
                            command: { context in
                                guard let targetPath = context.snapshot
                                    .absolutePaths.first
                                else {
                                    return nil
                                }
                                return TestParameterizedCommand(
                                    format: .jpeg,
                                    targetPath: targetPath
                                )
                            }
                        )
                    ),
                ]
            ),
        ]
    }
}

/// 验证连续不可用叶子不会消耗 action tag 的测试命令。
private struct TestAvailabilityCommand: ContextCommandPayload, Equatable {
    /// 测试 Feature 的单一功能级身份。
    static let descriptor = ContextCommandDescriptor(
        id: "test-availability",
        title: "可用性",
        icon: .systemSymbol(name: "checkmark.circle")
    )

    /// 使测试命令保持非空的简单负载。
    let marker: Bool

    /// 创建可投递的测试命令。
    init(marker: Bool = true) {
        self.marker = marker
    }
}

/// 声明两层子菜单、两个不可用叶子和一个可用叶子的测试 Feature。
private final class TestAvailabilityFeature: ContextMenuFeature {
    /// 所有叶子共用同一种跨进程命令。
    typealias Command = TestAvailabilityCommand

    /// 满足真实 Feature 的投递依赖。
    let commandClient: ContextCommandClient

    /// 注入测试客户端。
    init(commandClient: ContextCommandClient) {
        self.commandClient = commandClient
    }

    /// 构造可以验证递归 AppKit 菜单行为的声明树。
    var nodes: [ContextMenuNode<ContextMenuAction<TestAvailabilityCommand>>] {
        [
            .submenu(
                title: "第一层",
                children: [
                    .item(
                        ContextMenuAction(
                            id: "unavailable-one",
                            title: "不可用一",
                            icon: .systemSymbol(name: "xmark.circle"),
                            command: { _ in nil }
                        )
                    ),
                    .item(
                        ContextMenuAction(
                            id: "unavailable-two",
                            title: "不可用二",
                            icon: .systemSymbol(name: "xmark.circle"),
                            command: { _ in nil }
                        )
                    ),
                    .submenu(
                        title: "第二层",
                        children: [
                            .item(
                                ContextMenuAction(
                                    id: "enabled",
                                    title: "启用",
                                    icon: .systemSymbol(
                                        name: "checkmark.circle"
                                    ),
                                    command: { _ in
                                        TestAvailabilityCommand()
                                    }
                                )
                            ),
                        ]
                    ),
                ]
            ),
        ]
    }
}

/// 记录 Controller 点击投递的命令，用于验证准备绑定。
nonisolated private final class RecordingContextCommandTransport:
    ContextCommandSending,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var requests: [ContextCommandRequest] = []

    var recordedRequests: [ContextCommandRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func send(
        _ request: ContextCommandRequest,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        lock.lock()
        requests.append(request)
        lock.unlock()
        completion(.success(()))
    }
}
