// PreferencesToolbar.swift
// OpenClip
//
// The settings window's toolbar, owned by AppKit rather than SwiftUI. SwiftUI
// rebuilds `.toolbar` per pane, which makes the title bar re-measure and moves
// the traffic lights; this toolbar is created once and only its contents change.
//
// The trailing switch is a title bar accessory, not a toolbar item: macOS 26
// merges adjacent toolbar items into one glass capsule.
import AppKit
import Combine
import Core

public enum PreferencesToolbarAction: Sendable, Equatable {
    case newGroup
    case addCustomAction
    case addApplication
    case addAIAction
    case installExtensionFile
    case openCustomActions
    case refreshStore
    case setStoreSort(StoreSort)
    /// The window decides what the switch means for the page on screen.
    case setPageToggle(Bool)
    /// A pick from the trailing ellipsis menu, by `SettingsToolbarMenuItem.id`.
    case pageMenuItem(String)
}

/// One row of the toolbar's **+** menu. A plain value so its contents are testable away from AppKit.
struct PreferencesPlusMenuItem: Equatable {
    let title: String
    let symbol: String
    let action: PreferencesToolbarAction
    var startsGroup: Bool = false
}

/// What the toolbar's **+** offers per page. Pages not listed here get no menu.
enum PreferencesPlusMenu {
    static func items(for page: SettingsPage) -> [PreferencesPlusMenuItem] {
        switch page {
        case .customize:
            return [
                PreferencesPlusMenuItem(
                    title: String(localized: "New Group"),
                    symbol: "folder.badge.plus",
                    action: .newGroup
                ),
                PreferencesPlusMenuItem(
                    title: String(localized: "Custom Action"),
                    symbol: "plus",
                    action: .openCustomActions,
                    startsGroup: true
                ),
                PreferencesPlusMenuItem(
                    title: String(localized: "Install Extension"),
                    symbol: "puzzlepiece.extension",
                    action: .installExtensionFile
                ),
            ]
        case .appRules:
            return [PreferencesPlusMenuItem(
                title: String(localized: "Add Application"),
                symbol: "plus",
                action: .addApplication
            )]
        case .ai:
            return [PreferencesPlusMenuItem(
                title: String(localized: "New AI Action"),
                symbol: "plus",
                action: .addAIAction
            )]
        default:
            return []
        }
    }
}

/// The bridge between the SwiftUI panes and the AppKit toolbar.
@MainActor
public final class PreferencesToolbarModel: ObservableObject {
    @Published public var page: SettingsPage = .general
    /// Resolved by the window; an action's page is titled after the action.
    @Published public var title: String = SettingsPage.general.staticTitle ?? ""
    /// `nil` hides the switch.
    @Published public var pageToggle: SettingsToolbarToggle?
    /// Empty hides the ellipsis menu.
    @Published public var pageMenuItems: [SettingsToolbarMenuItem] = []
    @Published public var searchQuery: String = ""
    @Published public var storeSort: StoreSort = .featured
    @Published public var isRefreshing: Bool = false

    public let actions = PassthroughSubject<PreferencesToolbarAction, Never>()

    public init() {}
}

@MainActor
public final class PreferencesToolbarController: NSObject, NSToolbarDelegate, NSSearchFieldDelegate, NSToolbarItemValidation {
    private enum ItemID {
        static let navigation = NSToolbarItem.Identifier("openclip.preferences.navigation")
        /// A toolbar item, not the window title: a unified toolbar's own title area leaves a wide gap.
        static let title = NSToolbarItem.Identifier("openclip.preferences.title")
        static let sort = NSToolbarItem.Identifier("openclip.preferences.sort")
        static let storeInstall = NSToolbarItem.Identifier("openclip.preferences.storeInstall")
        static let refresh = NSToolbarItem.Identifier("openclip.preferences.refresh")
        static let pageMenu = NSToolbarItem.Identifier("openclip.preferences.pageMenu")
        static let search = NSToolbarItem.Identifier("openclip.preferences.search")
        static let action = NSToolbarItem.Identifier("openclip.preferences.action")
    }

