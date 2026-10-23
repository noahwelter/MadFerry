// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FerryKit",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26)],
    products: [.library(name: "FerryKit", targets: ["FerryKit"])],
    targets: [
        .target(name: "FerryKit", resources: [.copy("Resources/BundledSchedule.json")]),
        .testTarget(name: "FerryKitTests", dependencies: ["FerryKit"]),
    ]
)
