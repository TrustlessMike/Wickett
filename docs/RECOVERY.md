# Recovery evidence — October 10, 2026

## Historical boundary

- `603c3e5` (December 2, 2025): last pre-pivot Wickett app commit, “Add combined createAndSendFiatRequest for faster requests.” This supplies the iOS snapshot.
- `21f72a4` (January 7, 2026): “Pivot to Mimic: wallet tracking and copy trading app.”
- `1dbd28f` (January 7, 2026): second explicitly named Mimic pivot commit.
- `3ef61dc` (October 27, 2025): earlier payments backend and documentation. The December iOS-only commit removed those files from tracking; some later payment modules survived locally in the successor checkout.

The previous Wickett GitHub remote returned 404 during recovery. No pull requests were returned for the accessible Mimic or Wickett website repositories, and a Wickett pull-request search by the owner returned no results. Commit history, source and surviving assets therefore supply the evidence; no missing pull request is reconstructed or claimed.

The separate private `wickett-wallet-website` repository contains the original “Any Currency” / “One Wallet” positioning. Local historical fiat-payment documentation describes requests denominated in local currencies and recipient allocations. Those historical documents contain unverified completion claims and are summarized in PRODUCT.md rather than copied as current status.

## Assembly and provenance

`recovery-manifest.json` records original file hashes and origins. `ios_commit` is the exact historical commit. `local-surviving-payments` entries came from the local successor files on the recovery date and may differ from the December backend. Owner configuration was replaced with placeholders, signing identity removed, and a payment-only export index written. Unused copy-trading/lending/staking package dependencies were removed. Trailing whitespace was normalized. The TypeScript check ran on the host Node 26 runtime; the declared Node 20 runtime has not been separately verified.

The new repository has a fresh history. It excludes historical wallet-key files, Firebase project credentials, environment files, private keys, operational logs and copied Git internals. Original local checkouts and their uncommitted work were not modified.

## Verification

- 86 Swift files: syntax parsing passed; not a full app build.
- Recovered backend: all relative imports resolve; TypeScript check passed.
- Secret-pattern checks: no private-key blocks, Google API keys, GitHub tokens, credential-bearing URLs, or literal secret assignments found in the selected source. A Remote Config key name was a false positive. This is a bounded pre-publication check, not a security audit.
- Full iOS build, provider configuration, authentication/authorization review, request-to-backend contract checks and transfer tests remain outstanding.

No historical production-ready, mainnet-test or TestFlight claims were carried forward as verified current facts.
