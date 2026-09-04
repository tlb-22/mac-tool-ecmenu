import AppKit
import ApplicationServices
import Foundation

@MainActor
final class FinderMenuSession {
    private enum MenuCommandModifiers {
        static let commandOnly = Int(([] as AXMenuItemModifiers).rawValue)
        static let commandShift = Int(AXMenuItemModifiers.shift.rawValue)
    }

    private struct ResolvedItem {
        let directChild: AXUIElement
        let menuElement: AXUIElement
    }

    private struct ResolvedContext {
        let window: AXUIElement
        let selectionOwner: AXUIElement
        let firstItem: ResolvedItem
        let remainingItems: [ResolvedItem]

        var items: [ResolvedItem] { [firstItem] + remainingItems }
    }

    private struct SelectionOwnerCandidate {
        let owner: AXUIElement
        var itemsByURL: [[ResolvedItem]]
    }

    private struct VerifiedSelection {
        let owner: AXUIElement
        let children: [AXUIElement]
    }

    private enum MenuObservation {
        case ready(MenuSnapshot)
        case notReady
        case gone
    }

    private enum FinderWindowCandidateStatus {
        case pending
        case unrelated
        case finderWindow
    }

    private enum State {
        case initialized
        case window(AXUIElement, AXUIElement)
        case sheet(AXUIElement, AXUIElement, AXUIElement)
        case menuRequested(AXUIElement, AXUIElement, VerifiedSelection)
        case menuOpened(AXUIElement, AXUIElement, AXUIElement, VerifiedSelection)
        case menuReady(
            AXUIElement,
            AXUIElement,
            AXUIElement,
            VerifiedSelection,
            MenuSnapshot
        )
        case finished
    }

    private let context: FinderMenuContext
    private var finder: NSRunningApplication?
    private var state: State = .initialized

    init(context: FinderMenuContext) {
        self.context = context
    }

    func prepare() throws -> MenuSnapshot {
        let finder = try waitForFinder()
        self.finder = finder
        let application = AXUIElementCreateApplication(finder.processIdentifier)
        let window = try createFinderWindow(
            finder: finder,
            application: application,
            processIdentifier: finder.processIdentifier
        )
        state = .window(application, window)
        let resolvedContext = try navigateOwnedWindow(
            window,
            application: application,
            processIdentifier: finder.processIdentifier,
            directory: context.directory
        )
        state = .window(application, resolvedContext.window)

        let selection = try applySelection(
            in: resolvedContext,
            application: application
        )
        let target = try menuTarget(in: resolvedContext)
        let menuWaiter = try AXElementNotificationWaiter(
            processIdentifier: finder.processIdentifier,
            application: application,
            notification: kAXMenuOpenedNotification as CFString
        )

        state = .menuRequested(application, resolvedContext.window, selection)
        try AXClient.perform(kAXShowMenuAction as CFString, on: target)
        guard let menu = try menuWaiter.wait(
            timeout: AutomationTiming.menu,
            resolve: { elements in
                try self.firstElement(
                    withRole: kAXMenuRole as String,
                    in: elements
                )
            }
        ) else {
            throw AutomationFailure.menuOpenTimeout
        }

        state = .menuOpened(application, resolvedContext.window, menu, selection)
        try movePointerOutsideMenu(menu, within: resolvedContext.window)
        let snapshot = try waitForStableMenu(menu)
        try verifySelection(selection)
        state = .menuReady(
            application,
            resolvedContext.window,
            menu,
            selection,
            snapshot
        )
        return snapshot
    }

    func verifyAfterCapture() throws {
        guard case let .menuReady(
            application,
            window,
            menu,
            selection,
            expected
        ) = state,
              let finder,
              !finder.isTerminated,
              try AXClient.bool(
                  kAXFrontmostAttribute as CFString,
                  of: application
              ) == true else {
            throw AutomationFailure.focusLost("Finder lost foreground focus during capture.")
        }
        guard let mainWindow = try AXClient.element(
            kAXMainWindowAttribute as CFString,
            of: application
        ), AXClient.same(mainWindow, window) else {
            throw AutomationFailure.focusLost(
                "The owned Finder window stopped being the main window during capture."
            )
        }
        try verifySelection(selection)

        let actual: MenuSnapshot
        switch try observeMenu(menu) {
        case let .ready(snapshot):
            actual = snapshot
        case .notReady:
            throw AutomationFailure.menuChanged
        case .gone:
            throw AutomationFailure.focusLost("The Finder menu closed during capture.")
        }
        guard actual == expected else { throw AutomationFailure.menuChanged }
    }

