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
// Leading everything is the back/forward pair System Settings has: an
// `NSToolbarItemGroup` wired to the router's history, so leaving any page —
// an action's editor, the icon chooser, an extension — is the same gesture.
import AppKit
import Combine
import Core

public enum PreferencesToolbarAction: Sendable {
    case newGroup
    case addCustomAction
    case installExtension
    case addApplication
    case refresh
    case addAIAction
}

/// The bridge between the SwiftUI panes and the AppKit toolbar.
@MainActor
public final class PreferencesToolbarModel: ObservableObject {
    /// The page on screen. Decides which controls the toolbar shows.
    @Published public var page: SettingsPage = .general
    /// The page's title, resolved by the window (an action's page is titled after the action).
    @Published public var title: String = SettingsPage.general.staticTitle ?? ""
    @Published public var storeFilter: StoreFilter = .all
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
        static let filter = NSToolbarItem.Identifier("openclip.preferences.filter")
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
            window?.setAccessibilityTitle(model.title)
        }
    }

    private weak var trackingSplitView: NSSplitView?

    private weak var navigationGroup: NSToolbarItemGroup?
    private weak var backItem: NSToolbarItem?
    private weak var forwardItem: NSToolbarItem?
    private weak var titleLabel: NSTextField?
    private weak var filterItem: NSToolbarItem?
    private weak var searchItem: NSToolbarItem?
    private weak var actionItem: NSToolbarItem?
    private weak var filterControl: NSSegmentedControl?
    private weak var searchField: NSSearchField?
    private weak var actionButton: NSButton?

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

        model.$storeFilter
            .sink { [weak self] filter in
                self?.filterControl?.selectedSegment = StoreFilter.allCases.firstIndex(of: filter) ?? 0
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
        let showsStoreControls = (page == .store)
        setHidden(filterItem, !showsStoreControls)
        setHidden(searchItem, !showsStoreControls)

        switch page {
        case .actions:
            configureActionButton(symbol: "plus", tooltip: String(localized: "Add Action or Group"))
        case .appRules:
            configureActionButton(symbol: "plus", tooltip: String(localized: "Add Application"))
        case .store:
            configureActionButton(symbol: "arrow.clockwise", tooltip: String(localized: "Refresh Catalog"))
        case .ai:
            configureActionButton(symbol: "plus", tooltip: String(localized: "Add Custom AI Action"))
        default:
            setHidden(actionItem, true)
        }
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

    @objc private func actionButtonPressed(_ sender: NSButton) {
        switch model.page {
        case .actions:
            // The Actions page's button offers three ways to add, so it drops a
            // menu rather than firing one action.
            let menu = NSMenu()
            menu.addItem(menuItem(String(localized: "New Group"), symbol: "folder.badge.plus", action: #selector(menuNewGroup)))
            menu.addItem(menuItem(String(localized: "Add Custom Action"), symbol: "plus.circle", action: #selector(menuAddCustomAction)))
            menu.addItem(menuItem(String(localized: "Install Extension…"), symbol: "square.and.arrow.down", action: #selector(menuInstallExtension)))
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
        case .appRules:
            model.actions.send(.addApplication)
        case .store:
            model.actions.send(.refresh)
        case .ai:
            model.actions.send(.addAIAction)
        default:
            break
        }
    }

    private func menuItem(_ title: String, symbol: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    @objc private func menuNewGroup() { model.actions.send(.newGroup) }
    @objc private func menuAddCustomAction() { model.actions.send(.addCustomAction) }
    @objc private func menuInstallExtension() { model.actions.send(.installExtension) }

    @objc private func filterChanged(_ sender: NSSegmentedControl) {
        let filters = StoreFilter.allCases
        guard filters.indices.contains(sender.selectedSegment) else { return }
        if !model.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            model.searchQuery = ""
        }
        model.storeFilter = filters[sender.selectedSegment]
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
        [ItemID.navigation, ItemID.title, ItemID.filter, .flexibleSpace, ItemID.action, ItemID.search]
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

        case ItemID.filter:
            let control = NSSegmentedControl(
                labels: StoreFilter.allCases.map(\.title),
                trackingMode: .selectOne,
                target: self,
                action: #selector(filterChanged(_:))
            )
            control.segmentStyle = .automatic
            // Each segment as wide as its own label, sized into a real frame: an
            // equal-width control spends more room than the labels need, and the
            // toolbar answers a set of items too wide for the window by dropping
            // the trailing ones into the overflow menu. Constraints are no good
            // here either — a constrained view has no size for the toolbar to
            // measure.
            control.segmentDistribution = .fit
            control.sizeToFit()
            control.selectedSegment = StoreFilter.allCases.firstIndex(of: model.storeFilter) ?? 0

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = control
            item.label = String(localized: "Filter")
            item.visibilityPriority = .high
            // Leading edge, beside the pane name — see the title item above.
            item.isNavigational = true
            filterControl = control
            filterItem = item
            setHidden(item, model.page != .store)
            return item

        case ItemID.search:
            // A plain item around an NSSearchField rather than NSSearchToolbarItem:
            // the system item collapses to a magnifying glass at this window's
            // width and, on the click that expands it again, takes enough room to
            // push the filter into the overflow menu — so the field opened in the
            // middle of the toolbar with the segments gone. A field that is always
            // its full width never moves.
            let field = NSSearchField(frame: NSRect(x: 0, y: 0, width: 160, height: 28))
            field.delegate = self
            field.bezelStyle = .roundedBezel
            field.placeholderString = String(localized: "Search")
            field.stringValue = model.searchQuery

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = field
            item.label = String(localized: "Search")
            item.visibilityPriority = .high
            searchField = field
            searchItem = item
            setHidden(item, model.page != .store)
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
