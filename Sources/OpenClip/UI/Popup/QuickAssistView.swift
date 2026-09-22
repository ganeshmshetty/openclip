// QuickAssistView.swift
// OpenClip
//
// Contents of the floating Quick Assist window: a compact header you can drag by, then one row per
// Decision tool that is marked for Quick Assist, each showing its current answer for the text in
// the focused field.
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

/// Everything the window renders: the rows plus an optional status line (no tools configured,
/// waiting for typing, provider unavailable).
public struct QuickAssistViewModel: Equatable, Sendable {
    public var rows: [QuickAssistRow]
    public var statusLine: String?

    public init(rows: [QuickAssistRow], statusLine: String?) {
        self.rows = rows
        self.statusLine = statusLine
    }
}

struct QuickAssistView: View {
    static let panelWidth: CGFloat = 248

    let model: QuickAssistViewModel
    let onClose: () -> Void

    @State private var isHoveringClose = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let status = model.statusLine {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
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
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isHoveringClose ? Color.primary : Color.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringClose = $0 }
            .help(String(localized: "Turn off Quick Assist"))
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, model.rows.isEmpty && model.statusLine == nil ? 10 : 6)
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
