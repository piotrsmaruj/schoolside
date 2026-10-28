import AppKit
import SwiftUI

@MainActor
enum SchoolPalette {
    static let accent = adaptive(light: 0x6B4F82, dark: 0xC4A7DD, highLight: 0x4D315F, highDark: 0xE2C8FA)
    static let canvas = adaptive(light: 0xF6F5F2, dark: 0x18161C)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x211E26)
    static let sidebar = adaptive(light: 0xEEECE8, dark: 0x141218)
    static let selection = adaptive(light: 0xEAE1F1, dark: 0x372A45)
    static let raised = adaptive(light: 0xF1EEF4, dark: 0x2A2530)
    static let border = adaptive(light: 0xDAD5DE, dark: 0x493E52, highLight: 0x94889C, highDark: 0xA194AB)
    static let primaryText = adaptive(light: 0x28242B, dark: 0xF2EDF5, highLight: 0x161219, highDark: 0xFFFFFF)
    static let secondaryText = adaptive(light: 0x68636D, dark: 0xB9AFBF, highLight: 0x4F4856, highDark: 0xD5CBDD)
    static let warning = adaptive(light: 0x8D4F15, dark: 0xE9B36F)
    static let warningSurface = adaptive(light: 0xFAEDD5, dark: 0x3D2B1C)
    static let success = adaptive(light: 0x39724F, dark: 0x9BCAA4)

    /// Appearance-aware semantic tokens keep content readable in Auto and increased contrast.
    private static func adaptive(light: UInt32, dark: UInt32,
                                 highLight: UInt32? = nil, highDark: UInt32? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.accessibilityHighContrastAqua,
                .accessibilityHighContrastDarkAqua, .aqua, .darkAqua])
            let value: UInt32
            switch match {
            case .accessibilityHighContrastAqua: value = highLight ?? light
            case .accessibilityHighContrastDarkAqua: value = highDark ?? dark
            case .darkAqua: value = dark
            default: value = light
            }
            return NSColor(srgbRed: Double((value >> 16) & 0xFF) / 255,
                           green: Double((value >> 8) & 0xFF) / 255,
                           blue: Double(value & 0xFF) / 255, alpha: 1)
        })
    }
}
