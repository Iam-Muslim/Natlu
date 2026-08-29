# iOS deployment

Two ways to ship this app to Apple:

- **From a Mac** — `bundle exec fastlane ship_ios`, the fastest loop while iterating.
- **From GitHub Actions** — the *06 - Deploy iOS (signed)* workflow, so someone on Windows
  (or anyone without a Mac) can release without touching one. GitHub's macOS
  runners are free for public repositories.

Both paths run the same fastlane lanes, so they cannot drift apart.

---

## App identity

| | |
|---|---|
| Bundle ID | `com.recitequran.app` |
| Apple team | `ZKQ5264RUS` — Abdeljawad Almiladi |
| App Store name | Recite Quran - اتلو القران |
| Display name | `Recite Quran` (English), `اتلو القران` (Arabic) |
| Minimum iOS | 15.0 |
| App Store Connect API key | `ZJUS9VF3D6` (shared with the Al Najma and Jibly projects) |

The ASR model is **not** in the repo. It is a 69 MB asset on the
[`models-latest`](https://github.com/Iam-Muslim/Natlu/releases/tag/models-latest)
release, fetched automatically by every build path. Upstream it lives in a gated
HuggingFace repo under the Quran-Lab NPL-1.2 licence, which is why it is not
committed.

---

## One-time setup

Do this once, on a Mac, before the first release.

### 1. Install the toolchain

```bash
brew install ruby cocoapods gh
PATH="/opt/homebrew/opt/ruby/bin:$PATH" bundle install
```

fastlane 2.236 needs Ruby 3+, so it must run under the Homebrew Ruby rather than
macOS's built-in 2.6. Every command below assumes that `PATH` prefix.

### 2. Put the API key in place

```bash
mkdir -p secrets
cp /path/to/AuthKey_ZJUS9VF3D6.p8 secrets/
chmod 600 secrets/AuthKey_ZJUS9VF3D6.p8
```

`secrets/` is gitignored. Nothing in it may ever be committed.

### 3. Create the App Store Connect record — by hand

The bundle ID `com.recitequran.app` is **already registered** on the developer
portal (`6Y9927RW9W`), so signing works. What is still missing is the App Store
Connect *listing*.

That one step cannot be scripted. fastlane's `produce` action only supports Apple
ID + password authentication — it predates App Store Connect API keys — and
Apple's API has no endpoint for creating an app record at all. So:

1. Sign in to [App Store Connect](https://appstoreconnect.apple.com/apps).
2. **Apps → +  → New App**.
3. Platform **iOS**, bundle ID **com.recitequran.app**, name
   **Recite Quran - اتلو القران**, primary language **Arabic**, SKU
   `com.recitequran.app`.

`bundle exec fastlane ios_status` reports `TestFlight latest build = n/a` until
this exists. Nothing else needs it — the certificate and profile below work
without it.

### 4. Provisioning profile

```bash
bundle exec fastlane make_profile
```

Creates and installs the `ReciteQuran AppStore` profile for
`com.recitequran.app`.

This lane deliberately does **not** create a certificate. The team already has
one Apple Distribution certificate (expiring 2027-02-03) that Al Najma, Jibly and
every other project signs with, and Apple caps a team at a small number of them —
creating another, or revoking this one, would break signing everywhere else.

### 5. Export the certificate for CI

GitHub Actions needs the distribution certificate *and its private key* as a
`.p12`. Exporting a private key always raises a keychain prompt, so it cannot be
scripted — do it once by hand:

1. **Keychain Access → login → My Certificates**
2. Find **Apple Distribution: Abdeljawad Almiladi (ZKQ5264RUS)**
3. Right-click → **Export** → save as `secrets/ReciteQuran_dist.p12`
4. Set a password and keep it — that is `IOS_DIST_CERT_PASSWORD` below

### 6. Hand the signing material to GitHub Actions

```bash
bundle exec fastlane ci_bundle
```

Writes `secrets/ci_secrets.txt` containing three base64 blobs. Add each as a
repository secret under **Settings → Secrets and variables → Actions**, then
delete the file.

| Secret | Where it comes from |
|---|---|
| `IOS_DIST_CERT_P12` | `ci_bundle` output |
| `IOS_DIST_CERT_PASSWORD` | the password you chose in step 5 |
| `IOS_PROVISIONING_PROFILE` | `ci_bundle` output |
| `ASC_KEY_P8` | `ci_bundle` output |

```bash
rm secrets/ci_secrets.txt
```

---

## Releasing from a Mac

```bash
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"

bundle exec fastlane ios_status    # what is on TestFlight right now
bundle exec fastlane ship_ios      # bump build number, build, upload to TestFlight
bundle exec fastlane beta          # once processed: send to external testers
bundle exec fastlane release_ios   # submit to App Store review
```

`ship_ios` refuses to start if the marketing version in `pubspec.yaml` is already
on App Store Connect, because Apple only rejects a duplicate version at the very
end of a submission — after a full archive has been built and uploaded. Bump
`version:` in `pubspec.yaml` for each release; the build number after the `+`
is managed automatically.

---

## Releasing from GitHub (no Mac)

1. Open the repository's **Actions** tab.
2. Choose **06 - Deploy iOS (signed)** in the sidebar.
3. Click **Run workflow** and pick an action:

| Action | What it does | Needs signing secrets |
|---|---|---|
| `unsigned` | Compiles only. A smoke test that the app still builds. | no |
| `testflight` | Builds a signed IPA and uploads it to TestFlight. | yes |
| `beta` | Sends the last processed build to the external testers group. | API key only |
| `appstore` | Submits the last TestFlight build to App Store review. | API key only |

Optionally set **marketing_version** (e.g. `1.0.3`) to override `pubspec.yaml`
for that run.

A `testflight` run takes roughly 25–40 minutes; most of it is the Xcode archive.
The finished IPA is attached to the run as an artefact for 14 days. On failure,
the gym and fastlane logs are attached instead — that is the first place to look.

### The normal release sequence

```
testflight  →  wait for Apple to finish processing (5-30 min)  →  beta  →  appstore
```

`beta` and `appstore` do not rebuild anything. They act on the binary already
sitting on TestFlight, so they finish in a couple of minutes.

### Notes

- Runs are serialised by a concurrency group. Two builds at once would race for
  the same TestFlight build number.
- The build number bump happens on the runner and is deliberately **not**
  committed back. The next build number is derived from what TestFlight already
  has, so nothing drifts even though the repo is never written to.
- Signing is switched from automatic to manual on the runner only, because a CI
  machine has no Xcode account to resolve a profile with. Your checkout is
  untouched.

---

## Notes on the build

**`recite_quran` comes from GitHub, not pub.dev.** The published 1.0.1 package
runs the ASR model on the plain CPU execution provider on iOS. The CoreML
provider — which uses the Neural Engine — landed in
[`Iam-Muslim/ReciteQuran#4`](https://github.com/Iam-Muslim/ReciteQuran/pull/4)
and has not been released to pub.dev yet, so `pubspec.yaml` points at the
package's default branch. Switch back to a `^x.y.z` constraint once a release
containing it ships.

**`sherpa_onnx` is pinned to 1.13.5, and must stay pinned.** In 1.13.6 the iOS
package renamed its bundle to `sherpa-onnx.xcframework` but left the framework
inside it called `SherpaOnnxC.framework`. CocoaPods derives the linker flag from
the bundle name, so it emits `-framework "sherpa-onnx"` and every iOS archive
fails at link time with `Framework 'sherpa-onnx' not found`. 1.13.5 ships
`SherpaOnnxC.xcframework`, where the two names agree. `sherpa_onnx_ios` is pinned
separately under `dependency_overrides` because `sherpa_onnx` 1.13.5 still
accepts `^1.13.5` for it and would otherwise pull 1.13.6 back in transitively.
Before loosening either pin, build an iOS archive and confirm it links.

**`permission_handler` is compiled down to microphone only.** It otherwise
compiles in every permission it supports, leaving the binary referencing
Contacts, Photos, Camera and Bluetooth APIs that this app never uses and has no
`NS*UsageDescription` for — a routine App Review rejection. The `PERMISSION_MICROPHONE=1`
macro in `ios/Podfile` keeps only the one that is actually needed.

**Export compliance is pre-declared.** `ITSAppUsesNonExemptEncryption` is `false`
in `Info.plist` — the app does no encryption of its own, and recitation never
leaves the device — so TestFlight will not ask about it on every upload.

**A privacy manifest ships in the app.** `ios/Runner/PrivacyInfo.xcprivacy`
declares no tracking and no data collection, and gives Apple's required reasons
for the two API categories the app touches (`UserDefaults` for settings,
file timestamps for the model it extracts from its own bundle).

---

## Troubleshooting

**The workflow does not appear on the Actions tab.** As of 2026-08-29 GitHub
had not indexed `06_deploy_ios.yml`, even though it sits on the default branch
and is valid YAML. A deliberately trivial probe workflow pushed alongside it was
not indexed either, which rules out this file's contents — GitHub is not picking
up *any* newly added workflow on this repo, while the four pre-existing ones
keep running normally.

The likeliest cause is the non-ASCII default branch name,
`ReciteQuran-الحمدلله`. Two things to try, cheapest first:

1. Open the repository's **Actions** tab in a browser. The UI sometimes registers
   a workflow that the API has not surfaced yet.
2. Rename the default branch to something ASCII, e.g. `main`. The existing
   workflows already list `main` among their trigger branches, so nothing else
   should need changing.

Until it registers, releases still work from a Mac — `bundle exec fastlane
ship_ios` runs the identical lane the workflow would.

**`No IPA in build/ios/ipa/`** — the archive succeeded but the export failed,
almost always signing. Locally, open `ios/Runner.xcworkspace` in Xcode and check
the Signing & Capabilities tab. On CI, check that all four secrets are present
and that the provisioning profile has not expired (they last a year).

**`CocoaPods installed but broken`** during a fastlane build — Homebrew Ruby's
gem environment leaking into the `pod` subprocess. `build_ios` in the Fastfile
already strips those variables; if you are invoking `flutter build` by hand, do
the same or use a plain shell.

**Apple rejects the build number** — something else uploaded the same number.
`bundle exec fastlane ios_status` shows what TestFlight has; the next `ship_ios`
picks up from there automatically.

**`The version number has been previously used`** — bump `version:` in
`pubspec.yaml`. `ship_ios` checks this up front, but the `appstore` CI action
submits an already-uploaded binary and cannot.