    /// 即使菜单关闭失败，也继续尝试关闭本次拥有的窗口；首个失败仍会返回给调用方。
    func closeOwnedUI() throws {
        let application: AXUIElement
        let window: AXUIElement
        let sheet: AXUIElement?
        let menu: AXUIElement?

        switch state {
        case .initialized, .finished:
            state = .finished
            return
        case let .window(app, ownedWindow),
             let .menuRequested(app, ownedWindow, _):
            application = app
            window = ownedWindow
            sheet = nil
            menu = nil
        case let .sheet(app, ownedWindow, ownedSheet):
            application = app
            window = ownedWindow
            sheet = ownedSheet
            menu = nil
        case let .menuOpened(app, ownedWindow, openMenu, _),
             let .menuReady(app, ownedWindow, openMenu, _, _):
            application = app
            window = ownedWindow
            sheet = nil
            menu = openMenu
        }

        var firstFailure: AutomationFailure?
        if let menu {
            do {
                try closeMenu(menu, application: application)
            } catch let failure as AutomationFailure {
                firstFailure = failure
            }
        }
        if let sheet {
            do {
                try closeSheet(sheet, in: window, application: application)
            } catch let failure as AutomationFailure {
                if firstFailure == nil { firstFailure = failure }
            }
        }
        do {
            try closeWindow(window, application: application)
            state = .finished
        } catch let failure as AutomationFailure {
            if firstFailure == nil { firstFailure = failure }
        }
        if let firstFailure { throw firstFailure }
    }

    private func createFinderWindow(
        finder: NSRunningApplication,
        application: AXUIElement,
        processIdentifier: pid_t
    ) throws -> AXUIElement {
        let existingWindows = try AXClient.elements(
            kAXWindowsAttribute as CFString,
            of: application
        )
        if !finder.isActive, existingWindows.isEmpty {
            let activationWindowWaiter = try AXElementNotificationWaiter(
                processIdentifier: processIdentifier,
                application: application,
                notification: kAXWindowCreatedNotification as CFString
            )
            try waitForFinderFrontmost(
                finder: finder,
                application: application
            )
            return try claimCreatedFinderWindow(
                using: activationWindowWaiter,
                application: application
            )
        }

        try waitForFinderFrontmost(
            finder: finder,
            application: application
        )
        guard let command = try menuCommand(
            character: "n",
            modifiers: MenuCommandModifiers.commandOnly,
            application: application
        ),
              try AXClient.supports(kAXPressAction as CFString, on: command.element) else {
            throw AutomationFailure.newFinderWindowUnavailable
        }
        let windowWaiter = try AXElementNotificationWaiter(
            processIdentifier: processIdentifier,
            application: application,
            notification: kAXWindowCreatedNotification as CFString
        )
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            != "com.apple.loginwindow" else {
            throw AutomationFailure.interactiveSessionUnavailable
        }
        try AXClient.perform(kAXPressAction as CFString, on: command.element)
        return try claimCreatedFinderWindow(
            using: windowWaiter,
            application: application
        )
    }

    private func claimCreatedFinderWindow(
        using waiter: AXElementNotificationWaiter,
        application: AXUIElement
    ) throws -> AXUIElement {
        let window = try waitForCreatedFinderWindow(
            using: waiter,
            application: application
        )
        state = .window(application, window)
        try waitForOwnedFinderWindow(
            window,
            using: waiter,
            application: application
        )
        return window
    }

    private func waitForCreatedFinderWindow(
        using waiter: AXElementNotificationWaiter,
        application: AXUIElement
    ) throws -> AXUIElement {
        var previousCandidate: AXUIElement?
        guard let window = try waiter.wait(
            timeout: AutomationTiming.finder,
            resolve: { elements -> AXUIElement? in
                guard let candidate = try self.createdFinderWindow(
                    from: elements,
                    application: application
                ) else {
                    previousCandidate = nil
                    return nil
                }
                guard let previousCandidate,
                      AXClient.same(previousCandidate, candidate) else {
                    previousCandidate = candidate
                    return nil
                }
                return candidate
            }
        ) else {
            throw AutomationFailure.finderWindowTimeout
        }
        return window
    }

