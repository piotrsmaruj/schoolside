import AppKit
import SwiftUI

enum SchoolDensity: String, CaseIterable, Identifiable {
    case compact, comfortable
    var id: String { rawValue }
    var title: String { self == .compact ? "Kompaktowy" : "Wygodny" }
    var rowPadding: CGFloat { self == .compact ? 10 : 16 }
    var rowSpacing: CGFloat { self == .compact ? 6 : 10 }
    var bodyLines: Int { self == .compact ? 1 : 2 }
}

enum SchoolTextSize: String, CaseIterable, Identifiable {
    case standard, large
    var id: String { rawValue }
    var title: String { self == .standard ? "Standardowy" : "Duży" }
    var scale: CGFloat { self == .standard ? 1 : 1.25 }

    @MainActor
    func pointSize(for style: NSFont.TextStyle) -> CGFloat {
        NSFont.preferredFont(forTextStyle: style, options: [:]).pointSize * scale
    }

    @MainActor
    func font(_ style: NSFont.TextStyle, design: Font.Design = .default) -> Font {
        .system(size: pointSize(for: style), weight: style == .headline ? .semibold : .regular, design: design)
    }
}

enum SchoolTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Systemowy"
        case .light: "Jasny"
        case .dark: "Ciemny"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
    var nativeAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class SchoolAppearance: ObservableObject {
    static let preferenceKey = "schoolTheme"
    static let densityPreferenceKey = "schoolDensity"
    static let textSizePreferenceKey = "schoolTextSize"
    private let defaults: UserDefaults
    @Published var textSize: SchoolTextSize {
        didSet { defaults.set(textSize.rawValue, forKey: Self.textSizePreferenceKey) }
    }
    @Published var density: SchoolDensity {
        didSet { defaults.set(density.rawValue, forKey: Self.densityPreferenceKey) }
    }
    @Published var theme: SchoolTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: Self.preferenceKey)
            NSApp?.appearance = theme.nativeAppearance
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        textSize = SchoolTextSize(rawValue: defaults.string(forKey: Self.textSizePreferenceKey) ?? "") ?? .standard
        density = SchoolDensity(rawValue: defaults.string(forKey: Self.densityPreferenceKey) ?? "") ?? .compact
        theme = SchoolTheme(rawValue: defaults.string(forKey: Self.preferenceKey) ?? "") ?? .system
        NSApp?.appearance = theme.nativeAppearance
    }
}

private struct SchoolFont: ViewModifier {
    @EnvironmentObject private var appearance: SchoolAppearance
    let style: NSFont.TextStyle
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(appearance.textSize.font(style, design: design))
    }
}

extension View {
    /// Applies the user's reading size to content and metadata, including sheets.
    func schoolFont(_ style: NSFont.TextStyle, design: Font.Design = .default) -> some View {
        modifier(SchoolFont(style: style, design: design))
    }
}