    private let model: PreferencesToolbarModel
    private let router: SettingsRouter
    private var cancellables: Set<AnyCancellable> = []
    /// The pane name is drawn by the title item: on macOS 26 a unified toolbar ignores
    /// `titleVisibility = .hidden`, so the name would show twice.
    public weak var window: NSWindow? {
        didSet {
            installSidebarTrackingSeparator(retriesLeft: 20)
            installPageToggleAccessory()
            window?.setAccessibilityTitle(model.title)
        }
    }

    private weak var trackingSplitView: NSSplitView?

    private weak var navigationGroup: NSToolbarItemGroup?
    private weak var backItem: NSToolbarItem?
    private weak var forwardItem: NSToolbarItem?
    private weak var titleLabel: NSTextField?
    private weak var searchItem: NSToolbarItem?
    private weak var actionItem: NSToolbarItem?
    private var actionMenuItems: [PreferencesPlusMenuItem] = []
    private weak var searchField: NSSearchField?
    private weak var sortItem: NSMenuToolbarItem?
    private weak var storeInstallItem: NSToolbarItem?
    private weak var storeInstallButton: NSButton?
    private weak var refreshItem: NSToolbarItem?
    private weak var refreshButton: NSButton?
    private weak var actionButton: NSButton?
    private weak var pageMenuItem: NSToolbarItem?
    private weak var pageMenuButton: NSButton?
    private var pageToggleAccessory: NSTitlebarAccessoryViewController?
    private var pageToggleHost: TitlebarSwitchHost?

