# NovelAgent

NovelAgent is an iPhone-native AI agent for planning and writing Chinese
long-form web fiction. It guides a new writer from an initial idea to a
confirmed story brief, rolling outline, chapter draft, consistency review,
revision, and local backup.

## Product Boundaries

- iOS 16.0+, iPhone only
- Swift 6, SwiftUI, UIKit text editor bridge
- Direct BYOK access to OpenAI, Anthropic, and OpenAI-compatible APIs
- Local SQLite source of truth with Markdown/JSON/ZIP backup
- One chapter per resumable production run
- No account system, iCloud, arbitrary novel import, local LLM, or unattended
  background generation in V1

## Repository Layout

```text
Sources/NovelAgentCore/       Cross-platform domain and agent runtime
Sources/NovelAgentProviders/  URLSession/SSE provider adapters
NovelAgentApp/                SwiftUI app, GRDB storage, Keychain, export
Tests/                        Core, persistence, and UI tests
project.yml                   XcodeGen project definition
```

## Windows Core Tests

Install Swift 6 for Windows, then run:

```powershell
swift test
```

The iOS application itself requires Xcode. GitHub Actions generates the Xcode
project and runs iOS builds and simulator tests.

## Generate the Xcode Project

```bash
brew install xcodegen
xcodegen generate
open NovelAgent.xcodeproj
```

## Unsigned IPA

Run the `Build Unsigned IPA` workflow manually. It creates an ad-hoc signed
IPA intended for personal installation with TrollStore. No signing certificate
or provisioning profile is embedded.

## Security

API keys are stored in Keychain and are never written to SQLite, exported
backups, source files, or logs. Custom endpoints must use HTTPS.

## License

MIT. See `THIRD_PARTY_NOTICES.md` for attribution and clean-room boundaries.

