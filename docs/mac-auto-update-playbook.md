# Playbook: self-updating Mac apps from GitHub

How to make any native macOS app update itself: **push to `main` → GitHub builds and publishes → every installed copy updates the next time it's opened.** No paid Apple account, no server, nothing but GitHub and [Sparkle 2](https://sparkle-project.org).

This was built and verified end to end on the *Situations* app (`martyvasquez/baseball-simulator`). Everything below is what actually worked there, including the problems hit along the way. Use that repo as the reference implementation: `ios/SituationSim/Model/AppUpdater.swift`, `ios/project.yml`, `.github/workflows/release-mac.yml`.

---

## 1. How it works

```text
git push (main, app files changed)
   ↓
GitHub Actions (macos-26 runner)
   test → build Release (universal, ad-hoc signed, build # = run # + 100)
   → zip → Sparkle generate_appcast (signs zip with EdDSA private key from a repo secret)
   → gh release create build-N  Situations.zip + appcast.xml  --latest
   ↓
Installed app launches
   → Sparkle fetches  https://github.com/OWNER/REPO/releases/latest/download/appcast.xml
   → newer build? download zip → verify EdDSA signature → replace app → relaunch
```

**Trust model.** Without a paid Apple Developer account there's no Developer ID signing or notarization, so builds are *ad-hoc* signed. Authenticity comes from Sparkle's own EdDSA signature: the app ships with the public key and refuses any update not signed with the private key, which lives only in the developer's keychain and a GitHub secret. (Verified in Sparkle's source: an update is accepted if *either* the EdDSA signature *or* Apple code signing validates, so a valid EdDSA signature is enough even though each ad-hoc build's signature differs.) Tested both ways: a signed update installed; a tampered zip was downloaded and rejected.

**Cost of not paying Apple:** the *first* install on each Mac shows "Apple could not verify…", and the user clicks **Open Anyway** once. Updates after that don't prompt, because Sparkle handles them.

---

## 2. Requirements

- The app's GitHub repo is **public** (installed apps download the feed and zip without credentials). Never embed a GitHub token in an app. For a private-source app, publish releases from a separate public repo.
- Xcode on the dev Mac; GitHub's `macos-26` runner for CI (it's the current `macos-latest`).
- `gh` CLI logged in with the **`workflow`** scope, or pushes that add workflow files are rejected: `gh auth refresh -h github.com -s workflow` (interactive browser approval — the human has to run it).
- A native macOS target (SwiftUI or AppKit), deployment target macOS 14+ if you use `@Observable` (Sparkle itself supports older).

---

## 3. Step by step

Replace `APP` (product name, e.g. `Situations`), `SCHEME`, `PROJECT`, `BUNDLE_ID`, `OWNER/REPO` throughout.

### Step 1 — Add Sparkle

Swift Package Manager, `https://github.com/sparkle-project/Sparkle`, version 2.x (Situations uses 2.10.0), added to the **Mac app target only**. With XcodeGen:

```yaml
packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    majorVersion: 2.6.0
targets:
  MyAppMac:
    dependencies:
      - package: Sparkle
```

Commit `Package.resolved` (`*.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`) to pin the version. After the package resolves, Sparkle's command-line tools are at `<DerivedData>/SourcePackages/artifacts/sparkle/Sparkle/bin/` (`generate_keys`, `generate_appcast`, `sign_update`). CI uses the same path.

### Step 2 — Build settings and Info.plist

| Setting | Value | Notes |
|---|---|---|
| `CFBundleVersion` | `$(CURRENT_PROJECT_VERSION)` | **Gotcha:** XcodeGen's generated Info.plist hard-coded `1`, so CI's build-number override silently did nothing. Make sure it's the variable. |
| `CFBundleShortVersionString` | `$(MARKETING_VERSION)` | Human version (1.0); change only for milestones. |
| `SUFeedURL` | `https://github.com/OWNER/REPO/releases/latest/download/appcast.xml` | "latest release" link: no web host, and nothing committed back to `main`. |
| `SUPublicEDKey` | from `generate_keys` (step 3) | |
| `SUEnableAutomaticChecks` | `YES` | Also suppresses Sparkle's "check automatically?" prompt. |
| `SUAutomaticallyUpdate` | `YES` | Download and install without asking. |
| `SUVerifyUpdateBeforeExtraction` | `YES` | Verify the signature before unzipping. Recommended when you're not using Developer ID. |
| `ENABLE_HARDENED_RUNTIME` | `NO` | **Gotcha:** with ad-hoc signing, hardened runtime's library validation stops the app from loading `Sparkle.framework`. Only turn it on together with Developer ID + notarization. |
| App Sandbox | off (simplest) | A sandboxed app needs Sparkle's XPC-service setup; see Sparkle's sandboxing docs. |

