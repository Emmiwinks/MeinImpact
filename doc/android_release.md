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

It asks for a keystore password and your name/organisation (any values
work; they are not shown to users). Use the same password for the key when
asked. Store the `.jks` file and the password in your password manager.
Never commit it (`android/.gitignore` already blocks `*.jks` and
`key.properties`).

## 2. Give CI the key (once)

Turn the keystore into text:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) | Set-Clipboard
```

In GitHub: repository **Settings > Secrets and variables > Actions > New
repository secret**, create four secrets:

| Secret | Value |
|---|---|
| `ANDROID_UPLOAD_KEYSTORE_BASE64` | the clipboard content from above |
| `ANDROID_UPLOAD_STORE_PASSWORD` | the keystore password |
| `ANDROID_UPLOAD_KEY_ALIAS` | `upload` |
| `ANDROID_UPLOAD_KEY_PASSWORD` | the key password (same as above) |

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

Later releases: steps 3 and 4.2 only.
