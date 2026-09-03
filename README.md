# Metrike Ads SDK for iOS

`MetrikeAds` is a closed-source binary framework distributed as a Swift
Package. This repository is intentionally small: a `Package.swift` manifest
that resolves the `.xcframework` published at cdx, plus a runnable example
app. **It does not contain the SDK's source.**

## Install

Xcode: **File → Add Package Dependencies…** and paste this repository's URL.

Or, in a `Package.swift` of your own:

```swift
dependencies: [
    .package(url: "https://github.com/metrikehub/metrike-ads-ios", from: "0.1.0")
]
```

## Requirements

- iOS 14.0+
- Xcode 15+ / Swift 5.7 toolchain

## Example app

See [`Example/`](Example/) — a small UIKit gallery covering all six ad
formats (banner, interstitial, VAST fullscreen, outstream, instream,
MRAID) plus an in-app conversion demo. It consumes only the public
`MetrikeAds` API, the same way any host app would.

## Documentation

Full integration guide (formats, metrics, consent/CMP, GPS opt-in, iOS
install-attribution notes, and V1 limitations):
https://hub.metrike.com.br/sdk/docs/ios

## License

MIT — see [`LICENSE`](LICENSE).