### Step 3 — Signing keys (once per app)

```sh
BIN=<DerivedData>/SourcePackages/artifacts/sparkle/Sparkle/bin
$BIN/generate_keys --account BUNDLE_ID      # prints the public key; private key goes into the login keychain
```

Use a per-app `--account` so each app has its own key. Put the printed public key in `SUPublicEDKey`.

Store the private key as a repo secret **without printing it**. **Gotcha:** `generate_keys -x` refuses any path that already exists, including `/dev/stdout` and a named pipe (it prints "private-key-file already exists"). What works:

```sh
D=$(mktemp -d) && chmod 700 "$D"
$BIN/generate_keys --account BUNDLE_ID -x "$D/k" >/dev/null 2>&1
gh secret set SPARKLE_PRIVATE_KEY --repo OWNER/REPO < "$D/k"
rm -P "$D/k"; rmdir "$D"
gh secret list --repo OWNER/REPO            # confirm it's there
```

The keychain entry is the backup. **If the key is lost, installed copies can never be updated** — each Mac would need a manual reinstall of a build with a new public key. Sparkle lets you rotate *either* the EdDSA key *or* the Apple signing identity in one release, never both.

### Step 4 — The updater (Swift)

```swift
#if os(macOS)
import Sparkle

/// Keeps the Mac app up to date from GitHub Releases. Checks on launch, downloads
/// in the background, and relaunches on the new version as soon as it's ready.
@MainActor
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()

    private var controller: SPUStandardUpdaterController?

    /// Start the updater and check for a new build right away.
    func start() {
        #if !DEBUG // Development builds shouldn't replace themselves with published ones.
        guard controller == nil else { return }
        let c = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        controller = c
        c.updater.checkForUpdatesInBackground()
        #endif
    }

    var canCheck: Bool { controller != nil }

    /// "Check for Updates…" in the app menu.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    // Install as soon as the update is downloaded instead of waiting for the app to quit.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        immediateInstallHandler()
        return true
    }
}
#endif
```

Why each piece:
- `checkForUpdatesInBackground()` at launch gives the "updated next time it's opened" behavior. By default Sparkle only checks on a schedule (about daily) and skips the very first launch.
- The `willInstallUpdateOnQuit` delegate method makes it install and relaunch right away. Without it, `SUAutomaticallyUpdate` waits until the user quits, so the update would only show up on the launch *after* next.
- The `#if !DEBUG` guard stops Xcode runs from replacing themselves with the published build.

SwiftUI wiring (`App`):

```swift
#if os(macOS)
init() { AppUpdater.shared.start() }
#endif

var body: some Scene {
    WindowGroup { ContentView() }
    #if os(macOS)
    .commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { AppUpdater.shared.checkForUpdates() }
                .disabled(!AppUpdater.shared.canCheck)
        }
    }
    #endif
}
```

AppKit: call `start()` in `applicationDidFinishLaunching` and add a menu item after "About" whose action calls `checkForUpdates()`.

### Step 5 — The release workflow

`.github/workflows/release-mac.yml` (the Situations version, parameterized):