    private func waitForOwnedFinderWindow(
        _ window: AXUIElement,
        using waiter: AXElementNotificationWaiter,
        application: AXUIElement
    ) throws {
        var wasFocused = false
        guard try waiter.wait(
            timeout: AutomationTiming.finder,
            resolve: { elements -> Bool? in
                guard let candidate = try self.createdFinderWindow(
                    from: elements,
                    application: application
                ) else {
                    wasFocused = false
                    return nil
                }
                guard AXClient.same(candidate, window) else {
                    throw AutomationFailure.finderWindowOwnershipAmbiguous
                }
                guard try self.finderWindowIsFocused(
                    window,
                    application: application
                ) else {
                    wasFocused = false
                    return nil
                }
                guard wasFocused else {
                    wasFocused = true
                    return nil
                }
                return true
            }
        ) != nil else {
            throw AutomationFailure.finderWindowTimeout
        }
    }

    private func navigateOwnedWindow(
        _ window: AXUIElement,
        application: AXUIElement,
        processIdentifier: pid_t,
        directory: URL
    ) throws -> ResolvedContext {
        let sheetWaiter = try AXElementNotificationWaiter(
            processIdentifier: processIdentifier,
            application: application,
            notification: kAXSheetCreatedNotification as CFString
        )
        guard let command = try menuCommand(
            character: "g",
            modifiers: MenuCommandModifiers.commandShift,
            application: application
        ) else {
            throw AutomationFailure.finderOpenFailed(directory.path)
        }
        try AXClient.perform(kAXPressAction as CFString, on: command.element)
        guard let sheet = try sheetWaiter.wait(
            timeout: AutomationTiming.menu,
            resolve: { elements in
                try self.firstElement(
                    withRole: kAXSheetRole as String,
                    in: elements,
                    attachedTo: window
                )
            }
        ) else {
            throw AutomationFailure.finderOpenFailed(directory.path)
        }
        state = .sheet(application, window, sheet)

        let textFields = try AXTree.paths(below: sheet).filter { path in
            try AXClient.string(
                kAXRoleAttribute as CFString,
                of: path.element
            ) == kAXTextFieldRole as String
        }
        guard textFields.count == 1 else {
            throw AutomationFailure.finderOpenFailed(directory.path)
        }
        let textField = textFields[0].element
        try AXClient.setValue(
            directory.path as CFString,
            for: kAXValueAttribute as CFString,
            on: textField
        )
        try AXClient.setValue(
            kCFBooleanTrue,
            for: kAXFocusedAttribute as CFString,
            on: textField
        )
        guard try AXClient.bool(
            kAXFocusedAttribute as CFString,
            of: textField
        ) == true else {
            throw AutomationFailure.finderOpenFailed(directory.path)
        }
        try FinderKeyboard.press(.returnKey)

        let ownedWindow = window
        let deadline = Date().addingTimeInterval(AutomationTiming.target)
        while Date() < deadline {
            guard try AXClient.bool(
                kAXFrontmostAttribute as CFString,
                of: application
            ) == true else {
                throw AutomationFailure.focusLost(
                    "Finder lost foreground focus while navigating."
                )
            }
            guard let focusedWindow = try AXClient.element(
                kAXFocusedWindowAttribute as CFString,
                of: application
            ) else {
                runLoopSlice(AutomationTiming.poll)
                continue
            }
            if try isOwnedSheetFocus(focusedWindow, sheet: sheet, window: ownedWindow) {
                runLoopSlice(AutomationTiming.poll)
                continue
            }
            guard AXClient.same(focusedWindow, ownedWindow) else {
                throw AutomationFailure.focusLost(
                    "Finder focused another window while navigating."
                )
            }
            if let resolved = try resolveContext(in: focusedWindow),
               try !sheetIsAttached(sheet, to: focusedWindow) {
                state = .window(application, focusedWindow)
                return resolved
            }
            runLoopSlice(AutomationTiming.poll)
        }
        throw AutomationFailure.finderOpenFailed(directory.path)
    }

