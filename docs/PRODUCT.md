# Wickett product identity

## Core idea

Global payments: send and request value across borders while presenting amounts in familiar currencies. The recipient can choose how received value is held. Blockchain, wallet creation and fee sponsorship support the experience underneath.

## Evidence in the recovered product

| Product area | Source evidence | Scope |
| --- | --- | --- |
| Send money | `Sources/Wickett/Features/Send/` | Recipient selection, amount entry, user signing and transaction status |
| Request money | `Sources/Wickett/Features/Request/`, `Core/Requests/` | Fiat-denominated requests, request lists and QR presentation |
| Cash in/out | `Features/Coinbase/`, `functions/src/coinbase/` | Onramp, offramp and Apple Pay adapters; availability is provider-dependent |
| Recipient preferences | `Shared/Models/UserPreferences.swift`, `Features/Settings/` | Currency and portfolio allocation preferences |
| Settlement | `functions/src/transactions/` | Solana SOL/SPL sponsorship and signed transaction broadcast |
| Conversion | `Features/Swap/`, `functions/src/auto-convert/` | Swap and incoming-value conversion logic inherited from the original concept |

These are source-level capabilities, not claims that live services currently work or that every country or currency is supported.

## Separate projects

- **Wickett:** global payments, send/request, on/off-ramps and recipient preferences.
- **Mimic:** follow traders, wallet activity, copy-trading and prediction-market discovery. Separate repository: https://github.com/TrustlessMike/Mimic.
- **Stack:** spare-change crypto onboarding and portfolio discovery. Its source lives in Stack-Ios and older web prototypes; it is not part of this recovery.

Shared authentication and wallet plumbing does not make these the same product. New payment work belongs here; Mimic-specific execution and market features belong in Mimic.
