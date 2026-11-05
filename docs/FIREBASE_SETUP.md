# Firebase Setup

Everything the code expects from a Firebase project, in the order to click it.
The repo never contains `google-services.json`; the file lives on each
developer machine and in CI secrets only.

## 1. Console steps

1. Create a project (any name; the package identity comes from Android).
2. **Authentication → Sign-in method → Google**: enable. Nothing else.
3. **Firestore Database**: create (production mode; the rules below replace
   the defaults).
4. **Project settings → My apps → Add app → Android**, package name
   `com.keshabstudios.replymate` (must match `applicationId` exactly).
5. Download **google-services.json** and place it at `android/app/`.
   Do not commit it: `.gitignore` already refuses, and AGENTS.md lists it as
   a secret-class file.
6. Rebuild. With the file present the gradle plugin applies, Firebase boots,
   the admin entry appears in Settings and reply generation switches from
   *not configured* to the key pool. Without it, nothing changes: guest mode.

## 2. Collections

| Collection | Written by | Read by | Purpose |
|---|---|---|---|
| `admin_api_keys` | admin screen | app (any signed-in user - see the trade-off note) | the key pool: `name, key, baseUrl, model, provider, isActive, priority, usageCount, errorCount` |
| `admin_key_groups` | admin screen | app | per-provider cooldown / priority config |
| `api_error_logs` | app (batched) | admin | failure history shown in the admin screen |
| `admin_config` (doc `access`) | hand-edited once | app | the admin allowlist |

Create `admin_config/access` by hand once:

```json
{
  "emails": ["your-google-account@example.com"],
  "uids": []
}
```

Emails are enough to get in; add a uid later if you want the list to survive
an email change. The app reads this doc on every admin-screen open, so adding
an admin never needs a release.

## 3. Firestore rules

```text
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function adminEmails() {
      return get(/databases/$(database)/documents/admin_config/access)
          .data.get('emails', []);
    }
    function adminUids() {
      return get(/databases/$(database)/documents/admin_config/access)
          .data.get('uids', []);
    }
    function isAdmin() {
      return request.auth != null && (
        request.auth.token.email in adminEmails() ||
        request.auth.uid in adminUids()
      );
    }

    // The allowlist itself: any signed-in user may read it (it contains no
    // secrets, and the app needs it to decide whether to show the admin
    // entry); only admins may change it.
    match /admin_config/{doc} {
      allow read: if request.auth != null;
      allow write: if isAdmin();
    }

    // ARCHITECTURE A TRADE-OFF (see docs/API_SECURITY.md "Key-pool
    // decision"): the client must read keys to call providers directly, so
    // every signed-in user can read the pool. Treat pooled keys as
    // disposable free-tier consumables, never as production credentials.
    // Writes stay admin-only.
    match /admin_api_keys/{keyId} {
      allow read: if request.auth != null;
      allow write: if isAdmin();
    }
    match /admin_key_groups/{group} {
      allow read: if request.auth != null;
      allow write: if isAdmin();
    }

    // The app writes its own error batches; only admins read them.
    match /api_error_logs/{logId} {
      allow create: if request.auth != null;
      allow read, update, delete: if isAdmin();
    }

    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

## 4. Verifying the wiring

1. With `google-services.json` in place, run the app: Settings shows
   **Admin**.
2. Admin → sign in with the allowlisted Google account → the gate flips to
   *on the admin allowlist* → *Open API key manager* lists (an empty) pool.
3. Add one key (OpenRouter or a Gemini proxy), then Generate a reply from
   the composer: suggestions arrive in the chosen language and tone.
4. Break it on purpose once: disable the key in the admin screen, generate
   again, and confirm the app reports *no healthy API key* instead of
   crashing or fabricating a reply.

## 5. CI

CI never needs `google-services.json` (guest-mode invariant). Release
signing reads `key.properties` / the upload keystore from repository secrets,
written into the workspace by the workflow before the build - never from git.
