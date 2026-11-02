<p align="center"><img src="Resources/Assets.xcassets/Logo.imageset/Logo.png" width="180" alt="Wickett original logo"></p>

# Wickett — global payments

Send and request money across borders with a familiar iOS experience, fiat-denominated requests, and Solana settlement. Wickett's original idea was everyday global payments with fiat on/off-ramps and recipient currency preferences.

**Recovered source prototype.** This repository separates the original payments product from the later Mimic copy-trading pivot. It is not a currently verified payment service or release-ready app.

## Recovered code

- **iOS:** the last Wickett commit before the Mimic pivot, December 2, 2025 (`603c3e5`). SwiftUI wallet, send, requests, QR codes, fiat on/off-ramp screens, recipient preferences, and swap flows.
- **Backend:** surviving payment-related Firebase/TypeScript modules recovered from the local successor checkout. Includes sponsorship, signed-transaction broadcast, payment requests, Coinbase adapters, and user services. These are a separate recovery source, not an exact December backend snapshot.
- **Brand:** the original Wickett logo and iOS assets, preserved from the payments app.

Mimic's prediction, copy-trading, tracking dashboard and real-time tracker are outside this repository. See [product scope](docs/PRODUCT.md) and [recovery evidence](docs/RECOVERY.md).

## Development status

Verified on November 2, 2026:

- **iOS simulator build:** `xcodebuild -project Wickett.xcodeproj -scheme Wickett -destination 'generic/platform=iOS Simulator' build` succeeds with Xcode 27.2 (iOS Simulator 27.2 SDK, arm64 and x86_64) with no Firebase or Privy configuration present. This needed two project fixes: the `solana-swift` dependency now points at upstream `p2p-org/solana-swift` 5.0.0, because the historical fork no longer exists, and `GoogleService-Info.plist` is bundled only when present.
- **Backend:** `npm ci --ignore-scripts && npm run build` passes (TypeScript checking only) on host Node 26.11.1.

Not yet verified: launching the app in a simulator, because the build host's CoreSimulator was out of date for Xcode 27.2. A device build, signing, provider connections, sign-in, deployment, and any end-to-end request or transfer have not been verified either. The declared Node 20 runtime has not been separately verified.

The source still contains historical mainnet-oriented logic. Configure an isolated test project and review the recovered transaction and authorization paths before running services. No deployment configuration or operational credentials are supplied.

### Backend check

Use the declared Node 20 environment:

```sh
cd functions
npm ci --ignore-scripts
npm run build
```

`build` only type-checks; it does not deploy or emit a runnable backend. Backend secret names are defined through Firebase Secret Manager in the source. Supply your own provider projects and configuration.

### iOS

Open `Wickett.xcodeproj`. Supply your own Firebase configuration at `Resources/GoogleService-Info.plist`, using `Resources/GoogleService-Info.plist.example` as a field guide. Set the Privy app and client IDs in `AppConfiguration.swift` and the matching `privy-` URL scheme in `Resources/Info.plist`. Select your own bundle identifier and signing team. Package versions are pinned in `Wickett.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. The historical `Package.swift` is preserved for reference; the Xcode project is the recovery entry point.

Until both the Firebase plist and the Privy values are supplied, the app is written to skip Firebase and Privy setup and show a setup screen listing what is missing (`BackendSetupView`). That path builds but has not yet been run in a simulator.

## License

Project-authored code is released under [MIT](LICENSE). Third-party packages and token/company marks retain their respective licenses and rights; their presence does not imply endorsement. The Wickett brand asset is preserved to identify this project.
