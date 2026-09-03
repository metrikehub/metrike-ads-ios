// swift-tools-version:5.7
import PackageDescription
let package = Package(
    name: "MetrikeAds",
    platforms: [.iOS(.v14)],
    products: [.library(name: "MetrikeAds", targets: ["MetrikeAds"])],
    targets: [
        .binaryTarget(
            name: "MetrikeAds",
            url: "https://cdx.metrike.com.br/sdk/ios/MetrikeAds-0.1.0.zip",
            checksum: "ea37da3af5ab6d15a9b704bf3dd395e0259f68944f6244787c84dbd8142f9371"
        )
    ]
)
