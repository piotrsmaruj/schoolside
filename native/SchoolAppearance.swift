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
    private let defaults: UserDefaults
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
        density = SchoolDensity(rawValue: defaults.string(forKey: Self.densityPreferenceKey) ?? "") ?? .compact
        theme = SchoolTheme(rawValue: defaults.string(forKey: Self.preferenceKey) ?? "") ?? .system
        NSApp?.appearance = theme.nativeAppearance
    }
}
