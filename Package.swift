// swift-tools-version:5.7
import PackageDescription
let package = Package(
    name: "MetrikeAds",
    platforms: [.iOS(.v14)],
    products: [.library(name: "MetrikeAds", targets: ["MetrikeAds"])],
    targets: [
        .binaryTarget(
            name: "MetrikeAds",
            url: "https://cdx.metrike.com.br/sdk/ios/MetrikeAds-0.1.1.zip",
            checksum: "ab1ba0d4de6b5f547771bf4940b3e4398eed41b52ecbc96541a8ad94e0331f62"
        )
    ]
)
