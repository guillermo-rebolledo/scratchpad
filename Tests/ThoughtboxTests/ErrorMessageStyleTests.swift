import Foundation
import Testing
@testable import Thoughtbox

@Suite("Accessible error message styling")
struct ErrorMessageStyleTests {
    @Test("Body text exceeds WCAG AA contrast in light and dark appearances")
    func paletteContrast() {
        #expect(ErrorMessagePalette.light.contrastRatio >= ErrorMessagePalette.minimumBodyTextContrast)
        #expect(ErrorMessagePalette.dark.contrastRatio >= ErrorMessagePalette.minimumBodyTextContrast)
        #expect(abs(ErrorMessagePalette.light.contrastRatio - 9.80) < 0.01)
        #expect(abs(ErrorMessagePalette.dark.contrastRatio - 12.28) < 0.01)
    }
}
