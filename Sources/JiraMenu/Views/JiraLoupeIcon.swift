import AppKit

/// Loads the menubar icon from a bundled PNG resource (`MenuBarIcon.png`
/// in the app bundle's `Contents/Resources/`). The PNG is used unmodified —
/// no rotation or scaling beyond fitting to the requested point size.
///
/// `isTemplate = true` tells macOS to ignore the PNG's color channels and
/// render only the alpha mask, tinting it to match the menubar's state
/// (normal / pressed / dark mode / menubar-on-wallpaper). For a template
/// image to look correct the PNG must have a transparent background —
/// solid-white backgrounds render as a white rectangle behind the glyph.
///
/// Called once per app launch from `JiraMenuApp`. If the resource is
/// missing, returns an empty NSImage of the requested size so the
/// MenuBarExtra still has *something* to render (a clickable blank
/// rectangle beats a crash on startup).
@MainActor
func jiraLoupeMenuBarImage(size: CGFloat = 18) -> NSImage {
    let fallback = NSImage(size: NSSize(width: size, height: size))

    guard let url = Bundle.main.url(forResource: "jiramenu-logo", withExtension: "png"),
          let image = NSImage(contentsOf: url) else {
        return fallback
    }

    // Constrain to the caller's point size. AppKit will handle pixel-scale
    // for Retina displays via the NSImage's representations.
    image.size = NSSize(width: size, height: size)
    image.isTemplate = true
    return image
}
