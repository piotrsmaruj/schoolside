import AppKit
import SwiftUI

@main
@MainActor
struct PaletteTests {
    static func main() {
        let variants: [NSAppearance.Name] = [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]
        for variant in variants {
            readable(SchoolPalette.primaryText, on: SchoolPalette.canvas, variant: variant)
            readable(SchoolPalette.secondaryText, on: SchoolPalette.surface, variant: variant)
            readable(SchoolPalette.secondaryText, on: SchoolPalette.sidebar, variant: variant)
            readable(SchoolPalette.accent, on: SchoolPalette.surface, variant: variant)
            readable(SchoolPalette.accent, on: SchoolPalette.selection, variant: variant)
            readable(SchoolPalette.secondaryText, on: SchoolPalette.selection, variant: variant)
            readable(SchoolPalette.secondaryText, on: SchoolPalette.raised, variant: variant)
            readable(SchoolPalette.warning, on: SchoolPalette.warningSurface, variant: variant)
        }
        let light = components(SchoolPalette.canvas, variant: .aqua)
        let dark = components(SchoolPalette.canvas, variant: .darkAqua)
        assert(luminance(light) - luminance(dark) > 0.5, "Canvas must adapt to light and dark appearances")
        print("Swift palette: readable text/accent/warnings in light, dark and increased contrast passed")
    }

    static func readable(_ foreground: Color, on background: Color, variant: NSAppearance.Name) {
        let front = luminance(components(foreground, variant: variant))
        let back = luminance(components(background, variant: variant))
        let ratio = (max(front, back) + 0.05) / (min(front, back) + 0.05)
        assert(ratio >= 4.5, "Text contrast must be at least 4.5:1 in \(variant.rawValue); got \(ratio)")
    }

    static func components(_ color: Color, variant: NSAppearance.Name) -> [Double] {
        var result: [Double] = []
        NSAppearance(named: variant)!.performAsCurrentDrawingAppearance {
            guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { fatalError("Palette must resolve in sRGB") }
            result = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        }
        return result
    }

    static func luminance(_ components: [Double]) -> Double {
        let linear = components.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }
}
