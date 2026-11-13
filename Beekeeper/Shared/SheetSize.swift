import SwiftUI

extension View {
    /// A sheet's size on the Mac, where a sheet is only as big as its content. On iPad and iPhone the
    /// system sizes sheets, and a fixed size would crop the content or leave it floating in the middle.
    func macSheetSize(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
        frame(width: width, height: height)
        #else
        self
        #endif
    }
}
