// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "JiraMenu",
    platforms: [
        .macOS(.v13),
    ],
    targets: [
        .executableTarget(
            name: "JiraMenu",
            path: "Sources/JiraMenu",
            // Resources are staged into the .app's Contents/Resources by
            // scripts/build-app.sh so they're reachable via Bundle.main.
            // We exclude them from SwiftPM's build to avoid its resource-
            // handling warnings (and the Bundle.module indirection we'd
            // otherwise need).
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "JiraMenuTests",
            dependencies: ["JiraMenu"],
            path: "Tests/JiraMenuTests"
        ),
    ]
)
