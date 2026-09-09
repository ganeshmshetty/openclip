// PreferencesToolbar.swift
// OpenClip
//
// The preferences window's toolbar, owned by AppKit rather than by SwiftUI.
//
// SwiftUI builds the window's NSToolbar from whatever `.toolbar` publishes and
// tears it down again when a pane publishes nothing, and every rebuild makes
// the title bar re-measure — which is what kept knocking the traffic lights out
// of the full-height sidebar on the way between tabs. Here the toolbar is
// created once with a fixed set of items and only their contents change, so the
// title bar's geometry is the same on every pane. It also gets the store a real
// NSSearchToolbarItem, which is the system search field a SwiftUI toolbar item
// could not give it.
import AppKit
import Combine

public enum PreferencesToolbarAction: Sendable {
    case newGroup
    case addCustomAction
    case installExtension
    case addApplication
    case refresh
}

/// The bridge between the SwiftUI panes and the AppKit toolbar.
@MainActor
public final class PreferencesToolbarModel: ObservableObject {
    @Published public var tab: PreferenceTab = .general
    @Published public var storeFilter: StoreFilter = .all
    @Published public var searchQuery: String = ""
    @Published public var isRefreshing: Bool = false

    /// Toolbar button presses, forwarded to whichever pane acts on them.
    public let actions = PassthroughSubject<PreferencesToolbarAction, Never>()

    public init() {}
}

@MainActor
public final class PreferencesToolbarController: NSObject, NSToolbarDelegate, NSSearchFieldDelegate {
    private enum ItemID {
        /// Filter and search share one item. As two, the toolbar was free to
        /// decide only one of them fit and push the other into the overflow
        /// menu; as one view they are measured, shown and hidden together.
        static let storeControls = NSToolbarItem.Identifier("openclip.preferences.storeControls")
        static let action = NSToolbarItem.Identifier("openclip.preferences.action")
    }

    private let model: PreferencesToolbarModel
    private var cancellables: Set<AnyCancellable> = []
    /// Set by whoever opens the window, so the title can follow the pane.
    public weak var window: NSWindow? {
        didSet { window?.title = model.tab.windowTitle }
    }

    private weak var storeControlsItem: NSToolbarItem?
    private weak var actionItem: NSToolbarItem?
    private weak var filterControl: NSSegmentedControl?
    private weak var searchField: NSSearchField?
    private weak var actionButton: NSButton?

    public init(model: PreferencesToolbarModel) {
        self.model = model
        super.init()

        model.$tab
            .sink { [weak self] tab in self?.sync(tab: tab) }
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
                self?.actionButton?.isEnabled = !(isRefreshing && self?.model.tab == .store)
            }
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

    // MARK: - Item contents per tab

    private func sync(tab: PreferenceTab) {
        window?.title = tab.windowTitle
        setHidden(storeControlsItem, tab != .store)

        switch tab {
        case .actions:
            configureActionButton(symbol: "plus", tooltip: String(localized: "Add Action or Group"))
        case .appRules:
            configureActionButton(symbol: "plus", tooltip: String(localized: "Add Application"))
        case .store:
            configureActionButton(symbol: "arrow.clockwise", tooltip: String(localized: "Refresh Catalog"))
        default:
            setHidden(actionItem, true)
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
        button.isEnabled = true
        setHidden(actionItem, false)
        actionItem?.toolTip = tooltip
    }

    // MARK: - Actions

    @objc private func actionButtonPressed(_ sender: NSButton) {
        switch model.tab {
        case .actions:
            // The Actions tab's button offers three ways to add, so it drops a
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

    // MARK: - NSToolbarDelegate

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // Filter hard left of the content area, search hard right, one flexible
        // space between them. Centring the filter with a leading flexible space
        // spent the width twice and pushed the search field into the overflow
        // menu at the window's minimum size.
        [ItemID.storeControls, .flexibleSpace, ItemID.action]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    public func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case ItemID.storeControls:
            let control = NSSegmentedControl(
                labels: StoreFilter.allCases.map(\.title),
                trackingMode: .selectOne,
                target: self,
                action: #selector(filterChanged(_:))
            )
            control.segmentStyle = .automatic
            control.segmentDistribution = .fillEqually
            for index in 0..<control.segmentCount {
                control.setWidth(66, forSegment: index)
            }
            control.selectedSegment = StoreFilter.allCases.firstIndex(of: model.storeFilter) ?? 0

            let field = NSSearchField()
            field.delegate = self
            field.placeholderString = String(localized: "Search extensions")
            field.stringValue = model.searchQuery
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 170).isActive = true

            let stack = NSStackView(views: [control, field])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 10

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = stack
            item.label = String(localized: "Extensions")
            item.visibilityPriority = .high
            filterControl = control
            searchField = field
            storeControlsItem = item
            setHidden(item, model.tab != .store)
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
            sync(tab: model.tab)
            return item

        default:
            return nil
        }
    }
}
