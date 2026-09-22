// QuickAssistView.swift
// OpenClip
//
// Contents of the floating Quick Assist window: a compact header you can drag by, the text it is
// currently judging (with buttons to add the current selection to it or clear it), then one row per
// Decision tool that is marked for Quick Assist.
import SwiftUI
import Core

/// One tool's line in the Quick Assist window.
public struct QuickAssistRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var state: DecisionInlineState

    public init(id: String, title: String, state: DecisionInlineState) {
        self.id = id
        self.title = title
        self.state = state
    }
}

/// Everything the window renders: the text being judged, the rows, and an optional status line
/// (no tools configured, waiting for typing, provider unavailable).
public struct QuickAssistViewModel: Equatable, Sendable {
    public var context: String
    public var rows: [QuickAssistRow]
    public var statusLine: String?

    public init(context: String = "", rows: [QuickAssistRow], statusLine: String?) {
        self.context = context
        self.rows = rows
        self.statusLine = statusLine
    }
}

struct QuickAssistView: View {
    static let panelWidth: CGFloat = 268

    let model: QuickAssistViewModel
    let onClose: () -> Void
    var onAddSelection: () -> Void = {}
    var onClearContext: () -> Void = {}

    @State private var hoveredButton: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            context
            if let status = model.statusLine {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            if !model.rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        QuickAssistRowView(row: row)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .frame(width: Self.panelWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .padding(8)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: Constants.defaultDecisionIconSymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Quick Assist")
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 4)
            iconButton("plus", id: "add", help: String(localized: "Add the selected text to the context"), action: onAddSelection)
            iconButton("eraser", id: "clear", help: String(localized: "Clear the context"), action: onClearContext)
                .disabled(model.context.isEmpty)
                .opacity(model.context.isEmpty ? 0.35 : 1)
            iconButton("xmark", id: "close", help: String(localized: "Turn off Quick Assist"), action: onClose)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    /// The text being judged, so it is never a mystery what the answers below refer to.
    private var context: some View {
        Text(model.context.isEmpty ? String(localized: "Nothing yet") : model.context)
            .font(.system(size: 11))
            .foregroundStyle(model.context.isEmpty ? .tertiary : .secondary)
            .lineLimit(3)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .animation(.easeOut(duration: 0.15), value: model.context)
    }

    private func iconButton(_ symbol: String, id: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(hoveredButton == id ? Color.primary : Color.secondary)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredButton = $0 ? id : nil }
        .help(help)
    }
}

private struct QuickAssistRowView: View {
    let row: QuickAssistRow

    var body: some View {
        HStack(spacing: 8) {
            Text(row.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            outcome
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(row.state.barTint ?? .clear)
                .padding(.horizontal, 6)
        )
        .animation(.easeOut(duration: 0.15), value: row.state)
    }

    @ViewBuilder
    private var outcome: some View {
        switch row.state {
        case .running:
            ToastSpinnerView(color: .secondary, scale: 0.85)
        case .answer(let label):
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 110, alignment: .trailing)
                .foregroundStyle(.primary)
        default:
            if let symbol = row.state.symbolName {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(row.state.glyphColor)
            }
        }
    }
}
