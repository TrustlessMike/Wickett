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

The recovered backend passes `npm run build` (TypeScript checking only). All 86 Swift files pass syntax parsing. No end-to-end transfer, provider connection, deployment, or full iOS build has been verified in this recovery.

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

Open `Wickett.xcodeproj`. Supply your own Firebase configuration using `Resources/GoogleService-Info.plist.example` as a field guide, set Privy values in `AppConfiguration.swift`, and select your own bundle identifier and signing team. The historical `Package.swift` is preserved for reference; the Xcode project is the recovery entry point. SDK compatibility and a full build remain to be checked.

## License

Project-authored code is released under [MIT](LICENSE). Third-party packages and token/company marks retain their respective licenses and rights; their presence does not imply endorsement. The Wickett brand asset is preserved to identify this project.
