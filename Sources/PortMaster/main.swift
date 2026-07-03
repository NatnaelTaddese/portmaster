import AppKit
import CoreText

// Register bundled fonts (Lexend) for this process before any UI exists.
if let fontURLs = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") {
    for url in fontURLs {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
