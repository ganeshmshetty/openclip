// SettingsNavigator.swift
// OpenClip
//
// Push/pop navigation *inside* the Actions preferences pane, replacing the floating editors.
//
// Every sub-setting used to open a window on top of the settings window: the row gear opened an
// `.applicationDefined` NSPopover, the icon picker opened a popover on top of that popover, and
// editing an AI preset opened a sheet that dimmed all of it. Nothing said where you were or how to
// get back, and closing the wrong layer first was easy.
//
// System Settings answers the same problem by drilling down in place — Privacy & Security ▸
// Accessibility, Notifications ▸ an app — with a back chevron and the title of where you are. This
// is that: one column, a stack of pages, one way back.
//
// Pages already on the stack stay mounted (offset out of view) rather than being torn down, so a
// page's in-progress edits survive pushing the icon picker on top of it and popping back.

import SwiftUI

// MARK: - Pages

/// A page in the Actions pane's navigation stack. The root (the action list) is not a case — it is
/// what an empty stack shows.
enum SettingsPage: Hashable, Identifiable {
    case action(id: String)
    case group(id: String)
    /// Icon chooser. The symbol it writes to travels out of band in `SettingsNavigator.iconTarget`,
    /// because a `Binding` is not `Hashable` and the page that owns the draft must stay mounted.
    case iconPicker(title: String)
    case ai
    case aiActions
    case aiPreset(id: String)
    case aiNewPreset

    var id: String {
        switch self {
        case .action(let id): return "action:\(id)"
        case .group(let id): return "group:\(id)"
        case .iconPicker: return "iconPicker"
        case .ai: return "ai"
        case .aiActions: return "aiActions"
        case .aiPreset(let id): return "aiPreset:\(id)"
        case .aiNewPreset: return "aiNewPreset"
        }
    }

    var title: String {
        switch self {
        case .action: return String(localized: "Configure Action")
        case .group: return String(localized: "Edit Group")
        case .iconPicker(let title): return title
        case .ai: return String(localized: "AI Tools")
        case .aiActions: return String(localized: "AI Actions")
        case .aiPreset: return String(localized: "Edit AI Action")
        case .aiNewPreset: return String(localized: "Add Custom AI Action")
        }
    }
}

// MARK: - Navigator

/// The Actions pane's navigation stack.
///
/// A shared object rather than tab-local state because the rows that push onto it are hosted in an
/// `NSOutlineView`, which rebuilds its cell views on every model change and so cannot own the
/// "where am I" state.
@MainActor
final class SettingsNavigator: ObservableObject {
    static let shared = SettingsNavigator()

    @Published private(set) var path: [SettingsPage] = []

    /// Where the icon picker writes. Held here, outside the page enum, so the page that owns the
    /// draft symbol keeps owning it while the picker is on top.
    private(set) var iconTarget: Binding<String>?

    private init() {}

    func push(_ page: SettingsPage) {
        withAnimation(Self.transition) {
            path.append(page)
        }
    }

    func pushIconPicker(title: String, writingTo binding: Binding<String>) {
        iconTarget = binding
        push(.iconPicker(title: title))
    }

    func pop() {
        guard !path.isEmpty else { return }
        withAnimation(Self.transition) {
            let removed = path.removeLast()
            if case .iconPicker = removed { iconTarget = nil }
        }
    }

    /// Returns to the root, e.g. when the pane is left or the action being edited disappears.
    func popToRoot() {
        guard !path.isEmpty else { return }
        withAnimation(Self.transition) {
            path.removeAll()
            iconTarget = nil
        }
    }

    static let transition: Animation = .easeInOut(duration: 0.22)
}

// MARK: - Stack container

/// Hosts `root` and the navigator's pages in one column.
///
/// Pages are drawn in a `ZStack` with every level kept mounted — the level below is pushed slightly
/// left and faded out the way a navigation controller parallaxes it, but it is never removed, so
/// its `@State` (an editor's unsaved draft) survives the round trip.
@MainActor
struct SettingsNavigationStack<Root: View, PageContent: View>: View {
    @ObservedObject var navigator: SettingsNavigator
    @ViewBuilder let root: () -> Root
    @ViewBuilder let page: (SettingsPage) -> PageContent

    var body: some View {
        ZStack(alignment: .top) {
            level(index: -1) { root() }

            ForEach(Array(navigator.path.enumerated()), id: \.element.id) { index, page in
                level(index: index) {
                    VStack(spacing: 0) {
                        SettingsPageHeader(title: page.title) { navigator.pop() }
                        Divider()
                        self.page(page)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
        .clipped()
    }

    /// A level of the stack. `index` is its position in `path`; `-1` is the root.
    @ViewBuilder
    private func level<Content: View>(index: Int, @ViewBuilder content: () -> Content) -> some View {
        let isTop = index == navigator.path.count - 1
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(x: isTop ? 0 : -40)
            .opacity(isTop ? 1 : 0)
            .allowsHitTesting(isTop)
            .accessibilityHidden(!isTop)
    }
}

// MARK: - Page header

/// Back chevron + title, the drill-down's only chrome. Matches the way System Settings labels a
/// pushed pane, and gives the page a keyboard route back (Escape / ⌘[).
struct SettingsPageHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 13))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel(String(localized: "Back"))

            Spacer(minLength: 8)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            // Balances the back button so the title stays optically centred.
            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                Text("Back")
                    .font(.system(size: 13))
            }
            .hidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
