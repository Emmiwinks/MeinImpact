# Android release (Google Play)

How a build gets from `main` to testers' phones. CI builds a signed app
bundle (`.aab`) on every push to `main` that touches `app/`; you upload it
in the Play Console.

- App ID: `de.meinimpact.app` (permanent once uploaded)
- Developer account: `meinimpact.app@gmail.com`
- Build number: the CI run number (`--build-number`), so it always grows
- API: `https://meinimpact-api.fly.dev/` (release builds default to it)

## 1. Create the upload key (once)

The upload key signs every bundle you upload. Google re-signs the app for
distribution with its own app signing key (Play App Signing), so a lost
upload key can be reset through Play support, but keep it safe anyway.

No Java is installed on the dev machine, so use Docker. In PowerShell, in
a folder **outside the repository** (e.g. `C:\Users\PCUser\keys`):

```powershell
docker run --rm -it -v "${PWD}:/out" eclipse-temurin:17 keytool -genkeypair -v `
  -keystore /out/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 `
  -alias upload
```

In cmd (one line, `%cd%` instead of `${PWD}`):

```bat
docker run --rm -it -v "%cd%:/out" eclipse-temurin:17 keytool -genkeypair -v -keystore /out/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

It asks for a keystore password and your name/organisation (any values
work; they are not shown to users). The one password covers the keystore
and the key inside it. Store the `.jks` file and the password in your password manager.
Never commit it (`android/.gitignore` already blocks `*.jks` and
`key.properties`).

## 2. Give CI the key (once)

Turn the keystore into text:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) | Set-Clipboard
```

In cmd:

```bat
powershell -NoProfile -Command "[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\Users\PCUser\keys\upload-keystore.jks')) | Set-Clipboard"
```

In GitHub: repository **Settings > Secrets and variables > Actions > New
repository secret**, create two secrets:

| Secret | Value |
|---|---|
| `ANDROID_UPLOAD_KEYSTORE_BASE64` | the clipboard content from above |
| `ANDROID_UPLOAD_STORE_PASSWORD` | the keystore password |

The key alias `upload` is set in the workflow.

Until these exist, the "Build Android release" job fails on `main` on
purpose; a bundle signed with the debug key would be rejected by Play.

## 3. Get a bundle

Push to `main`. In GitHub **Actions > App > the run > Artifacts**, download
`meinimpact-android-<run number>` and unzip it: `app-release.aab`.

## 4. Play Console: first internal test (once)

1. **Create app**: name "MeinImpact", default language German, app, free.
2. **Testing > Internal testing > Create new release**: accept Play App
   Signing, upload `app-release.aab`, release notes, save, roll out.
3. **Testers**: create an email list (Google accounts of the testers), save,
   copy the **opt-in link** and send it to them. Up to 100 testers, no
   review needed for internal testing.
4. Play asks for the app content forms before the first rollout: privacy
   policy URL, app access, ads (none), content rating, target audience,
   data safety. The privacy policy has to be online first (meinimpact.de).

## 5. Automatic releases (once)

After the first manual release, CI can roll out every push to `main` to
internal testing. Play needs a service account for that:

1. [Google Cloud Console](https://console.cloud.google.com/): create (or
   pick) a project, enable the **Google Play Android Developer API**.
2. **IAM & Admin > Service accounts > Create**: name e.g. `play-upload`, no
   roles. Open it, **Keys > Add key > JSON**, download the file.
3. Play Console **Users and permissions > Invite new users**: the service
   account's email, app permission for MeinImpact with **Release apps to
   testing tracks**. No admin rights needed.
4. GitHub secret `PLAY_SERVICE_ACCOUNT_JSON`: the whole content of the JSON
   file. Then delete the downloaded file.

From then on, each push to `main` that touches the app lands with the
testers a few minutes later; they get it as a normal Play Store update.
Without the secret, the upload step is skipped and the bundle stays an
artifact (step 3).

If Play answers "Only releases with status draft may be created on draft
app", the app content forms from 4.4 are not done yet.
