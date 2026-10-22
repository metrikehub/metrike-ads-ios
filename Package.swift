// swift-tools-version:5.7
import PackageDescription
let package = Package(
    name: "MetrikeAds",
    platforms: [.iOS(.v14)],
    products: [.library(name: "MetrikeAds", targets: ["MetrikeAds"])],
    targets: [
        .binaryTarget(
            name: "MetrikeAds",
            url: "https://cdx.metrike.com.br/sdk/ios/MetrikeAds-0.2.0.zip",
            checksum: "c9021c7b6a83cbb19637b8e36417666b8447aceaff3f42e650b4f542b59d8cf6"
        )
    ]
)
