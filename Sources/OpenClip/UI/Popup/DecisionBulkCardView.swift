// DecisionBulkCardView.swift
// OpenClip
//
// The Bulk decision card: pick the tool and whether the selection splits into rows or words, see
// how many items that makes, run it, watch the categories fill up, then copy one category or all
// of them. Rendered in the popup's content mode, in place of the bar.
import SwiftUI
import Core

struct DecisionBulkCardView: View {
    @ObservedObject var session: DecisionBulkSession
    let onDismiss: () -> Void

    private var isRunning: Bool { session.phase == .running }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)
            configuration
            Divider().opacity(0.5)
            results
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 380)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Bulk decision")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(itemCountText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// "42 items detected" — the count updates as the mode changes.
    private var itemCountText: String {
        let count = session.units.count
        if session.wasTruncated {
            return String(localized: "\(count) items detected (capped)")
        }
        return String(localized: "\(count) items detected")
    }

    // MARK: - Configuration

    private var configuration: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Decision")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                Picker("", selection: $session.toolID) {
                    ForEach(session.availableTools) { tool in
                        Text(tool.title).tag(tool.id)
                    }
                }
                .labelsHidden()
                .disabled(isRunning)
            }
            HStack {
                Text("Split by")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                Picker("", selection: $session.mode) {
                    ForEach(DecisionBulkSession.offeredModes, id: \.self) { mode in
                        Text(Self.modeTitle(mode)).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(isRunning)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    static func modeTitle(_ mode: DecisionBulkUnitKind) -> String {
        switch mode {
        case .row, .line: return String(localized: "Row")
        case .word: return String(localized: "Word")
        case .paragraph: return String(localized: "Paragraph")
        case .span: return String(localized: "Sentence")
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isRunning {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: session.progressFraction)
                        .progressViewStyle(.linear)
                    Text("Judging \(session.completed) of \(session.units.count)…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if session.phase != .idle {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(session.sections) { section in
                            sectionRow(section)
                        }
                    }
                }
                .frame(maxHeight: 190)
            } else if let error = session.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            } else {
                Text("Each item is judged on its own, then grouped by answer.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func sectionRow(_ section: DecisionBulkSession.Section) -> some View {
        HStack(spacing: 8) {
            Text(section.label)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(section.items.count)")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button {
                session.copyToPasteboard(session.copyText(for: section))
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(section.items.isEmpty)
            .opacity(section.items.isEmpty ? 0.3 : 1)
            .help(String(localized: "Copy the \(section.label) items"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tint(for: section.label))
        )
    }

    /// Yes/no categories reuse the inline outcome washes so the two surfaces read alike.
    private func tint(for label: String) -> Color {
        switch label {
        case DecisionBulkSession.yesLabel: return DecisionInlineState.yes.barTint ?? .clear
        case DecisionBulkSession.noLabel: return DecisionInlineState.no.barTint ?? .clear
        case DecisionBulkSession.unsureLabel: return DecisionInlineState.unsure.barTint ?? .clear
        default: return Color.primary.opacity(0.06)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if session.phase == .finished {
                Button(String(localized: "Copy All")) {
                    session.copyToPasteboard(session.copyAllText())
                }
                .disabled(session.sections.allSatisfy(\.items.isEmpty))
            }
            Spacer()
            Button(String(localized: "Close")) { onDismiss() }
            if isRunning {
                Button(String(localized: "Stop")) { session.cancel() }
            } else {
                Button(session.phase == .finished ? String(localized: "Run Again") : String(localized: "Run")) {
                    session.run()
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.units.isEmpty || session.tool == nil)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
