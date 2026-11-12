import AppKit
import CoreText

/// Outfit (SIL OFL 1.1), the one bundled font: headings, titles and metrics at weight 600.
/// The .app carries `Contents/Resources/Fonts` (Info.plist `ATSApplicationFontsPath`), and launch also
/// registers that folder for the process. Under `swift run` and in tests the folder is absent and
/// every display role falls back to the system font, silently.
enum BundledFonts {
    /// PostScript names of Outfit's SemiBold (wght 600) named instance. The variable font's default
    /// instance is Thin, so CoreText names the family "Outfit Thin" and the instance `Outfit-Thin_SemiBold`.
    private static let semiboldNames = ["Outfit-Thin_SemiBold", "Outfit-SemiBold"]
    private static let weightAxis = NSNumber(value: 0x7767_6874)  // 'wght'

    /// Registers every font file in `<resources>/Fonts` for this process. Safe to call more than once.
    static func register(bundle: Bundle = .main) {
        guard let folder = bundle.resourceURL?.appendingPathComponent("Fonts", isDirectory: true) else { return }
        let files =
            (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for url in files where ["woff2", "woff", "ttf", "otf"].contains(url.pathExtension.lowercased()) {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Already registered through ATSApplicationFontsPath is the expected case; nothing to do.
                let code = error.map { CFErrorGetCode($0.takeRetainedValue()) } ?? 0
                Log.app.debug("Font not registered (code \(code, privacy: .public))")
            }
        }
    }

    /// Outfit at weight 600, or nil when it is not available.
    static func displayFont(size: CGFloat) -> NSFont? {
        for name in semiboldNames {
            if let font = NSFont(name: name, size: size) { return font }
        }
        guard
            let family = NSFontManager.shared.availableFontFamilies.first(where: { $0.hasPrefix("Outfit") })
        else { return nil }
        let descriptor = NSFontDescriptor(fontAttributes: [.family: family, .variation: [weightAxis: 600]])
        return NSFont(descriptor: descriptor, size: size)
    }

    static var isDisplayFontAvailable: Bool { displayFont(size: 12) != nil }
}
