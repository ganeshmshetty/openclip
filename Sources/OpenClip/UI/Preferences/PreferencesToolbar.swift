// PreferencesToolbar.swift
// OpenClip
//
// The settings window's toolbar, owned by AppKit rather than by SwiftUI.
//
// SwiftUI builds the window's NSToolbar from whatever `.toolbar` publishes and
// tears it down again when a pane publishes nothing, and every rebuild makes
// the title bar re-measure — which is what kept knocking the traffic lights out
// of the full-height sidebar on the way between tabs. Here the toolbar is
// created once with a fixed set of items and only their contents change, so the
// title bar's geometry is the same on every pane. It also gets the store a real
// AppKit search field, which is what a SwiftUI toolbar item could not give it.
//
// The Store's All/Popular/New filter is deliberately *not* here: with it, the
// expanding search field, the ellipsis and the pane name all competing for one
// row, expanding the search pushed the other two into the overflow menu. The
// filter belongs with the list it filters anyway, so it lives in the page.
//
// Leading everything is the back/forward pair System Settings has: an
// `NSToolbarItemGroup` wired to the router's history, so leaving any page —
// an action's editor, the icon chooser, an extension — is the same gesture.
// Trailing everything, on that same line, is what the page on screen is *about*:
// an ellipsis menu of what can be done to it as a whole (view its README, show
// its folder, uninstall it) and its on/off switch. Both belong to the subject
// rather than to a row, which is why System Settings puts them here too.
//
// The switch is a *title bar accessory*, not a toolbar item: macOS 26 draws a
// glass background behind toolbar items and merges adjacent ones into one
// capsule, so a switch next to the ellipsis came out sharing a pill with it,
// with a border drawn tight around the switch. An accessory sits outside that
// treatment, so the switch reads as a bare control at the trailing edge and the
// ellipsis keeps the ordinary toolbar-button background to its left.
import AppKit
import Combine
import Core

public enum PreferencesToolbarAction: Sendable {
    case newGroup
    case addCustomAction
    case addApplication
    case addAIAction
    /// The trailing switch was moved. The window decides what it means for the page on screen.
    case setPageToggle(Bool)
    /// A pick from the trailing ellipsis menu, by `SettingsToolbarMenuItem.id`.
    case pageMenuItem(String)
}

/// The bridge between the SwiftUI panes and the AppKit toolbar.
@MainActor
public final class PreferencesToolbarModel: ObservableObject {
    /// The page on screen. Decides which controls the toolbar shows.
    @Published public var page: SettingsPage = .general
    /// The page's title, resolved by the window (an action's page is titled after the action).
    @Published public var title: String = SettingsPage.general.staticTitle ?? ""
    /// The subject's on/off switch, trailing in the toolbar. `nil` hides it.
    @Published public var pageToggle: SettingsToolbarToggle?
    /// What the trailing ellipsis menu offers. Empty hides it.
    @Published public var pageMenuItems: [SettingsToolbarMenuItem] = []
    @Published public var searchQuery: String = ""
    @Published public var isRefreshing: Bool = false

    /// Toolbar button presses, forwarded to whichever pane acts on them.
    public let actions = PassthroughSubject<PreferencesToolbarAction, Never>()

    public init() {}
}

@MainActor
public final class PreferencesToolbarController: NSObject, NSToolbarDelegate, NSSearchFieldDelegate, NSToolbarItemValidation {
    private enum ItemID {
        /// Back and forward through the router's history, as one grouped control.
        static let navigation = NSToolbarItem.Identifier("openclip.preferences.navigation")
        /// The pane's name as a toolbar item rather than the window's own title:
        /// a unified toolbar reserves a title area of its own choosing, which
        /// left a wide gap between "Store" and the first control.
        static let title = NSToolbarItem.Identifier("openclip.preferences.title")
        /// The page subject's ellipsis menu, trailing. Its switch is a title bar accessory.
        static let pageMenu = NSToolbarItem.Identifier("openclip.preferences.pageMenu")
        static let search = NSToolbarItem.Identifier("openclip.preferences.search")
        static let action = NSToolbarItem.Identifier("openclip.preferences.action")
    }

