import Foundation

/// Presentation helpers for listing a display's modes (the `aspace modes`
/// command). The ordering is pure and value-based so it can be unit-tested;
/// the CLI handles the actual column formatting.
public enum DisplayModeReport {
    /// Modes sorted for human reading: largest point size first, then largest
    /// framebuffer (HiDPI variants above their 1:1 twin), then highest refresh.
    public static func sorted(_ modes: [DisplayMode]) -> [DisplayMode] {
        modes.sorted {
            if $0.pointWidth != $1.pointWidth { return $0.pointWidth > $1.pointWidth }
            if $0.pointHeight != $1.pointHeight { return $0.pointHeight > $1.pointHeight }
            if $0.pixelWidth != $1.pixelWidth { return $0.pixelWidth > $1.pixelWidth }
            return $0.refreshHz > $1.refreshHz
        }
    }
}
