import SwiftUI
import AppKit

/// The menubar icon: the Jira three-chevron mark dominating the upper-right
/// of the frame, with a small cursor arrow in the bottom-left pointing
/// toward it — "select Jira." Rendered as a monochrome template NSImage so
/// macOS tints it to match the menubar's light/dark/selected state.
struct JiraLoupeIcon: View {
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            // Jira mark lives in the upper-right; the cursor arrow lives in
            // the lower-left. They don't overlap — each owns its own quadrant.
            let markSize = size * 0.74
            let markCenter = CGPoint(x: size * 0.55, y: size * 0.40)
            let arrowSize = size * 0.42
            let arrowCenter = CGPoint(x: size * 0.23, y: size * 0.78)

            ZStack {
                // Cursor arrow, pointing up-right toward the Jira mark.
                CursorArrowShape()
                    .fill(Color.black)
                    .frame(width: arrowSize, height: arrowSize)
                    .position(arrowCenter)

                // Jira mark — the visual anchor.
                JiraMarkShape()
                    .fill(Color.black)
                    .frame(width: markSize, height: markSize)
                    .position(markCenter)
            }
        }
    }
}

/// Stylized Jira mark: three right-angle chevrons (◢) stacked diagonally
/// from top-left (smallest) to bottom-right (largest). Mirrors the Atlassian
/// Jira logo silhouette without cloning the trademarked multi-color
/// original — fine for a monochrome template icon where color is discarded.
///
/// Triangles are drawn non-overlapping so they read as three distinct shapes
/// rather than merging into one solid blob.
struct JiraMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let s = min(rect.width, rect.height)
        let ox = rect.minX
        let oy = rect.minY

        // Each triangle's right angle is at its bottom-right corner (◢).
        // Positions are normalized centers; sizes are normalized edge lengths.
        let wedges: [(cx: CGFloat, cy: CGFloat, size: CGFloat)] = [
            (0.22, 0.20, 0.30),
            (0.48, 0.46, 0.36),
            (0.76, 0.74, 0.42),
        ]

        for w in wedges {
            let cx = ox + s * w.cx
            let cy = oy + s * w.cy
            let half = (s * w.size) / 2
            let topRight    = CGPoint(x: cx + half, y: cy - half)
            let bottomRight = CGPoint(x: cx + half, y: cy + half)
            let bottomLeft  = CGPoint(x: cx - half, y: cy + half)
            path.move(to: topRight)
            path.addLine(to: bottomRight)
            path.addLine(to: bottomLeft)
            path.closeSubpath()
        }

        return path
    }
}

/// Classic mouse-cursor arrow silhouette, rotated to point up-right at ~45°.
/// Drawn as a single filled polygon so it renders cleanly at small sizes —
/// strokes + triangles as separate layers tend to alias at 18pt menubar size.
struct CursorArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let x0 = rect.minX
        let y0 = rect.minY

        // Vertices clockwise from the tip (top-right), in normalized (0..1)
        // coordinates within the arrow's bounding box.
        //
        //            (tip)
        //              •
        //             /|
        //            / |    <- outer edge of arrowhead barb
        //           /  |
        //          /   •    <- inner elbow (barb meets shaft)
        //         /   /
        //        /   /
        //       /   /       <- shaft
        //      /   /
        //     •---•          <- shaft tail
        //   (tail)
        let verts: [(CGFloat, CGFloat)] = [
            (1.00, 0.00),  // tip
            (0.55, 0.15),  // outer top of arrowhead
            (0.70, 0.50),  // inner elbow top
            (0.35, 0.80),  // shaft right side near tail
            (0.05, 1.00),  // tail bottom-left
            (0.00, 0.75),  // tail top-left
            (0.30, 0.45),  // shaft left side
            (0.45, 0.35),  // inner elbow bottom (where barb joins shaft)
            (0.15, 0.55),  // outer bottom of arrowhead barb
        ]

        // The vertex list above traces the arrow silhouette. Map normalized
        // coords into the shape's rect and add to the path.
        for (i, v) in verts.enumerated() {
            let point = CGPoint(x: x0 + w * v.0, y: y0 + h * v.1)
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

/// Renders `JiraLoupeIcon` into a template NSImage for use as a
/// `MenuBarExtra` label. Called once per app launch.
@MainActor
func jiraLoupeMenuBarImage(size: CGFloat = 18) -> NSImage {
    let view = JiraLoupeIcon()
        .frame(width: size, height: size)
    let renderer = ImageRenderer(content: view)
    renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
    let fallback = NSImage(size: NSSize(width: size, height: size))
    let image = renderer.nsImage ?? fallback
    image.isTemplate = true
    return image
}
