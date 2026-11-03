import CoreGraphics
import Foundation

/// Posts the jiggle as real CGEvents to the HID event tap.
public final class CGMousePoster: MousePosting {
    private let distance: CGFloat
    private let gap: TimeInterval
    private static let f15KeyCode: CGKeyCode = 0x71

    public init(distance: CGFloat = 5, gap: TimeInterval = 0.04) {
        self.distance = distance
        self.gap = gap
    }

    public func jiggle(in frame: CGRect, pressKey: Bool) -> (start: Date, end: Date) {
        let start = Date()
        var cursor = CGEvent(source: nil)?.location ?? CGPoint(x: frame.midX, y: frame.midY)
        if !frame.contains(cursor) {
            cursor = CGPoint(x: frame.midX, y: frame.midY)
            moveMouse(to: cursor)
            pause()
        }
        // Keep the whole pattern inside the frame.
        let plus = clamp(CGPoint(x: cursor.x + distance, y: cursor.y), to: frame)
        let minus = clamp(CGPoint(x: cursor.x - distance, y: cursor.y), to: frame)
        moveMouse(to: plus)
        pause()
        moveMouse(to: minus)
        pause()
        moveMouse(to: cursor)
        if pressKey {
            pause()
            postKey(down: true)
            pause()
            postKey(down: false)
        }
        return (start, Date())
    }

    private func moveMouse(to point: CGPoint) {
        let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        event?.post(tap: .cghidEventTap)
    }

    private func postKey(down: Bool) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: Self.f15KeyCode, keyDown: down)
        event?.post(tap: .cghidEventTap)
    }

    private func pause() {
        Thread.sleep(forTimeInterval: gap)
    }

    private func clamp(_ p: CGPoint, to frame: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, frame.minX + 1), frame.maxX - 1), y: min(max(p.y, frame.minY + 1), frame.maxY - 1))
    }
}
