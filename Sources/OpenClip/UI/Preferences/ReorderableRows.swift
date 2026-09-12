// ReorderableRows.swift
// OpenClip
//
// A list whose rows are put in order by dragging them, with the blue insertion bar drawn in the
// gap the drag is over.
//
// It is the settings window's stand-in for the Customize outline, which is an `NSOutlineView` and
// cannot be embedded in a form. The gesture and the rule are deliberately the same: the gap a drag
// is over is the number of rows whose midpoint it has passed, and the bar is drawn on a row edge,
// never across a row. Rows drop *between* rows only — dropping one onto another means something in
// the Customize outline (it makes a group) and means nothing here.

import SwiftUI
import UniformTypeIdentifiers

/// Row frames, keyed by row id, in the list's own coordinate space.
private struct ReorderableRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Drop handling for the list. A `DropDelegate` rather than `dropDestination` because only this
/// API reports the drag position *continuously*, which is what the insertion bar needs to follow
/// the cursor between rows.
private struct ReorderableDropDelegate: DropDelegate {
    let isDraggingActive: () -> Bool
    let gapForLocation: (CGPoint) -> Int
    let onGapChanged: (Int?) -> Void
    let onDrop: (Int) -> Bool

    func dropEntered(info: DropInfo) {
        guard isDraggingActive() else { return }
        onGapChanged(gapForLocation(info.location))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isDraggingActive() else { return nil }
        onGapChanged(gapForLocation(info.location))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        onGapChanged(nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard isDraggingActive() else { return false }
        return onDrop(gapForLocation(info.location))
    }
}

@MainActor
struct ReorderableRows<Row: View>: View {
    /// The rows, in the order they are shown.
    let ids: [String]
    /// What is shown while a row is being dragged.
    let dragPreviewTitle: (String) -> String
    /// The dragged row and the gap it was dropped into: 0 is above the first row, `ids.count` is
    /// below the last.
    let onMove: (String, Int) -> Void
    /// How far the separators between rows are inset, to match the list they are drawn in.
    var dividerInset: CGFloat = 0
    @ViewBuilder let row: (String) -> Row

    @State private var rowFrames: [String: CGRect] = [:]
    @State private var insertionGap: Int?
    /// The row being dragged, captured at drag start so the drop resolves synchronously.
    @State private var draggingID: String?

    private static var coordinateSpace: String { "reorderableRows" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ids, id: \.self) { id in
                row(id)
                    // The row itself is the drag handle — no grip glyph, matching the outline.
                    .background(frameReader(for: id))
                    .onDrag {
                        draggingID = id
                        return NSItemProvider(object: id as NSString)
                    } preview: {
                        Text(dragPreviewTitle(id))
                            .font(.system(size: 12, weight: .medium))
                            .padding(6)
                    }

                if id != ids.last {
                    Divider()
                        .padding(.horizontal, dividerInset)
                }
            }
        }
        .coordinateSpace(name: Self.coordinateSpace)
        .onPreferenceChange(ReorderableRowFramePreferenceKey.self) { frames in
            MainActor.assumeIsolated { rowFrames = frames }
        }
        .overlay(alignment: .topLeading) { insertionBar }
        .onDrop(of: [.text], delegate: ReorderableDropDelegate(
            isDraggingActive: { draggingID != nil },
            gapForLocation: { location in RowReordering.insertionGap(atY: location.y, rowFrames: orderedFrames) },
            onGapChanged: { gap in insertionGap = gap },
            onDrop: { gap in
                defer {
                    insertionGap = nil
                    draggingID = nil
                }
                guard let draggingID else { return false }
                onMove(draggingID, gap)
                return true
            }
        ))
    }

    /// Reports a row's frame in the list's coordinate space, drawn as a clear background so it
    /// never affects layout.
    private func frameReader(for id: String) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: ReorderableRowFramePreferenceKey.self,
                value: [id: geo.frame(in: .named(Self.coordinateSpace))]
            )
        }
    }

    /// Row frames in list order; a row that has not reported its frame yet is skipped.
    private var orderedFrames: [CGRect] {
        ids.compactMap { rowFrames[$0] }
    }

    @ViewBuilder
    private var insertionBar: some View {
        if let insertionGap, let y = RowReordering.insertionY(forGap: insertionGap, rowFrames: orderedFrames) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
                .frame(maxWidth: .infinity)
                .offset(y: y - 1)
                .allowsHitTesting(false)
        }
    }
}

/// Where a drag lands, as pure arithmetic. Kept off `ReorderableRows` so neither a caller nor a
/// test has to name that view's generic row type to ask.
enum RowReordering {
    /// The gap a drag at `y` is over: every row whose midpoint it has passed counts, so 0 is above
    /// the first row and `rowFrames.count` is below the last — the rule AppKit's insertion bar
    /// follows in the Customize outline.
    static func insertionGap(atY y: CGFloat, rowFrames: [CGRect]) -> Int {
        rowFrames.filter { y > $0.midY }.count
    }

    /// Where the bar is drawn: the top edge of the row the gap precedes, or the bottom edge of the
    /// last row for the trailing gap. Nil when there are no rows to sit between.
    static func insertionY(forGap gap: Int, rowFrames: [CGRect]) -> CGFloat? {
        guard let first = rowFrames.first, let last = rowFrames.last else { return nil }
        if gap <= 0 { return first.minY }
        if gap >= rowFrames.count { return last.maxY }
        return rowFrames[gap].minY
    }

    /// `ids` with `id` moved into `gap`. Gap indices are read against the list *before* the row is
    /// lifted out, which is what `move(fromOffsets:toOffset:)` expects.
    static func reordering(_ ids: [String], moving id: String, toGap gap: Int) -> [String] {
        guard let source = ids.firstIndex(of: id) else { return ids }
        var reordered = ids
        reordered.move(fromOffsets: IndexSet(integer: source), toOffset: max(0, min(gap, ids.count)))
        return reordered
    }
}
