// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nvivio",
    platforms: [.iOS(.v15), .macOS(.v12), .tvOS(.v15), .visionOS(.v1)],
    products: [
        .library(name: "Nvivio", targets: ["Nvivio"])
    ],
    targets: [
        // The privacy manifest goes into the SDK's bundle, where Xcode finds it for the app's privacy report.
        .target(name: "Nvivio", resources: [.copy("PrivacyInfo.xcprivacy")]),
        .testTarget(name: "NvivioTests", dependencies: ["Nvivio"])
    ],
    swiftLanguageModes: [.v6]
)
