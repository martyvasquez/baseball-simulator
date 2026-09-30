# Baseball Situation Simulator — notes for agents

A teaching tool for young players: pick a situation (field size, runners, outs, where the ball goes) and it shows where all nine fielders go, what the runners do, and where the ball is thrown, with the reasoning and published sources. The owner is a parent using it to teach their kids; accuracy of the baseball rules matters more than anything else.

Three apps share one set of rules:

| App | Where | How people get it |
|---|---|---|
| Web | `index.html`, `app.js`, `styles.css`, `engine.js`, `sources.js` | Open `index.html` (no build step) |
| Mac | `ios/` target `SituationSimMac`, product **Situations.app** | Installed once from GitHub Releases, then **updates itself** (see Releases below) |
| iPad | `ios/` target `SituationSim` | Installed from Xcode onto the owner's iPad (no auto-update) |

The Mac and iPad apps are one SwiftUI codebase (`ios/SituationSim/`). Platform differences live in `#if os(...)` blocks and `Views/Platform.swift`.

## Rules that keep the three apps correct

**1. The rules engine exists twice and must stay identical.** `engine.js` (web) and `ios/SituationSim/Engine/Solver.swift` (native) are line-for-line ports. Any rule change goes in both, then:

```sh
node scripts/export-ios-data.js      # re-exports fixtures.json + Sources.json from the web engine
```

and run the tests (below). `EngineParityTests` compares the Swift engine to the web engine's answers for every situation (16 plays × 8 runner setups × 3 outs × 3 field sizes = 1,152) and names the exact situation/player if they differ.

**2. Every rule has a source note.** Each play tags the rule IDs it uses (`res.rules` in both engines, e.g. `G2`, `S4`, `R7`). Every ID needs an entry in `sources.js` (verdict + note + links), exported to `ios/SituationSim/Resources/Sources.json`. A test fails if one is missing. Only cite links that were actually opened; the owner cares that these are real.

**3. No two fielders may end a play on top of each other.** `LayoutTests` enforces it for every situation. When a new play puts two backups on the same line (typical: pitcher and an outfielder behind the same base), the outfielder goes deeper — see `deep2`/`deep3` in both engines.

**4. The web page caches its scripts.** After changing any `.js`/`.css`, bump the `?v=N` query on the tags in `index.html`, or browsers keep running the old engine.

**5. The Xcode project is generated.** Edit `ios/project.yml`, run `xcodegen generate` in `ios/`, and commit both `project.yml` and `SituationSim.xcodeproj`.

## Testing

```sh
cd ios
# Mac (fast, no simulator) — this is also what CI runs
xcodebuild test -project SituationSim.xcodeproj -scheme SituationSimMac -destination platform=macOS -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
# iPad (needs an iOS 26+ iPad simulator; create one with `xcrun simctl create` if none exists)
xcodebuild test -project SituationSim.xcodeproj -scheme SituationSim -destination "platform=iOS Simulator,id=<SIM_UDID>" -derivedDataPath build
```

`SituationSimUITests/ScreenshotTests` saves screenshots of both orientations when run with `TEST_RUNNER_SCREENSHOT_DIR=/some/dir`. Debug builds accept launch arguments for setting up a play without tapping (`Model/DemoLaunch.swift`): `-level hs -hit gap_LC -runners 100 -outs 1 -focus 1B -reveal YES -at 2400`, plus `-landscape YES` (iPad) and `-snapshot /path.png` (Mac).

## Releases and versioning (Mac app)

**Pushing to `main` is releasing.** `.github/workflows/release-mac.yml` runs on every push to `main` that touches `ios/**` or the workflow itself: it tests, builds a universal (Intel + Apple Silicon) Release app, signs the update with Sparkle, and publishes a GitHub Release. Every installed copy checks for it when it's opened, installs it, and relaunches — no user action. Pushes that only touch the web app, README, or docs do **not** publish a release. To publish without a code change: Actions tab → *Release Mac app* → *Run workflow* (or `gh workflow run release-mac.yml`).

So: **don't push broken app changes to `main`** — tests gate the release, but anything that passes goes straight to the owner's kids.

### Version numbers