```yaml
# Publishes the Mac app on every push to main that changes it. Installed copies
# check this repo's latest release when they launch and update themselves.
name: Release Mac app

on:
  push:
    branches: [main]
    paths:
      - "PATH/TO/APP/**"            # only app changes publish; README/docs pushes don't
      - ".github/workflows/release-mac.yml"
  workflow_dispatch:                 # "Run workflow" button for manual releases

permissions:
  contents: write

concurrency:
  group: release-mac
  cancel-in-progress: false

env:
  PROJECT: PROJECT.xcodeproj
  SCHEME: SCHEME
  # No paid Apple account: ad-hoc signing. Trust comes from the Sparkle signature.
  SIGNING: CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=

jobs:
  release:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4

      - name: Xcode version
        run: xcodebuild -version

      - name: Test
        run: xcodebuild test -project "$PROJECT" -scheme "$SCHEME" -destination platform=macOS -derivedDataPath build $SIGNING

      - name: Build
        run: |
          # Build numbers always go up; the offset keeps them above hand-made test builds.
          BUILD=$((GITHUB_RUN_NUMBER + 100))
          echo "BUILD=$BUILD" >> "$GITHUB_ENV"
          xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
            -destination "generic/platform=macOS" -derivedDataPath build \
            CURRENT_PROJECT_VERSION=$BUILD $SIGNING

      - name: Package and sign the update
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: |
          mkdir release
          ditto -c -k --keepParent build/Build/Products/Release/APP.app release/APP.zip
          echo "$SPARKLE_PRIVATE_KEY" | build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast \
            --ed-key-file - \
            --download-url-prefix "https://github.com/${GITHUB_REPOSITORY}/releases/download/build-${BUILD}/" \
            release

      - name: Publish release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release create "build-$BUILD" release/APP.zip release/appcast.xml \
            --title "APP build $BUILD" \
            --notes "$(git log -1 --pretty=%s)" \
            --latest
```

Notes:
- `-destination "generic/platform=macOS"` + the Release configuration produces a **universal** binary (Intel and Apple Silicon); check with `lipo -archs`.
- `generate_appcast` writes `appcast.xml` into the `release` folder with a single item pointing at this release's zip. Each release carries its own `appcast.xml`, and `releases/latest/download/appcast.xml` always resolves to the newest, so nothing is committed back to the repo.
- **Run numbers are per workflow file.** Renaming or recreating the file restarts at 1 and new builds would look older than installed ones. Never rename it, or raise the offset first.
- Tests run on the Mac runner with the same ad-hoc signing flags, so if your test target has a custom product name, set `TEST_HOST` explicitly (Situations: `$(BUILT_PRODUCTS_DIR)/Situations.app/Contents/MacOS/Situations`).
- Expect about 2–3 minutes per run. `actions/checkout@v4` currently triggers a harmless Node.js deprecation notice; `@v5` avoids it.

### Step 6 — Test locally before the first push

Do this once per app to prove the update loop before involving GitHub. Two gotchas decide how:
- **`file://` feeds don't work** — Sparkle recorded a check time but never updated.
- **A local HTTP server on `127.0.0.1` does** (App Transport Security allows plain HTTP to IP addresses), and its access log shows exactly what the app requested.

```sh
BIN=<DerivedData>/SourcePackages/artifacts/sparkle/Sparkle/bin
T=$(mktemp -d); mkdir -p "$T/feed" "$T/installed"
build() { xcodebuild build -project PROJECT.xcodeproj -scheme SCHEME -configuration Release \
  -destination generic/platform=macOS -derivedDataPath "$T/dd" CURRENT_PROJECT_VERSION=$1 \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= ; }

build 5 && ditto "$T/dd/Build/Products/Release/APP.app" "$T/installed/APP.app"              # "old" installed copy
build 6 && ditto -c -k --keepParent "$T/dd/Build/Products/Release/APP.app" "$T/feed/APP.zip"  # "new" release

# Sign the new build into a feed (key exported to a private temp file, then erased)
$BIN/generate_keys --account BUNDLE_ID -x "$T/key" >/dev/null 2>&1
$BIN/generate_appcast --ed-key-file "$T/key" --download-url-prefix "http://127.0.0.1:8799/" "$T/feed"
rm -P "$T/key"

# Point the old copy at the local feed; re-sign after editing its Info.plist
plutil -replace SUFeedURL -string "http://127.0.0.1:8799/appcast.xml" "$T/installed/APP.app/Contents/Info.plist"
codesign --force --deep -s - "$T/installed/APP.app"
defaults delete BUNDLE_ID SULastCheckTime 2>/dev/null

(cd "$T/feed" && python3 -m http.server 8799 --bind 127.0.0.1) &   # watch its log
open "$T/installed/APP.app"
# Within ~5 s: the server logs GET /appcast.xml and GET /APP.zip,
# and CFBundleVersion of $T/installed/APP.app becomes 6.
```

