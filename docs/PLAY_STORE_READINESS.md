# Can ReplyMate be published on Google Play?

An audit, not a promise. Everything below was checked against the code in this
repository, the signed artifacts on the `v1.5.0` GitHub Release, and Google
Play's policies as they stand in November 2026. Nothing was uploaded and nothing
was built locally (this repository never builds APKs/AABs on a dev machine).

**Short answer: the app is technically publishable today — a signed AAB already
exists and would be accepted as an upload — but it would be rejected in review
as it stands.** The blockers are three policy items and two console forms, not
code. One of them (`isAccessibilityTool`) is a one-line fix that this repository
deliberately set the other way for sideloading.

---

## 1. What is verified working

| Item | Evidence |
|---|---|
| Signed **AAB** exists for upload | `v1.5.0` release asset `ReplyMate-AI-v1.5.0.aab` (61.8 MB) |
| Signed with a **real upload key**, not the debug key | `META-INF/UPLOAD.RSA` inside the AAB → `subject=CN=Keshab Sarkar, O=Keshab Studios, C=IN`, valid to 2054. A debug-signed bundle would read `CN=Android Debug` and Play would refuse it |
| `targetSdk` = **36** | `android/gradle` resolves `flutter.targetSdkVersion` → `FlutterExtension.kt` = 36. Play requires API 36 for new apps and updates since **31 Aug 2026** (extension window closed 1 Nov 2026) |
| `compileSdk` 36, `minSdk` 24, 64-bit | same files; AGP 9.3.1, Kotlin 2.4.20, JVM 17 |
| Bundle size under limits | 61.8 MB base, Play's base-module ceiling is 200 MB |
| `versionCode` / `versionName` | 5 / 1.5.0, both read from `pubspec.yaml` |
| Package id | `com.keshabstudios.replymate` |
| **INTERNET** permission in the release manifest | checked inside the released APK's binary manifest: `android.permission.INTERNET` is present. It arrives through a **transitive** library manifest, not ours — see §4 |
| 512×512 store icon | `distribution/play_store_512.png` |
| Release notes for Play | `distribution/whatsnew/whatsnew-en-US`, `whatsnew-bn-BD` |
| CI gates | `dart format` → `flutter analyze --fatal-infos` → `flutter test` (345 tests), green on `main` |
| Release pipeline | `.github/workflows/publish-release.yml` → reusable `publish-release.yml@v1.16.0`, signed + Play opt-in, has actually run and produced v1.5.0 (so the signing secrets exist) |

---

## 2. Blockers — Play will not approve these

### 2.1 `isAccessibilityTool="true"` on a non-accessibility app (hard blocker)

`android/app/src/main/res/xml/screen_reader_service_config.xml` declares:

```xml
android:isAccessibilityTool="true"
```

The file's own comment says this was set deliberately for a **sideloaded,
personal build**, and `README.md` says plainly that ReplyMate "is not
[an accessibility tool] and does not claim to be".

For Play those two statements cannot both be true: setting the flag on an app that is not a
disability tool is one of the named rejection causes in the 2026 sensitive
permissions policy.

> **Decision (owner, November 2026): left as `true` for now.** Nothing in this
> codebase reads the flag — the reader works through `canRetrieveWindowContent`
> and `rootInActiveWindow` — so the flag was kept only to hold the Advanced
> Protection Mode exemption on Android 17+ for the owner's own sideloaded build.
> It must become `false`, together with the disclosure and declaration below,
> before any Play submission. Do not flip it silently.

What Play requires instead, for an app that is *not* an accessibility tool but
does use the API:

1. `android:isAccessibilityTool="false"` (the platform default, stated
   explicitly) — a one-line change;
2. a **prominent in-app disclosure** with affirmative consent **before** the
   user is sent to the system toggle — this repository already has one
   (`capture_screen.dart`, `screenReadingDisclosureTitle/Body`), so the copy is
   the thing to review against the policy wording;
3. the **Accessibility API declaration form** in Play Console, with the narrow
   purpose and a **demo video** showing the disclosure, both "agree" and
   "decline", and the feature it enables;
4. the same disclosure stated in the store listing description.

Note for later: from Android 17, Advanced Protection Mode revokes accessibility
access for any app that is not classified as an accessibility tool, whatever the
config says. That is a platform fact, not a Play decision — screen reading will
simply be unavailable for users who enable that mode.

### 2.2 No privacy policy URL (hard blocker)

Play requires a reachable privacy policy for every app, and this one reads
notifications, which makes it non-negotiable. There is no policy in the repo and
no URL anywhere. The repository already publishes GitHub Pages, so
`https://keshab1997.github.io/ReplyMate-AI/privacy/` is the cheapest honest
home for it — it must state: what is read (the notification you answer, or the
visible chat when screen reading is on), where it goes (the AI provider you
configured, plus your own Firestore if you use the pool), what is stored (reply
cache, budget counters, conversation memory on device only), and how to delete
all of it.

### 2.3 The console declarations (each one can hold a release)

| Form | What it must say for this app |
|---|---|
| **Data safety** | Message text is shared with a third-party AI provider (OpenRouter / Google AI Studio) at the moment of the request and is not retained server-side; conversation memory and the reply cache stay on device; the admin sign-in collects an email address; no ads; traffic is HTTPS |
| **Foreground service — `specialUse`** | Justification text for "floating reply bubble". Already declared in the manifest with `PROPERTY_SPECIAL_USE_FGS_SUBTYPE`, which is what the form asks for |
| **Accessibility API** | see §2.1 |
| **Ads** | No ads |
| **Content rating** | questionnaire; no user-generated content, no ads, no purchases |
| **Target audience** | adults; the app drafts replies to personal messages |
| **Account deletion** | only if the admin Google sign-in counts as an account for Play's purposes — decide this before submitting |

