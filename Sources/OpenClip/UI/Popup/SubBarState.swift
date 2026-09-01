// SubBarState.swift
// OpenClip
//
// Data model for the horizontal group sub-bar: tracks which group is currently expanded,
// whether it was pinned by click or opened transiently by hover, and the parent button's
// frame for horizontal centering. Uses IDs (not `any Action` existentials) so the struct
// can conform to Equatable + Sendable under Swift 6 strict concurrency.
import Foundation
import CoreGraphics

/// The currently expanded group sub-bar state. Nil when no sub-bar is visible.
public struct ActiveSubGroupState: Equatable, Sendable {
    /// The `id` of the parent group action whose sub-bar is open.
    public let groupID: String
    /// Index of the parent action in `displayActions` (for highlight tracking).
    public let parentIndex: Int
    /// IDs of the resolved sub-actions to display in the sub-bar in their resolved order.
    public let subActionIDs: [String]
    /// `true` when opened by click (stays open until toggled); `false` for transient hover preview.
    public let isPinned: Bool
    /// The parent button's frame in `popupHoverSpace` coordinates, used for horizontal alignment.
    public let parentButtonFrame: CGRect

    public init(
        groupID: String,
        parentIndex: Int,
        subActionIDs: [String],
        isPinned: Bool,
        parentButtonFrame: CGRect
    ) {
        self.groupID = groupID
        self.parentIndex = parentIndex
        self.subActionIDs = subActionIDs
        self.isPinned = isPinned
        self.parentButtonFrame = parentButtonFrame
    }

    /// Returns a copy with `isPinned` set to `true`.
    public func pinned() -> ActiveSubGroupState {
        ActiveSubGroupState(
            groupID: groupID,
            parentIndex: parentIndex,
            subActionIDs: subActionIDs,
            isPinned: true,
            parentButtonFrame: parentButtonFrame
        )
    }
}