**Tamper test** (do it once): publish a signed build 7, then replace the zip with a different one after signing. The app should download it, refuse it, and stay on 6.

### Step 7 — First real release

1. Push (needs the `workflow` scope) → build `N` is published. Check `gh release list` and download `releases/latest/download/appcast.xml` to confirm it advertises `N`.
2. Download the zip the way a user would and check it: `CFBundleVersion`, `SUFeedURL`, `lipo -archs`, `codesign --verify --deep --strict`.
3. Run the workflow again (`gh workflow run release-mac.yml`) to publish `N+1` with no code change. Open the installed `N` → it should be `N+1` within seconds.

---

## 4. Installing on a Mac (share with the family)

1. Download `APP.zip` from `https://github.com/OWNER/REPO/releases/latest`.
2. Double-click it and drag the app into **Applications**.
3. Open it → "Apple could not verify…" → **Done** → **System Settings → Privacy & Security → Open Anyway** → confirm. The button only shows for about an hour after the blocked attempt. Or in Terminal: `xattr -dr com.apple.quarantine /Applications/APP.app`.

Updates after that are automatic.

**Standard (non-admin) user accounts:** if the app is in `/Applications` but was installed by an admin, the user can't replace it and each update asks for an admin password. Install into the user's own `~/Applications` instead.

A copy installed *before* the updater was added (e.g. from a flash drive) can't update itself — replace it once with a release download.

---

## 5. Day-to-day rules

- **Pushing app changes to `main` ships them to everyone.** Tests gate the release, but anything that passes goes out.
- **Don't set build numbers by hand**; CI does it. Change `MARKETING_VERSION` only for milestones.
- **Never change** the feed URL, public key, bundle ID, asset names (`APP.zip`, `appcast.xml`), or tag format (`build-N`), and don't mark releases as prerelease. Installed copies depend on all of them. Keep the repo public.
- **An open app doesn't update mid-session**; it checks on launch (and about daily while open). **Check for Updates…** forces it.
- **iPad/iPhone are not covered.** Sparkle is Mac-only; the iOS equivalent is TestFlight (paid account).

---

## 6. Upgrading to a paid account later (optional)

With the Apple Developer Program you can remove the first-install warning:
1. Create a **Developer ID Application** certificate; import it (as a `.p12`) plus notarization credentials into GitHub secrets.
2. In CI, sign with Developer ID, turn **hardened runtime on**, notarize (`xcrun notarytool submit --wait`), and staple before zipping.
3. Keep the **same EdDSA key**. Sparkle accepts changing the Apple signing identity as long as the EdDSA key stays the same (never change both in one release), so existing ad-hoc installs update straight to the notarized builds.

---

## 7. Checklist for a new app

- [ ] Public repo (or a public releases repo)
- [ ] Sparkle 2 via SPM on the Mac target; `Package.resolved` committed
- [ ] `CFBundleVersion = $(CURRENT_PROJECT_VERSION)`, `CFBundleShortVersionString = $(MARKETING_VERSION)`
- [ ] `SUFeedURL` (latest-release link), `SUPublicEDKey`, `SUEnableAutomaticChecks`, `SUAutomaticallyUpdate`, `SUVerifyUpdateBeforeExtraction`
- [ ] Hardened runtime off (unless notarizing); sandbox off (or Sparkle XPC setup)
- [ ] `generate_keys --account BUNDLE_ID`; private key → `SPARKLE_PRIVATE_KEY` secret via temp file; keychain kept as backup
- [ ] `AppUpdater` started at launch (not in Debug) with immediate install; **Check for Updates…** menu item
- [ ] `release-mac.yml` with `paths` filter, run number + offset, ad-hoc signing, `generate_appcast`, `gh release create --latest`
- [ ] `gh` has `workflow` scope
- [ ] Local 127.0.0.1 update test and tamper test pass
- [ ] Real two-release test passes (build N updates itself to N+1)
- [ ] Install instructions shared; non-admin users install to `~/Applications`