- **Build number (`CFBundleVersion`) is automatic.** CI sets `CURRENT_PROJECT_VERSION = GITHUB_RUN_NUMBER + 100`. Sparkle compares build numbers, so they must always increase. Never hand-set a build number for a release, and don't change `CURRENT_PROJECT_VERSION: "1"` in `project.yml` (it's only the local-build default).
- **Run numbers belong to the workflow file.** Renaming or recreating `release-mac.yml` restarts the count at 1 and new builds would look *older* than installed ones. If that ever has to happen, raise the `+ 100` offset above the last published build first.
- **Marketing version (`CFBundleShortVersionString`)** is `MARKETING_VERSION` in `project.yml` (currently `1.0`). Change it only for a milestone; it doesn't affect updating.

### Things that must not change (or installed copies stop updating)

| Setting | Where | Why |
|---|---|---|
| `SUFeedURL` = `https://github.com/martyvasquez/baseball-simulator/releases/latest/download/appcast.xml` | `project.yml` (Mac `info`) | Installed copies only know this URL. The repo must stay **public** and keep this name/owner. |
| `SUPublicEDKey` | `project.yml` | Installed copies only accept updates signed with the matching private key. |
| Asset names `Situations.zip`, `appcast.xml`; release tags `build-N`; releases marked `--latest`, not prerelease | workflow | The feed URL resolves through "latest release". |
| Bundle ID `com.martyvasquez.SituationSim` | `project.yml` | Sparkle updates the app with the same identity. |
| `ENABLE_HARDENED_RUNTIME: NO` (Mac target) | `project.yml` | Builds are ad-hoc signed (no paid Apple account). Hardened runtime's library validation would block the app from loading Sparkle.framework. Turn it on only together with Developer ID signing + notarization. |

### The signing key

- Private key: the owner's **login keychain** (Sparkle account `com.martyvasquez.SituationSim`) and the repo secret **`SPARKLE_PRIVATE_KEY`**. Never commit it or print it.
- If the secret is lost, restore it from the keychain (see the playbook for the safe export command). If both are lost, installed copies can never update again; every Mac would need a manual reinstall of a build with a new public key.
- Sparkle allows changing *either* the Apple code-signing identity *or* the EdDSA key in one release — never both at once.

The full design, the reasons behind each setting, and how to test it are in [`docs/mac-auto-update-playbook.md`](docs/mac-auto-update-playbook.md).

### How the app side works

`ios/SituationSim/Model/AppUpdater.swift` (macOS only): starts Sparkle at launch, calls `checkForUpdatesInBackground()`, and installs as soon as the download finishes (`willInstallUpdateOnQuit` → `immediateInstallationBlock`). **Debug builds never start the updater**, so running from Xcode won't replace your dev build. The app menu has **Check for Updates…**. Sparkle's own scheduled check (while the app stays open) is its default, about once a day.

### First install on a new Mac

Download `Situations.zip` from the [latest release](https://github.com/martyvasquez/baseball-simulator/releases/latest), drag to Applications, open, and approve **System Settings → Privacy & Security → Open Anyway** once (the app isn't notarized). If the Mac user is a **standard (non-admin) account**, install into `~/Applications` instead, or every update will ask for an admin password.

### Pushing workflow changes

The `gh` login needs the `workflow` scope to push anything under `.github/workflows/` (`gh auth refresh -h github.com -s workflow`, interactive — the owner has to run it).

## iPad install

With the iPad connected (`xcrun devicectl list devices` for its UDID):

```sh
cd ios
xcodebuild build -project SituationSim.xcodeproj -scheme SituationSim -destination "id=<IPAD_UDID>" -derivedDataPath build -allowProvisioningUpdates -quiet
xcrun devicectl device install app --device <IPAD_UDID> build/Build/Products/Debug-iphoneos/SituationSim.app
```

Signed with the owner's personal team `3CFUB9TT83` (set in `project.yml`).

## Known loose ends

- CI warns that `actions/checkout@v4` runs on a deprecated Node.js version; bumping it is harmless but publishes a release (it touches the workflow).
- Builds 101 and 102 were identical test releases of the updater.