    private let model: PreferencesToolbarModel
    private let router: SettingsRouter
    private var cancellables: Set<AnyCancellable> = []
    /// Set by whoever opens the window. The pane name is drawn by the title item
    /// below, not by the window: `titleVisibility = .hidden` is ignored by a
    /// unified toolbar on macOS 26, so a window with a title ended up showing the
    /// pane's name twice.
    public weak var window: NSWindow? {
        didSet {
            // Once the content view has a split view the toolbar can be told
            // where the sidebar ends.
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
    private weak var searchField: NSSearchField?
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
                self?.actionButton?.isEnabled = !(isRefreshing && self?.model.page == .store)
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

        // `objectWillChange` fires before the router's state changes; the next turn of the run
        // loop sees the new history.
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
        setHidden(searchItem, page != .store)

        switch page {
        case .customize:
            configureActionButton(symbol: "plus", tooltip: String(localized: "New Group"))
        case .customActions:
            configureActionButton(symbol: "plus", tooltip: String(localized: "Add Custom Action"))
        case .appRules:
            configureActionButton(symbol: "plus", tooltip: String(localized: "Add Application"))
        case .ai:
            configureActionButton(symbol: "plus", tooltip: String(localized: "Add Custom AI Action"))
        default:
            setHidden(actionItem, true)
        }
    }

    /// Puts the switch in the title bar, to the right of the toolbar's own items.
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

    /// Mirrors the page's switch onto the control, and gives back the space it occupies on a page
    /// that has no switch. A switch that is off *and* unmovable is a package the trust gate holds
    /// back, which the page explains in words underneath.
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

    /// Hides the whole item, not just its control: an item left in place still
    /// gets its own glass backing drawn, which showed up as an empty pane of
    /// material on the tabs with no toolbar controls.
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
        // Items say for themselves whether they can run; menu validation would otherwise enable
        // anything with a target and undo `isEnabled`.
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

    @objc private func pageMenuItemPressed(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        model.actions.send(.pageMenuItem(id))
    }

    @objc private func actionButtonPressed(_ sender: NSButton) {
        switch model.page {
        case .customize:
            model.actions.send(.newGroup)
        case .customActions:
            model.actions.send(.addCustomAction)
        case .appRules:
            model.actions.send(.addApplication)
        case .ai:
            model.actions.send(.addAIAction)
        default:
            break
        }
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
        // Back/forward first, then the pane name, the store's filter beside it, and everything
        // else pinned right: the pane's button, with the search field last against the window
        // edge. Centring the filter with a leading flexible space spent the width twice and
        // pushed the search field into the overflow menu at the window's minimum size.
        [
            ItemID.navigation, ItemID.title, .flexibleSpace,
            ItemID.action, ItemID.search, ItemID.pageMenu
        ]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator] + toolbarDefaultItemIdentifiers(toolbar)
    }

    /// Without this the toolbar has no idea where the sidebar ends, so it lines
    /// its items up against the right edge instead of the content area's left
    /// one. The separator tracks the split view's first divider, which is what
    /// gives the leading items something to start from.
    private func installSidebarTrackingSeparator(retriesLeft: Int) {
        guard let toolbar = window?.toolbar,
              !toolbar.items.contains(where: { $0.itemIdentifier == .sidebarTrackingSeparator }) else { return }
        // SwiftUI builds NavigationSplitView's NSSplitView on its first layout
        // pass, which is later than the window gaining a toolbar. One shot at
        // this found nothing and left the toolbar with no leading anchor, so
        // every item ended up packed against the right edge; keep looking for a
        // few run loop turns instead.
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
            // Navigational, like a back button: it is what pins the group to the
            // leading edge of the content area.
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
            // Navigational, like a back button: it is what pins the item to the
            // leading edge of the content area. Without it the toolbar re-lays
            // itself out on the first pane change and packs every item against
            // the window's right edge, flexible space and all.
            item.isNavigational = true
            titleLabel = label
            return item

        case ItemID.search:
            // `NSSearchToolbarItem`: a magnifier that expands into a field, the way Mail and
            // Notes search. It used to be a plain always-wide field because expanding it pushed
            // the Store's filter into the overflow menu — the trailing side carried a button and
            // a 160pt field then. It carries the magnifier and the ellipsis now, so there is room.
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

/// The title bar's trailing accessory: an `NSSwitch` parked at its own size.
///
/// It is not a toolbar item on purpose — see the note at the top of this file — and it is not
/// handed over bare either: an accessory's view is stretched to the title bar's height, and
/// `NSSwitch` draws itself into whatever bounds it is given, so the control is positioned by hand
/// and the host reports only the width the switch and its margins need. A page with no switch
/// reports no width at all, so the toolbar gets the room back.
private final class TitlebarSwitchHost: NSView {
    let control = NSSwitch()

    /// Clear of the window's trailing edge, and not crowding the ellipsis on the other side.
    private static let trailingInset: CGFloat = 14
    private static let leadingGap: CGFloat = 6

    private let controlSize: NSSize

    init() {
        control.controlSize = .regular
        control.sizeToFit()
        let fitted = control.fittingSize
        // `NSSwitch` answers 38x22 at the regular control size; the constants are only a floor for
        // a control that has not laid out yet.
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

    /// Centred by hand: the accessory fills the height it is given, and the switch must not.
    override func layout() {
        super.layout()
        control.setFrameOrigin(NSPoint(
            x: Self.leadingGap,
            y: ((bounds.height - controlSize.height) / 2).rounded()
        ))
    }

    /// The host is only a frame around the control; clicks belong to the control itself.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}
