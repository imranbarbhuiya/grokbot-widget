import AppKit

struct PanelPlacement {
    static func expanded(from collapsed: NSRect, within bounds: NSRect) -> (frame: NSRect, below: Bool) {
        let size = NSSize(width: min(380, bounds.width), height: min(640, bounds.height))
        let aboveSpace = bounds.maxY - collapsed.minY
        let belowSpace = collapsed.maxY - bounds.minY
        let below = aboveSpace < size.height && belowSpace > aboveSpace
        var frame = NSRect(x: collapsed.maxX - size.width, y: below ? collapsed.maxY - size.height : collapsed.minY, width: size.width, height: size.height)
        frame.origin.x = min(max(frame.minX, bounds.minX), bounds.maxX - size.width)
        frame.origin.y = min(max(frame.minY, bounds.minY), bounds.maxY - size.height)
        return (frame, below)
    }
}
