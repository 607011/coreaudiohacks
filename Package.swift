// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MusicFormatSwitcher",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MusicFormatSwitcher",
            path: "Sources/MusicFormatSwitcher",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
