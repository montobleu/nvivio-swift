#if canImport(SwiftUI)
import SwiftUI

extension View {
    /// Sends a screen view for `name` when this view appears. SwiftUI calls `onAppear` again
    /// on redraws and when you come back to the view; the SDK only counts a new screen.
    public func nvivioScreen(_ name: String) -> some View {
        onAppear { Nvivio.screen(name) }
    }
}
#endif
