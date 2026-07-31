import Foundation
import CoreGraphics
import Core
import AppKit

public struct PopupPositioner: Sendable {
    /// Calculate popup window frame given a SelectionContext or explicit parameters.
    public static func calculateFrame(for context: SelectionContext, popupSize: CGSize, in screenBounds: CGRect) -> CGRect {
        if let bounds = context.selectionBounds, !bounds.isEmpty {
            return calculateFrame(forSelectionBounds: bounds, popupSize: popupSize, in: screenBounds)
        }
        return calculateFrame(for: context.cursorPosition, popupSize: popupSize, in: screenBounds)
    }

    public static func calculateFrame(forSelectionBounds bounds: CGRect, popupSize: CGSize, in screenBounds: CGRect) -> CGRect {
        let offset = Constants.popupOffset
        let padding = Constants.popupPadding
        
        // Center horizontally on the selection
        var x = bounds.midX - (popupSize.width / 2)
        // Default position: floating above the selection
        var y = bounds.maxY + offset
        
        // Horizontal screen bounds clamping
        if x + popupSize.width > screenBounds.maxX - padding {
            x = screenBounds.maxX - popupSize.width - padding
        }
        if x < screenBounds.minX + padding {
            x = screenBounds.minX + padding
        }
        
        // If placing above would overflow the top edge of screen, place below selection
        if y + popupSize.height > screenBounds.maxY - padding {
            y = bounds.minY - popupSize.height - offset
        }
        if y < screenBounds.minY + padding {
            y = screenBounds.minY + padding
        }
        
        return CGRect(x: x, y: y, width: popupSize.width, height: popupSize.height)
    }

    public static func calculateFrame(for cursorPosition: CGPoint, popupSize: CGSize, in screenBounds: CGRect) -> CGRect {
        let offset = Constants.popupOffset
        let padding = Constants.popupPadding // padding from screen edge
        
        var x = cursorPosition.x + offset
        var y = cursorPosition.y + offset
        
        if x + popupSize.width > screenBounds.maxX - padding {
            x = screenBounds.maxX - popupSize.width - padding
        }
        if x < screenBounds.minX + padding {
            x = screenBounds.minX + padding
        }
        
        if y + popupSize.height > screenBounds.maxY - padding {
            y = cursorPosition.y - popupSize.height - padding
        }
        if y < screenBounds.minY + padding {
            y = screenBounds.minY + padding
        }
        
        return CGRect(x: x, y: y, width: popupSize.width, height: popupSize.height)
    }
}
