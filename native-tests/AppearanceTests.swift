import AppKit

@main
@MainActor
struct AppearanceTests {
    static func main() {
        let suite = "librus-appearance-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let appearance = SchoolAppearance(defaults: defaults)
        assert(appearance.density == .compact)
        appearance.density = .comfortable
        assert(SchoolAppearance(defaults: defaults).density == .comfortable,
               "The list density must survive reopening the app")
        appearance.density = .compact
        assert(SchoolAppearance(defaults: defaults).density == .compact)
        defaults.set("unknown-density", forKey: SchoolAppearance.densityPreferenceKey)
        assert(SchoolAppearance(defaults: defaults).density == .compact)
        assert(appearance.theme == .system, "Existing users keep the system appearance by default")
        appearance.theme = .light
        assert(SchoolAppearance(defaults: defaults).theme == .light)
        assert(appearance.theme.colorScheme == .light)
        appearance.theme = .dark
        assert(SchoolAppearance(defaults: defaults).theme == .dark)
        assert(appearance.theme.colorScheme == .dark)
        appearance.theme = .system
        assert(SchoolAppearance(defaults: defaults).theme == .system)
        assert(appearance.theme.colorScheme == nil)
        defaults.set("unknown-legacy-theme", forKey: SchoolAppearance.preferenceKey)
        assert(SchoolAppearance(defaults: defaults).theme == .system)
        textSizePersists(defaults)
        largerTextIncludesMetadata()
        print("Swift appearance: light/dark persistence, system default and invalid preference fallback passed")
    }

    static func textSizePersists(_ defaults: UserDefaults) {
        let appearance = SchoolAppearance(defaults: defaults)
        assert(appearance.textSize == .standard)
        appearance.textSize = .large
        assert(SchoolAppearance(defaults: defaults).textSize == .large,
               "The selected reading size must survive restarting the app")
        appearance.textSize = .standard
        assert(SchoolAppearance(defaults: defaults).textSize == .standard)
        defaults.set("invalid-size", forKey: SchoolAppearance.textSizePreferenceKey)
        assert(SchoolAppearance(defaults: defaults).textSize == .standard)
    }

    static func largerTextIncludesMetadata() {
        let styles: [NSFont.TextStyle] = [.body, .callout, .caption1, .caption2, .headline, .title1, .title2]
        for style in styles {
            assert(SchoolTextSize.large.pointSize(for: style) >= SchoolTextSize.standard.pointSize(for: style) + 2,
                   "Large text must visibly enlarge both content and small metadata")
        }
    }
}