    public init(model: PreferencesToolbarModel, router: SettingsRouter = .shared) {
        self.model = model
        self.router = router
        super.init()

        model.$page
            .sink { [weak self] page in self?.sync(page: page) }
            .store(in: &cancellables)

        model.$title
            .sink { [weak self] title in
                self?.titleLabel?.stringValue = title
                self?.window?.setAccessibilityTitle(title)
            }
            .store(in: &cancellables)

        model.$searchQuery
            .sink { [weak self] query in
                guard let field = self?.searchField, field.stringValue != query else { return }
                field.stringValue = query
            }
            .store(in: &cancellables)

        model.$isRefreshing
            .sink { [weak self] isRefreshing in
                self?.refreshButton?.isEnabled = !isRefreshing
            }
            .store(in: &cancellables)

        model.$storeSort
            .sink { [weak self] sort in
                guard let self else { return }
                self.sortItem?.menu = self.makeSortMenu(selected: sort)
            }
            .store(in: &cancellables)

        model.$pageToggle
            .sink { [weak self] toggle in self?.sync(pageToggle: toggle) }
            .store(in: &cancellables)

        model.$pageMenuItems
            .sink { [weak self] items in
                self?.setHidden(self?.pageMenuItem, items.isEmpty)
            }
            .store(in: &cancellables)

        // `objectWillChange` fires before the router's state changes; read on the next run loop turn.
        router.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncNavigation() }
            .store(in: &cancellables)
    }

    public func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "OpenClipPreferencesToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = false
        return toolbar
    }

    // MARK: - Item contents per page

    private func sync(page: SettingsPage) {
        setHidden(searchItem, !Self.showsSearch(for: page))
        setHidden(sortItem, page != .store)
        setHidden(storeInstallItem, page != .store)
        setHidden(refreshItem, page != .store)

        switch page {
        case .customize:
            configureActionButton(symbol: "plus", tooltip: String(localized: "Add"))
        case .appRules:
            configureActionButton(symbol: "plus", tooltip: String(localized: "Add Application"))
        case .ai:
            configureActionButton(symbol: "plus", tooltip: String(localized: "Add Custom AI Action"))
        default:
            setHidden(actionItem, true)
        }

        // Pages with several things to add (the Actions list) get a menu; others act on press.
        actionMenuItems = PreferencesPlusMenu.items(for: page)
    }

    /// Pages with the shared search field; the Actions list's field also matches aliases.
    private static func showsSearch(for page: SettingsPage) -> Bool {
        switch page {
        case .store, .customize, .shortcuts: return true
        default: return false
        }
    }

    private func installPageToggleAccessory() {
        guard let window, pageToggleAccessory == nil else { return }
        let host = TitlebarSwitchHost()
        host.control.target = self
        host.control.action = #selector(pageTogglePressed(_:))

        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        accessory.view = host
        window.addTitlebarAccessoryViewController(accessory)

        pageToggleAccessory = accessory
        pageToggleHost = host
        sync(pageToggle: model.pageToggle)
    }

    /// Mirrors the page's switch. An off, unmovable switch is a package the trust gate holds back.
    private func sync(pageToggle toggle: SettingsToolbarToggle?) {
        guard let host = pageToggleHost else { return }
        guard let toggle else {
            host.showsControl = false
            return
        }
        host.control.state = toggle.isOn ? .on : .off
        host.control.isEnabled = toggle.isEnabled
        host.control.setAccessibilityLabel(toggle.label)
        host.toolTip = toggle.label
        host.showsControl = true
    }

    private func syncNavigation() {
        backItem?.isEnabled = router.canGoBack
        forwardItem?.isEnabled = router.canGoForward
        if let control = navigationGroup?.view as? NSSegmentedControl, control.segmentCount == 2 {
            control.setEnabled(router.canGoBack, forSegment: 0)
            control.setEnabled(router.canGoForward, forSegment: 1)
        }
    }

    /// Hides the whole item: a hidden-control item still gets its glass backing drawn.
    private func setHidden(_ item: NSToolbarItem?, _ hidden: Bool) {
        guard let item else { return }
        if #available(macOS 15.0, *) {
            item.isHidden = hidden
        } else {
            item.view?.isHidden = hidden
        }
    }

    private func configureActionButton(symbol: String, tooltip: String) {
        guard let button = actionButton else { return }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.toolTip = tooltip
        button.isEnabled = !(model.page == .store && model.isRefreshing)
        setHidden(actionItem, false)
        actionItem?.toolTip = tooltip
    }

    // MARK: - Actions

    @objc private func navigationPressed(_ sender: Any?) {
        let index: Int
        if let group = sender as? NSToolbarItemGroup {
            index = group.selectedIndex
        } else if let control = sender as? NSSegmentedControl {
            index = control.selectedSegment
        } else {
            return
        }
        switch index {
        case 0: router.goBack()
        case 1: router.goForward()
        default: break
        }
        syncNavigation()
    }

    @objc private func pageTogglePressed(_ sender: NSSwitch) {
        model.actions.send(.setPageToggle(sender.state == .on))
    }

    @objc private func pageMenuPressed(_ sender: NSButton) {
        let menu = NSMenu()
        // Menu validation would enable anything with a target and undo `isEnabled`.
        menu.autoenablesItems = false
        for entry in model.pageMenuItems {
            guard !entry.isSeparator else {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: entry.title, action: #selector(pageMenuItemPressed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.id
            item.isEnabled = entry.isEnabled
            if !entry.symbol.isEmpty {
                item.image = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil)
                item.preferVisibleImage()
            }
            if entry.role == .destructive {
                // NSMenu has no destructive role, so the colour has to be drawn on.
                item.attributedTitle = NSAttributedString(
                    string: entry.title,
                    attributes: [.foregroundColor: NSColor.systemRed]
                )
            }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    /// The sort menu, rebuilt when the choice changes so the tick moves with it.
    private func makeSortMenu(selected: StoreSort) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for sort in StoreSort.allCases {
            let item = NSMenuItem(title: sort.title, action: #selector(sortItemPressed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = sort.rawValue
            item.image = NSImage(systemSymbolName: sort.symbol, accessibilityDescription: nil)
            item.preferVisibleImage()
            item.state = (sort == selected) ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func sortItemPressed(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let sort = StoreSort(rawValue: raw) else { return }
        model.actions.send(.setStoreSort(sort))
    }

    @objc private func storeInstallPressed(_ sender: NSButton) {
        model.actions.send(.installExtensionFile)
    }

    @objc private func refreshPressed(_ sender: NSButton) {
        model.actions.send(.refreshStore)
    }

    @objc private func pageMenuItemPressed(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        model.actions.send(.pageMenuItem(id))
    }

    @objc private func actionButtonPressed(_ sender: NSButton) {
        guard actionMenuItems.count > 1 else {
            if let only = actionMenuItems.first {
                model.actions.send(only.action)
            }
            return
        }
        let menu = makeActionMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    private func makeActionMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in actionMenuItems {
            if entry.startsGroup, !menu.items.isEmpty {
                menu.addItem(.separator())
            }
            let item = NSMenuItem(
                title: entry.title,
                action: #selector(actionMenuItemPressed(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = entry.action
            item.image = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil)
            item.preferVisibleImage()
            menu.addItem(item)
        }
        return menu
    }

    @objc private func actionMenuItemPressed(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? PreferencesToolbarAction else { return }
        model.actions.send(action)
    }

    public func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField else { return }
        model.searchQuery = field.stringValue
    }

    // MARK: - NSToolbarItemValidation

    public func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        if item === backItem { return router.canGoBack }
        if item === forwardItem { return router.canGoForward }
        return true
    }

    // MARK: - NSToolbarDelegate

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // A leading flexible space pushes the search field into the overflow menu at minimum width.
        [
            ItemID.navigation, ItemID.title, .flexibleSpace,
            ItemID.action, ItemID.search, ItemID.sort, ItemID.storeInstall, ItemID.refresh, ItemID.pageMenu
        ]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator] + toolbarDefaultItemIdentifiers(toolbar)
    }

    /// Gives the leading items an anchor; without it they pack against the right edge.
    private func installSidebarTrackingSeparator(retriesLeft: Int) {
        guard let toolbar = window?.toolbar,
              !toolbar.items.contains(where: { $0.itemIdentifier == .sidebarTrackingSeparator }) else { return }
        // SwiftUI creates the NSSplitView on a later layout pass than the toolbar, so retry.
        guard let contentView = window?.contentView,
              let splitView = Self.firstSplitView(in: contentView),
              splitView.arrangedSubviews.count > 1 else {
            guard retriesLeft > 0 else {
                Log.chrome.error("Preferences toolbar found no split view to track; items will right-align")
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.installSidebarTrackingSeparator(retriesLeft: retriesLeft - 1)
            }
            return
        }
        trackingSplitView = splitView
        if let controller = splitView.delegate as? NSSplitViewController {
            for item in controller.splitViewItems where item.titlebarSeparatorStyle != .none {
                item.titlebarSeparatorStyle = .none
            }
        }
        toolbar.insertItem(withItemIdentifier: .sidebarTrackingSeparator, at: 0)
    }

    private static func firstSplitView(in view: NSView) -> NSSplitView? {
        if let splitView = view as? NSSplitView { return splitView }
        for subview in view.subviews {
            if let found = firstSplitView(in: subview) { return found }
        }
        return nil
    }

    public func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .sidebarTrackingSeparator:
            guard let splitView = trackingSplitView else { return nil }
            return NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: splitView,
                dividerIndex: 0
            )

        case ItemID.navigation:
            let back = String(localized: "Back")
            let forward = String(localized: "Forward")
            let group = NSToolbarItemGroup(
                itemIdentifier: itemIdentifier,
                images: [
                    NSImage(systemSymbolName: "chevron.left", accessibilityDescription: back) ?? NSImage(),
                    NSImage(systemSymbolName: "chevron.right", accessibilityDescription: forward) ?? NSImage()
                ],
                selectionMode: .momentary,
                labels: [back, forward],
                target: self,
                action: #selector(navigationPressed(_:))
            )
            group.controlRepresentation = .expanded
            group.label = String(localized: "Back/Forward")
            group.paletteLabel = group.label
            group.isNavigational = true
            group.visibilityPriority = .high
            if group.subitems.count == 2 {
                group.subitems[0].toolTip = back
                group.subitems[1].toolTip = forward
                backItem = group.subitems[0]
                forwardItem = group.subitems[1]
            }
            navigationGroup = group
            syncNavigation()
            return group

        case ItemID.title:
            let label = NSTextField(labelWithString: model.title)
            label.font = .systemFont(ofSize: 15, weight: .bold)
            label.textColor = .labelColor
            label.lineBreakMode = .byTruncatingTail

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = label
            item.label = ""
            item.visibilityPriority = .high
            item.isNavigational = true
            titleLabel = label
            return item

        case ItemID.search:
            // Expanding search field; the trailing side has room only because the sort is a single button.
            let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
            item.searchField.delegate = self
            item.searchField.placeholderString = String(localized: "Search")
            item.searchField.stringValue = model.searchQuery
            item.preferredWidthForSearchField = 180
            item.resignsFirstResponderWithCancel = true
            item.label = String(localized: "Search")
            item.visibilityPriority = .high
            searchField = item.searchField
            searchItem = item
            setHidden(item, !Self.showsSearch(for: model.page))
            return item

        case ItemID.sort:
            // `NSMenuToolbarItem` gets press-and-hold and keyboard handling for free.
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.image = NSImage(
                systemSymbolName: "arrow.up.arrow.down",
                accessibilityDescription: String(localized: "Sort")
            )
            item.menu = makeSortMenu(selected: model.storeSort)
            item.showsIndicator = false
            item.label = String(localized: "Sort")
            item.toolTip = String(localized: "Sort")
            item.visibilityPriority = .high
            sortItem = item
            setHidden(item, model.page != .store)
            return item

        case ItemID.storeInstall:
            let button = NSButton(
                image: NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: String(localized: "Install from File…")) ?? NSImage(),
                target: self,
                action: #selector(storeInstallPressed(_:))
            )
            button.bezelStyle = .toolbar

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = button
            item.label = String(localized: "Install from File…")
            item.toolTip = String(localized: "Install from File…")
            item.visibilityPriority = .high
            storeInstallButton = button
            storeInstallItem = item
            setHidden(item, model.page != .store)
            return item

        case ItemID.refresh:
            let button = NSButton(
                image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: String(localized: "Refresh Catalog")) ?? NSImage(),
                target: self,
                action: #selector(refreshPressed(_:))
            )
            button.bezelStyle = .toolbar
            button.isEnabled = !model.isRefreshing

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = button
            item.label = String(localized: "Refresh Catalog")
            item.toolTip = String(localized: "Refresh Catalog")
            item.visibilityPriority = .high
            refreshButton = button
            refreshItem = item
            setHidden(item, model.page != .store)
            return item

        case ItemID.pageMenu:
            let button = NSButton(
                image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: String(localized: "More")) ?? NSImage(),
                target: self,
                action: #selector(pageMenuPressed(_:))
            )
            button.bezelStyle = .toolbar

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = button
            item.label = String(localized: "More")
            item.toolTip = String(localized: "More")
            item.visibilityPriority = .high
            pageMenuButton = button
            pageMenuItem = item
            setHidden(item, model.pageMenuItems.isEmpty)
            return item

        case ItemID.action:
            let button = NSButton(
                image: NSImage(systemSymbolName: "plus", accessibilityDescription: nil) ?? NSImage(),
                target: self,
                action: #selector(actionButtonPressed(_:))
            )
            button.bezelStyle = .toolbar

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = button
            item.label = String(localized: "Add")
            item.visibilityPriority = .high
            actionButton = button
            actionItem = item
            sync(page: model.page)
            return item

        default:
            return nil
        }
    }
}