    private func isOwnedSheetFocus(
        _ focusedElement: AXUIElement,
        sheet: AXUIElement,
        window: AXUIElement
    ) throws -> Bool {
        if AXClient.same(focusedElement, sheet) { return true }
        guard try AXClient.string(
            kAXRoleAttribute as CFString,
            of: focusedElement
        ) == kAXSheetRole as String,
              let sheetWindow = try AXClient.element(
                  kAXWindowAttribute as CFString,
                  of: focusedElement
              ) else {
            return false
        }
        return AXClient.same(sheetWindow, window)
    }

    private func resolveContext(in window: AXUIElement) throws -> ResolvedContext? {
        let requestedURLs = context.representedURLs
        let paths = try AXTree.paths(below: window)
        var candidates: [SelectionOwnerCandidate] = []

        for (urlIndex, requestedURL) in requestedURLs.enumerated() {
            let matches = try paths.filter {
                try AXClient.url(of: $0.element)?.path == requestedURL.path
            }
            guard !matches.isEmpty else { return nil }

            for path in matches {
                for (ancestorIndex, owner) in path.ancestors.enumerated() {
                    guard try AXClient.isSettable(
                        kAXSelectedChildrenAttribute as CFString,
                        on: owner
                    ) else { continue }

                    let directChild = ancestorIndex == 0
                        ? path.element
                        : path.ancestors[ancestorIndex - 1]
                    let ownerChildren = try AXClient.elements(
                        kAXChildrenAttribute as CFString,
                        of: owner
                    )
                    guard ownerChildren.contains(where: {
                        AXClient.same($0, directChild)
                    }) else { continue }

                    let itemElements = path.elementAndAncestors.prefix(
                        ancestorIndex + 1
                    )
                    guard let menuElement = try itemElements.first(where: {
                        try AXClient.supports(
                            kAXShowMenuAction as CFString,
                            on: $0
                        )
                    }) else { continue }

                    let item = ResolvedItem(
                        directChild: directChild,
                        menuElement: menuElement
                    )
                    if let candidateIndex = candidates.firstIndex(where: {
                        AXClient.same($0.owner, owner)
                    }) {
                        if !candidates[candidateIndex].itemsByURL[urlIndex].contains(where: {
                            AXClient.same($0.directChild, directChild)
                        }) {
                            candidates[candidateIndex].itemsByURL[urlIndex].append(item)
                        }
                    } else {
                        var itemsByURL = Array(
                            repeating: [ResolvedItem](),
                            count: requestedURLs.count
                        )
                        itemsByURL[urlIndex] = [item]
                        candidates.append(SelectionOwnerCandidate(
                            owner: owner,
                            itemsByURL: itemsByURL
                        ))
                    }
                }
            }
        }

        let complete = candidates.compactMap { candidate -> ResolvedContext? in
            guard candidate.itemsByURL.allSatisfy({ $0.count == 1 }) else {
                return nil
            }
            let items = candidate.itemsByURL.map { $0[0] }
            guard let firstItem = items.first else { return nil }
            for (index, item) in items.enumerated() {
                guard !items.dropFirst(index + 1).contains(where: {
                    AXClient.same($0.directChild, item.directChild)
                }) else { return nil }
            }
            return ResolvedContext(
                window: window,
                selectionOwner: candidate.owner,
                firstItem: firstItem,
                remainingItems: Array(items.dropFirst())
            )
        }
        guard complete.count == 1 else { return nil }
        return complete[0]
    }

    private func menuCommand(
        character: String,
        modifiers: Int,
        application: AXUIElement
    ) throws -> AXPath? {
        guard let menuBar = try AXClient.element(
            kAXMenuBarAttribute as CFString,
            of: application
        ) else {
            return nil
        }
        return try AXTree.paths(below: menuBar).first { path in
            guard try AXClient.string(
                kAXRoleAttribute as CFString,
                of: path.element
            ) == kAXMenuItemRole as String else {
                return false
            }
            let commandCharacter = try AXClient.string(
                kAXMenuItemCmdCharAttribute as CFString,
                of: path.element
            )?.lowercased()
            let commandModifiers = try AXClient.integer(
                kAXMenuItemCmdModifiersAttribute as CFString,
                of: path.element
            )
            return commandCharacter == character
                && commandModifiers == modifiers
        }
    }

