import AppKit
import SwiftUI

@MainActor
func announceForAccessibility(
    _ message: String,
    priority: NSAccessibilityPriorityLevel = .medium
) {
    NSAccessibility.post(
        element: NSApp as Any,
        notification: .announcementRequested,
        userInfo: [
            .announcement: message,
            .priority: priority.rawValue
        ]
    )
}

struct ErrorMessagePalette: Sendable {
    struct RGB: Sendable {
        let red: Double
        let green: Double
        let blue: Double

        var color: Color {
            Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
        }

        var relativeLuminance: Double {
            let linear = [red, green, blue].map { component in
                component <= 0.04045
                    ? component / 12.92
                    : pow((component + 0.055) / 1.055, 2.4)
            }
            return (0.2126 * linear[0]) + (0.7152 * linear[1]) + (0.0722 * linear[2])
        }

        func contrastRatio(against other: RGB) -> Double {
            let lighter = max(relativeLuminance, other.relativeLuminance)
            let darker = min(relativeLuminance, other.relativeLuminance)
            return (lighter + 0.05) / (darker + 0.05)
        }
    }

    static let minimumBodyTextContrast = 4.5
    static let light = ErrorMessagePalette(
        foreground: RGB(red: 122.0 / 255, green: 26.0 / 255, blue: 22.0 / 255),
        background: RGB(red: 255.0 / 255, green: 244.0 / 255, blue: 242.0 / 255)
    )
    static let dark = ErrorMessagePalette(
        foreground: RGB(red: 255.0 / 255, green: 218.0 / 255, blue: 213.0 / 255),
        background: RGB(red: 58.0 / 255, green: 24.0 / 255, blue: 22.0 / 255)
    )

    let foreground: RGB
    let background: RGB

    var contrastRatio: Double {
        foreground.contrastRatio(against: background)
    }

    static func resolved(for colorScheme: ColorScheme) -> ErrorMessagePalette {
        colorScheme == .dark ? dark : light
    }
}

struct AccessibleErrorMessage: View {
    @Environment(\.colorScheme) private var colorScheme

    let message: String
    let accessibilityLabel: String
    let identifier: String

    var body: some View {
        let palette = ErrorMessagePalette.resolved(for: colorScheme)

        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(palette.foreground.color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(palette.background.color, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier(identifier)
    }
}

private struct StatusMessageStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let isError: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isError {
            let palette = ErrorMessagePalette.resolved(for: colorScheme)
            content
                .foregroundStyle(palette.foreground.color)
                .background(palette.background.color)
        } else {
            content
                .foregroundStyle(.secondary)
                .background(.bar)
        }
    }
}

extension View {
    func statusMessageStyle(isError: Bool) -> some View {
        modifier(StatusMessageStyle(isError: isError))
    }
}