/// The title bar's trailing accessory. An accessory's view is stretched to the title bar's
/// height, so the switch is positioned by hand and the host reports only its own width.
private final class TitlebarSwitchHost: NSView {
    let control = NSSwitch()

    private static let trailingInset: CGFloat = 14
    private static let leadingGap: CGFloat = 6

    private let controlSize: NSSize

    init() {
        control.controlSize = .regular
        control.sizeToFit()
        let fitted = control.fittingSize
        // Floor for a control that has not laid out yet (`NSSwitch` is 38x22 at regular size).
        controlSize = NSSize(width: max(fitted.width, 38), height: max(fitted.height, 22))
        super.init(frame: NSRect(origin: .zero, size: controlSize))
        control.setFrameSize(controlSize)
        autoresizesSubviews = false
        addSubview(control)
        setFrameSize(NSSize(width: intrinsicContentSize.width, height: controlSize.height))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var showsControl: Bool = true {
        didSet {
            guard showsControl != oldValue else { return }
            control.isHidden = !showsControl
            invalidateIntrinsicContentSize()
            setFrameSize(NSSize(width: intrinsicContentSize.width, height: frame.height))
            needsLayout = true
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: showsControl ? Self.leadingGap + controlSize.width + Self.trailingInset : 0,
            height: NSView.noIntrinsicMetric
        )
    }

    override func layout() {
        super.layout()
        control.setFrameOrigin(NSPoint(
            x: Self.leadingGap,
            y: ((bounds.height - controlSize.height) / 2).rounded()
        ))
    }

    /// Clicks belong to the control, not the host frame.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}