    private func waitForFinder() throws -> NSRunningApplication {
        let deadline = Date().addingTimeInterval(AutomationTiming.finder)
        while Date() < deadline {
            if let finder = runningFinder() { return finder }
            runLoopSlice(AutomationTiming.poll)
        }
        throw AutomationFailure.finderUnavailable
    }

    private func waitForFinderFrontmost(
        finder: NSRunningApplication,
        application: AXUIElement
    ) throws {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            == "com.apple.loginwindow" {
            throw AutomationFailure.interactiveSessionUnavailable
        }
        if finder.isActive { return }

        let helper = NSRunningApplication.current
        let appKitApplication = NSApplication.shared
        appKitApplication.activate()

        let helperDeadline = Date().addingTimeInterval(1)
        while !helper.isActive, Date() < helperDeadline {
            runLoopSlice(AutomationTiming.poll)
        }
        if helper.isActive {
            appKitApplication.yieldActivation(to: finder)
            _ = finder.activate(from: helper, options: [])
        }
        if try AXClient.isSettable(
            kAXFrontmostAttribute as CFString,
            on: application
        ) {
            try AXClient.setValue(
                kCFBooleanTrue,
                for: kAXFrontmostAttribute as CFString,
                on: application
            )
        }

        let deadline = Date().addingTimeInterval(AutomationTiming.finder)
        while Date() < deadline {
            if finder.isActive { return }
            runLoopSlice(AutomationTiming.poll)
        }
        throw AutomationFailure.finderActivationTimeout
    }

    private func createdFinderWindow(
        from elements: [AXUIElement],
        application: AXUIElement
    ) throws -> AXUIElement? {
        var candidates: [AXUIElement] = []
        var hasPendingCandidate = false

        for element in uniqueElements(elements) {
            switch try finderWindowCandidateStatus(element) {
            case .pending:
                hasPendingCandidate = true
            case .unrelated:
                continue
            case .finderWindow:
                candidates.append(element)
            }
        }
        guard candidates.count <= 1 else {
            throw AutomationFailure.finderWindowOwnershipAmbiguous
        }
        guard !hasPendingCandidate, let candidate = candidates.first else {
            return nil
        }

        do {
            let windows = try AXClient.elements(
                kAXWindowsAttribute as CFString,
                of: application
            )
            guard windows.contains(where: { AXClient.same($0, candidate) }) else {
                return nil
            }
        } catch AutomationFailure.accessibility(_, .cannotComplete) {
            return nil
        } catch AutomationFailure.accessibility(_, .invalidUIElement) {
            return nil
        }
        return candidate
    }

    private func finderWindowIsFocused(
        _ window: AXUIElement,
        application: AXUIElement
    ) throws -> Bool {
        do {
            guard try AXClient.bool(
                kAXFrontmostAttribute as CFString,
                of: application
            ) == true,
                  let focusedWindow = try AXClient.element(
                      kAXFocusedWindowAttribute as CFString,
                      of: application
                  ),
                  let mainWindow = try AXClient.element(
                      kAXMainWindowAttribute as CFString,
                      of: application
                  ) else {
                return false
            }
            return AXClient.same(focusedWindow, window)
                && AXClient.same(mainWindow, window)
        } catch AutomationFailure.accessibility(_, .cannotComplete) {
            return false
        } catch AutomationFailure.accessibility(_, .invalidUIElement) {
            return false
        }
    }

    private func finderWindowCandidateStatus(
        _ element: AXUIElement
    ) throws -> FinderWindowCandidateStatus {
        do {
            guard let role = try AXClient.string(
                kAXRoleAttribute as CFString,
                of: element
            ) else {
                return .pending
            }
            guard role == kAXWindowRole as String else { return .unrelated }
            guard let identifier = try AXClient.string(
                kAXIdentifierAttribute as CFString,
                of: element
            ) else {
                return .pending
            }
            return identifier == "FinderWindow" ? .finderWindow : .unrelated
        } catch AutomationFailure.accessibility(_, .cannotComplete) {
            return .pending
        } catch AutomationFailure.accessibility(_, .invalidUIElement) {
            return .unrelated
        }
    }

