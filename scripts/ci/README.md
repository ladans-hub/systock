# iOS App Store artifact

The `ios-release` CI job runs on pushes to main and manual workflow runs.
It uses macOS 26 with stable Xcode 26.6, builds Flutter in release mode with
Google defines, and exports `Systock-iOS-AppStore-release` as an IPA artifact.
It does not upload to App Store Connect. Pull requests retain the unsigned iOS
compilation in the `apple` job and do not receive distribution credentials.

Configure repository Settings → Secrets and variables → Actions:

| Kind | Name | Value |
| --- | --- | --- |
| Secret | `IOS_DISTRIBUTION_P12_BASE64` | Base64 of an Apple Distribution certificate exported with its private key as .p12 |
| Secret | `IOS_DISTRIBUTION_P12_PASSWORD` | Nonempty password used to protect the .p12 |
| Secret | `IOS_APP_STORE_PROFILE_BASE64` | Base64 of a valid App Store Connect provisioning profile for `mz.ladans.systock`, containing that certificate |
| Variable | `GOOGLE_IOS_CLIENT_ID` | iOS OAuth client ID for `mz.ladans.systock` |
| Variable | `GOOGLE_SERVER_CLIENT_ID` | Optional OAuth server client ID |

The profile supplies the Apple team and profile UUID. Development, ad hoc,
enterprise, expired and mismatched profiles are rejected. Credentials live in a
temporary keychain and are removed after the job. Never commit signing files or
defines.json. The iOS URL scheme is generated from the iOS client ID at build time.

The marketing version comes from pubspec.yaml and the build number comes from
`github.run_number`. Ensure it exceeds any build already uploaded for that version;
a rerun retains the same build number, so use a new workflow run for a new upload.

References:
- https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications
- https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md
