// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OptiMac",
    platforms: [.macOS(.v11)],
    targets: [
        .executableTarget(
            name: "OptiMac",
            path: "Sources/OptiMac",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
                .linkedFramework("UserNotifications"),
                // macOS 11 n'a pas encore le moteur « async/await » de Swift :
                // il est livré dans OptiMac.app/Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        )
    ]
)