    private func firstElement(
        withRole expectedRole: String,
        in elements: [AXUIElement],
        attachedTo expectedWindow: AXUIElement? = nil
    ) throws -> AXUIElement? {
        var matches: [AXUIElement] = []

        for element in uniqueElements(elements) {
            do {
                guard try AXClient.string(
                    kAXRoleAttribute as CFString,
                    of: element
                ) == expectedRole else {
                    continue
                }
                if let expectedWindow {
                    guard let window = try AXClient.element(
                        kAXWindowAttribute as CFString,
                        of: element
                    ), AXClient.same(window, expectedWindow) else {
                        continue
                    }
                }
                matches.append(element)
            } catch AutomationFailure.accessibility(_, .cannotComplete) {
                continue
            } catch AutomationFailure.accessibility(_, .invalidUIElement) {
                continue
            }
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private func uniqueElements(_ elements: [AXUIElement]) -> [AXUIElement] {
        var unique: [AXUIElement] = []
        for element in elements where !unique.contains(where: {
            AXClient.same($0, element)
        }) {
            unique.append(element)
        }
        return unique
    }

    private func applySelection(
        in resolved: ResolvedContext,
        application: AXUIElement
    ) throws -> VerifiedSelection {
        let expectedChildren: [AXUIElement]
        switch context {
        case .container:
            expectedChildren = []
            try AXClient.setValue(
                expectedChildren as CFArray,
                for: kAXSelectedChildrenAttribute as CFString,
                on: resolved.selectionOwner
            )
        case .items:
            expectedChildren = resolved.items.map(\.directChild)
            if resolved.remainingItems.isEmpty {
                try click(
                    resolved.firstItem,
                    in: resolved,
                    application: application
                )
            } else {
                try click(
                    resolved.firstItem,
                    in: resolved,
                    application: application
                )
                try waitForSelection(
                    [resolved.firstItem.directChild],
                    on: resolved.selectionOwner
                )
                try selectAllItems(in: resolved, application: application)
            }
        }

        try waitForSelection(expectedChildren, on: resolved.selectionOwner)
        return VerifiedSelection(
            owner: resolved.selectionOwner,
            children: expectedChildren
        )
    }

    private func waitForSelection(
        _ expectedChildren: [AXUIElement],
        on owner: AXUIElement
    ) throws {
        let deadline = Date().addingTimeInterval(AutomationTiming.target)
        while Date() < deadline {
            let actualChildren = try AXClient.elements(
                kAXSelectedChildrenAttribute as CFString,
                of: owner
            )
            if sameElements(actualChildren, expectedChildren) { return }
            runLoopSlice(AutomationTiming.poll)
        }
        throw AutomationFailure.finderSelectionTimeout
    }

    private func click(
        _ item: ResolvedItem,
        in resolved: ResolvedContext,
        application: AXUIElement
    ) throws {
        try verifySelectionFocus(in: resolved, application: application)

        let location = try FinderPointer.location(of: item.menuElement)
        let hitElement = try AXClient.element(
            at: location,
            in: AXUIElementCreateSystemWide()
        )
        guard try isDescendant(hitElement, of: item.directChild) else {
            throw AutomationFailure.focusLost(
                "The Finder item was obscured before selection."
            )
        }
        try FinderPointer.click(at: location)
    }

    private func selectAllItems(
        in resolved: ResolvedContext,
        application: AXUIElement
    ) throws {
        try verifySelectionFocus(in: resolved, application: application)
        let ownerChildren = try AXClient.elements(
            kAXChildrenAttribute as CFString,
            of: resolved.selectionOwner
        )
        let scenarioChildren = resolved.items.map(\.directChild)
        guard sameElements(ownerChildren, scenarioChildren) else {
            throw AutomationFailure.finderSelectAllScopeMismatch
        }
        guard let command = try menuCommand(
            character: "a",
            modifiers: MenuCommandModifiers.commandOnly,
            application: application
        ), try AXClient.supports(kAXPressAction as CFString, on: command.element) else {
            throw AutomationFailure.finderSelectAllUnavailable
        }
        try AXClient.perform(kAXPressAction as CFString, on: command.element)
    }

    private func verifySelectionFocus(
        in resolved: ResolvedContext,
        application: AXUIElement
    ) throws {
        guard try AXClient.bool(
            kAXFrontmostAttribute as CFString,
            of: application
        ) == true,
              let focusedWindow = try AXClient.element(
                  kAXFocusedWindowAttribute as CFString,
                  of: application
              ), AXClient.same(focusedWindow, resolved.window) else {
            throw AutomationFailure.focusLost(
                "The owned Finder window lost focus before selection."
            )
        }
    }

    private func isDescendant(
        _ element: AXUIElement,
        of ancestor: AXUIElement
    ) throws -> Bool {
        var current: AXUIElement? = element
        while let candidate = current {
            if AXClient.same(candidate, ancestor) { return true }
            current = try AXClient.element(
                kAXParentAttribute as CFString,
                of: candidate
            )
        }
        return false
    }

    private func verifySelection(_ selection: VerifiedSelection) throws {
        let actualChildren = try AXClient.elements(
            kAXSelectedChildrenAttribute as CFString,
            of: selection.owner
        )
        guard sameElements(actualChildren, selection.children) else {
            throw AutomationFailure.finderSelectionTimeout
        }
    }

    private func menuTarget(in resolved: ResolvedContext) throws -> AXUIElement {
        switch context {
        case .container:
            guard try AXClient.supports(
                kAXShowMenuAction as CFString,
                on: resolved.selectionOwner
            ) else {
                throw AutomationFailure.showMenuUnavailable
            }
            return resolved.selectionOwner
        case .items:
            return resolved.firstItem.menuElement
        }
    }

    private func movePointerOutsideMenu(
        _ menu: AXUIElement,
        within window: AXUIElement
    ) throws {
        let menuFrame = try AXClient.frame(of: menu)
        let windowFrame = try AXClient.frame(of: window)
        let menuCenter = CGPoint(x: menuFrame.midX, y: menuFrame.midY)
        let inset: CGFloat = 16
        let candidates = [
            CGPoint(x: windowFrame.minX + inset, y: windowFrame.minY + inset),
            CGPoint(x: windowFrame.maxX - inset, y: windowFrame.minY + inset),
            CGPoint(x: windowFrame.minX + inset, y: windowFrame.maxY - inset),
            CGPoint(x: windowFrame.maxX - inset, y: windowFrame.maxY - inset),
        ]
        guard let location = candidates.max(by: {
            distanceSquared(from: $0, to: menuCenter)
                < distanceSquared(from: $1, to: menuCenter)
        }), !menuFrame.contains(location) else {
            throw AutomationFailure.pointerEventUnavailable
        }
        try FinderPointer.move(to: location)
    }

    private func distanceSquared(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        let deltaX = lhs.x - rhs.x
        let deltaY = lhs.y - rhs.y
        return deltaX * deltaX + deltaY * deltaY
    }

    private func waitForStableMenu(_ menu: AXUIElement) throws -> MenuSnapshot {
        let deadline = Date().addingTimeInterval(AutomationTiming.stability)
        var previous: MenuSnapshot?
        while Date() < deadline {
            switch try observeMenu(menu) {
            case let .ready(current):
                if current == previous { return current }
                previous = current
            case .notReady:
                previous = nil
            case .gone:
                throw AutomationFailure.menuStabilityTimeout
            }
            runLoopSlice(AutomationTiming.poll)
        }
        throw AutomationFailure.menuStabilityTimeout
    }

    private func observeMenu(_ menu: AXUIElement) throws -> MenuObservation {
        do {
            guard let role = try AXClient.string(
                kAXRoleAttribute as CFString,
                of: menu
            ) else {
                return .notReady
            }
            guard role == kAXMenuRole as String else {
                throw AutomationFailure.invalidAccessibilityValue(
                    kAXRoleAttribute as String
                )
            }
            let frame = try AXClient.frame(of: menu)
            let titles = try AXClient.elements(
                kAXChildrenAttribute as CFString,
                of: menu
            ).compactMap { item -> String? in
                guard try AXClient.string(
                    kAXRoleAttribute as CFString,
                    of: item
                ) == kAXMenuItemRole as String else { return nil }
                return try AXClient.string(
                    kAXTitleAttribute as CFString,
                    of: item
                ) ?? ""
            }
            guard frame.width > 0, frame.height > 0, !titles.isEmpty else {
                return .notReady
            }
            guard let finder else {
                preconditionFailure("An open Finder menu requires a Finder process.")
            }
            return .ready(MenuSnapshot(
                processIdentifier: finder.processIdentifier,
                rect: MenuRect(frame),
                titles: titles
            ))
        } catch AutomationFailure.accessibility(_, .invalidUIElement) {
            return .gone
        } catch AutomationFailure.accessibility(_, .noValue) {
            return .notReady
        }
    }

    private func closeMenu(
        _ menu: AXUIElement,
        application: AXUIElement
    ) throws {
        switch try observeMenu(menu) {
        case .gone:
            return
        case .ready, .notReady:
            break
        }
        guard try AXClient.supports(kAXCancelAction as CFString, on: menu) else {
            throw AutomationFailure.menuCancelUnavailable
        }
        guard let finder else {
            preconditionFailure("Owned Finder UI requires a Finder process.")
        }
        let closeWaiter = try AXElementNotificationWaiter(
            processIdentifier: finder.processIdentifier,
            application: application,
            notification: kAXMenuClosedNotification as CFString
        )
        try AXClient.perform(kAXCancelAction as CFString, on: menu)
        guard try closeWaiter.wait(
            timeout: AutomationTiming.cleanup,
            resolve: { elements in
                if elements.contains(where: { AXClient.same($0, menu) }) {
                    return true
                }
                do {
                    if case .gone = try self.observeMenu(menu) {
                        return true
                    }
                } catch AutomationFailure.accessibility(_, .cannotComplete) {
                    return nil
                }
                return nil
            }
        ) != nil else {
            throw AutomationFailure.menuCloseTimeout
        }
    }

    private func sheetIsAttached(
        _ sheet: AXUIElement,
        to window: AXUIElement
    ) throws -> Bool {
        do {
            guard let sheetWindow = try AXClient.element(
                kAXWindowAttribute as CFString,
                of: sheet
            ) else { return false }
            return AXClient.same(sheetWindow, window)
        } catch AutomationFailure.accessibility(_, .invalidUIElement) {
            return false
        }
    }

    private func closeSheet(
        _ sheet: AXUIElement,
        in window: AXUIElement,
        application: AXUIElement
    ) throws {
        guard try sheetIsAttached(sheet, to: window) else { return }
        guard try AXClient.bool(
            kAXFrontmostAttribute as CFString,
            of: application
        ) == true,
              let focusedElement = try AXClient.element(
                  kAXFocusedWindowAttribute as CFString,
                  of: application
              ) else {
            throw AutomationFailure.sheetCancelUnavailable
        }
        let focusBelongsToOwnedUI: Bool
        if AXClient.same(focusedElement, window) {
            focusBelongsToOwnedUI = true
        } else {
            focusBelongsToOwnedUI = try isOwnedSheetFocus(
                focusedElement,
                sheet: sheet,
                window: window
            )
        }
        guard focusBelongsToOwnedUI else {
            throw AutomationFailure.sheetCancelUnavailable
        }
        try FinderKeyboard.press(.escape)

        let deadline = Date().addingTimeInterval(AutomationTiming.cleanup)
        while Date() < deadline {
            if try !sheetIsAttached(sheet, to: window) { return }
            runLoopSlice(AutomationTiming.poll)
        }
        throw AutomationFailure.sheetCloseTimeout
    }

    private func closeWindow(_ window: AXUIElement, application: AXUIElement) throws {
        let windows = try AXClient.elements(kAXWindowsAttribute as CFString, of: application)
        guard windows.contains(where: { AXClient.same($0, window) }) else { return }
        guard let closeButton = try AXClient.element(
            kAXCloseButtonAttribute as CFString,
            of: window
        ), try AXClient.supports(kAXPressAction as CFString, on: closeButton) else {
            throw AutomationFailure.windowCloseTimeout
        }
        try AXClient.perform(kAXPressAction as CFString, on: closeButton)

        let deadline = Date().addingTimeInterval(AutomationTiming.cleanup)
        while Date() < deadline {
            let remaining = try AXClient.elements(
                kAXWindowsAttribute as CFString,
                of: application
            )
            if !remaining.contains(where: { AXClient.same($0, window) }) { return }
            runLoopSlice(AutomationTiming.poll)
        }
        throw AutomationFailure.windowCloseTimeout
    }
}

private func runningFinder() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
        .first(where: { !$0.isTerminated })
}

private func sameElements(_ lhs: [AXUIElement], _ rhs: [AXUIElement]) -> Bool {
    lhs.count == rhs.count && lhs.allSatisfy { element in
        rhs.contains(where: { AXClient.same($0, element) })
    }
}
