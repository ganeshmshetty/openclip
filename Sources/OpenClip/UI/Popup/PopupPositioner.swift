import Foundation
import CoreGraphics
import AppKit

public struct PopupPositioner: Sendable {
    public static func calculateFrame(for cursorPosition: CGPoint, popupSize: CGSize, in screenBounds: CGRect) -> CGRect {
        let offset: CGFloat = 16.0
        let padding: CGFloat = 8.0 // padding from screen edge
        
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
