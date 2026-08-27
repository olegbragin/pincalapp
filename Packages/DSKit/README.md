# DSKit — Isolated Design System

Local Swift Package for PinCal. Contains all reusable UI (no persistence, no feature logic).

**Contents:** `Calendar/*`, `CalendarCard/*`, `ColorPicker/*`, `PC*.swift`, `PCWalletCardStack/`

**Isolation rules:**
* No `import CorePersistence` / `import Features`
* Only `SwiftUI` + `OrderedCollections` (swift-collections 1.5.1)
* Assets (`Colors.xcassets` `eventColorOption*`, `colorForeground*`) currently in main app bundle — `Color("...")` resolves via `Bundle.main`. When fully migrated, move `Colors.xcassets` here and use `Bundle.module`.

**Integration (Xcode):**
1. Xcode → File → Add Package Dependencies → Add Local → select `Packages/DSKit`
2. In `PinCalApp` target → Frameworks → add `DSKit`
3. `import DSKit` in feature files, delete `PinCalApp/DSKit` from main target (keep Packages copy as source of truth).

**Verification:**
* `xcodebuild build -project PinCalApp.xcodeproj -scheme PinCalApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` — main app still builds (DSKit still in main target until step 3).
* Package standalone `swift build` fails on macOS due to `UIKit` — expected, use `xcodebuild` with iOS destination.
