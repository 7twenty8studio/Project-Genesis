# Google Drive backup for journal attachments (Android)

Android keeps prayer and sermon attachments (photos, recordings, PDFs) on
the device and, once the person taps **Back Up to Google Drive**, copies
them to their own Google Drive's hidden app folder (`appDataFolder`, scope
`https://www.googleapis.com/auth/drive.appdata`). Only Versely can see that
folder; it counts toward the person's own storage, not Versely's. The
attachment's row syncs through Supabase with `storage_path = "gdrive:<id>.<ext>"`
(iPhone rows keep their iCloud paths), so another Android device signed in
to the same account downloads the file when it's shown. Deleting the
account deletes the folder's files.

Code: `AttachmentTransfers` and `DriveClient` (app/journal), rules in
`AttachmentStorage` (core:domain). Authorization is Google Play services'
`Identity.getAuthorizationClient` (no Drive SDK).

## One-time setup (Google Cloud console)

1. Go to https://console.cloud.google.com and pick (or create) the project
   that holds Versely's Google sign-in client.
2. **APIs & Services › Library**: search "Google Drive API" and press **Enable**.
3. **APIs & Services › OAuth consent screen** (Google Auth Platform):
   - **Data access › Add or remove scopes**: add
     `.../auth/drive.appdata` ("See, create, and delete its own
     configuration data in your Google Drive"). It is a non-sensitive
     scope, so no Google verification review is needed.
   - Publishing status should be **In production** (in Testing only the
     listed test users can allow it).
4. **APIs & Services › Credentials › Create credentials › OAuth client ID**:
   - Application type: **Android**.
   - Package name: `com.seventwenty8studio.versely`.
   - SHA-1 certificate fingerprint: the debug key for now. On the Mac:
     `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android | grep SHA1`
   - Create. Nothing to copy into the app: Google matches the package name
     and signature.
5. When the app is on Google Play, add two more Android clients the same way
   with the SHA-1 of the **upload key** and of the **app signing key**
   (Play Console › Test and release › App integrity).

## Play Console › Data safety

Files go to the person's own Google Drive, not to Versely's servers, so they
aren't "collected" by the developer. The attachment details (size, kind,
caption, which prayer or sermon) sync through Supabase like notes.