### 2.4 Closed testing, if the developer account is personal and new

If the Play Console account is a **personal** account created after
13 November 2023, production access needs a closed test with **at least 12
testers opted in continuously for 14 days**, and since 2026 Google also looks at
whether those testers actually used the app. Organization accounts and older
personal accounts are exempt. Internal testing does not count.

---

## 3. Risks — allowed, but likely to be questioned

- **The name.** "ReplyMate AI" is already a Play app (`com.replymate.sylvie`,
  "ReplyMate AI – Smart Replies"), and "Reply Mate" is another live Play app.
  Two existing apps with the same name is a trademark/impersonation complaint
  waiting to happen, and it makes the listing hard to find. Pick a distinct
  title before submitting; the package id is unaffected.
- **Notification-listener access** is the app's core mechanism, which is the
  right justification, but "reads your notifications" apps are reviewed closely.
  The listing and the in-app copy have to lead with *what it does for the user*,
  and reviewers need to be able to see the feature work — ship the build with a
  `google-services.json` so a reviewer is not left in guest mode.
- **`specialUse` foreground service** for a floating bubble is defensible but
  not automatic; the fallback notification path is the argument that the app
  still works if the bubble is refused.
- **The key pool is read by the client.** Play does not review this, but
  shipping a shared AI key pool to reviewers invites questions about who pays.
  BYOK-first is the safer story, and the one the README already tells.
- **Hindi strings** are unreviewed by a native speaker (README says so). Not a
  blocker, but a reviewable-quality issue once the app is public.
- **16 KB page sizes**: from 1 February 2027, updates to apps with native
  libraries must support 16 KB pages. Flutter 3.50 is expected to be fine;
  re-check at that release, not now.
- `checkReleaseBuilds = false` in `android/app/build.gradle.kts` turns off
  `lintVital` for release builds. Play does not care; it does mean the release
  build is the one place a lint-only problem can slip through.

---

## 4. One thing worth fixing even though it is not a blocker

> **Done.** `android/app/src/main/AndroidManifest.xml` now declares
> `android.permission.INTERNET` itself. The paragraph below is kept as the
> reason, not as a to-do.

The release manifest gets `android.permission.INTERNET` from a **transitive**
library's manifest, not from ours — the app's own `src/main/AndroidManifest.xml`
never declares it (only the debug and profile ones do, which is Flutter's
default). It works today because Firebase/Firestore's manifest declares it, and
that is exactly the kind of thing that breaks silently the day the Firebase
dependency changes: a release build with no INTERNET permission loses AI,
Firestore and the web preview at once, while every debug build keeps working.

Declaring it in `src/main/AndroidManifest.xml` costs one line and removes the
dependency on somebody else's merge.

---

## 5. What is missing from the store listing itself

| Asset | State |
|---|---|
| Icon 512×512 | present (`distribution/play_store_512.png`) |
| Feature graphic 1024×500 | **missing** |
| Phone screenshots (2–8, min 320 px) | **not produced for the listing**, but the local screenshot tool renders 780×1688 PNGs of every screen — this is now a five-minute job, not a design project |
| Short description (≤80 chars) | not written |
| Full description (≤4000 chars) | not written; must include the accessibility disclosure (§2.1) |
| Release notes | present, bn-BD and en-US |

---

## 6. Order of work I would follow

1. Flip `isAccessibilityTool` to `false`; re-read the disclosure copy against
   the policy; record the demo video. *(code + one recording)*
2. Write and publish the privacy policy on Pages. *(docs)*
3. Produce the listing: feature graphic, six screenshots from
   `python3 tool/local_screenshots.py`, short and full description.
4. Fix the INTERNET declaration while touching the manifest anyway.
5. Create the Play listing, fill Data safety, FGS and Accessibility
   declarations, content rating, ads.
6. Upload `v1.5.0`-style AAB to **internal** testing, then closed testing with
   12 testers for 14 days if the account needs it, then production.

Steps 1–4 are work in this repository; 5–6 happen in Play Console, where the
owner's decisions (account type, name, whether the key pool ships) are the
inputs.

---

## মানুষের জন্য — এক নজরে

- **হ্যাঁ, চেষ্টা করা যাবে** — signed AAB আগেই তৈরি (v1.5.0), upload key আসল,
  targetSdk 36, সব CI সবুজ। অর্থাৎ bundle বানানো বা sign করার সমস্যা নেই।
- **কিন্তু এখনই submit করলে review-তে আটকাবে**, কারণ:
  1. `isAccessibilityTool="true"` — অ্যাপটা accessibility tool নয় (README নিজেই
     বলছে)। Play-তে এটা সরাসরি rejection কারণ; `false` করতে হবে + disclosure
     + declaration form + ভিডিও।
  2. **Privacy policy URL নেই** — Play-তে বাধ্যতামূলক।
  3. Console-এর form গুলো (Data safety, specialUse FGS, Accessibility, content
     rating) এখনো ভরা হয়নি।
  4. Personal account হলে **১২ জন tester × ১৪ দিন** closed testing লাগবে।
- **নাম নিয়ে ভাবা দরকার** — "ReplyMate AI" নামে Play-তে আগেই একটা অ্যাপ আছে।
- Listing-এর ছবি/feature graphic নেই — কিন্তু screenshot tool দিয়ে সেগুলো
  মিনিটের কাজ।
- কিছুই publish করা হয়নি, কিছুই upload করা হয়নি।
