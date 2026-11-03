import CoreGraphics
import Foundation

/// A snapshot of one window belonging to the remote desktop client.
public struct WindowInfo: Equatable, Hashable {
    /// The CGWindowID when known, otherwise a stable index from AX enumeration.
    public var id: Int
    public var pid: pid_t
    public var title: String
    /// Frame in CG coordinates (global, top-left origin).
    public var frame: CGRect
    public var isOnScreen: Bool

    public init(id: Int, pid: pid_t, title: String, frame: CGRect, isOnScreen: Bool) {
        self.id = id
        self.pid = pid
        self.title = title
        self.frame = frame
        self.isOnScreen = isOnScreen
    }

    public var area: CGFloat { frame.width * frame.height }
}
