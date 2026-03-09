# Mac Setup for TestFlight CI/CD

## Goal
Export signing credentials from this Mac and add them as GitHub Secrets so that GitHub Actions can build and upload SwiftST to TestFlight automatically on every push to `main`.

---

## App details (for reference)
- **App name:** SwiftST
- **Bundle ID:** `PaesLemeST`
- **Team ID:** `J8D7WJR5PY`
- **App Store Connect API Key ID:** `N385WPPNHV`

---

## Step 1 — Export the distribution certificate as a .p12

1. Open **Keychain Access**
2. In the sidebar select **My Certificates**
3. Find the certificate named **"Apple Distribution: [your name/org]"**
4. Right-click it → **Export**
5. Save as `distribution.p12`, set a strong password, note that password

Then base64-encode it:
```bash
base64 -i ~/Desktop/distribution.p12 | pbcopy
```
This copies the encoded value to your clipboard — that's the value for `CERTIFICATES_P12`.

---

## Step 2 — Download and export the provisioning profile

1. Go to [developer.apple.com](https://developer.apple.com) → **Certificates, IDs & Profiles → Profiles**
2. Find the **App Store Distribution** profile for bundle ID `PaesLemeST`
3. Download it (saves as a `.mobileprovision` file)

Then base64-encode it:
```bash
base64 -i ~/Downloads/YourProfile.mobileprovision | pbcopy
```
That's the value for `PROVISIONING_PROFILE`.

---

## Step 3 — Get the App Store Connect API key (.p8)

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Users and Access → Integrations → App Store Connect API**
2. Find the key with ID **`N385WPPNHV`** (or create a new one with App Manager role if it's been lost — .p8 files can only be downloaded once)
3. Note the **Issuer ID** shown at the top of the page
4. If you still have the `.p8` file:
```bash
cat ~/Downloads/AuthKey_N385WPPNHV.p8 | pbcopy
```
That's the value for `APP_STORE_CONNECT_API_KEY_CONTENT`.

---

## Step 4 — Add all secrets to GitHub

Go to: **github.com/c4ssio/gd → Settings → Secrets and variables → Actions → New repository secret**

Add each of these:

| Secret name | Value |
|---|---|
| `APP_STORE_CONNECT_API_KEY_ID` | `N385WPPNHV` |
| `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | The Issuer ID from App Store Connect (step 3) |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | Full contents of the `.p8` file (paste multi-line, that's fine) |
| `CERTIFICATES_P12` | Base64 output from step 1 |
| `CERTIFICATES_P12_PASSWORD` | The password you set when exporting the `.p12` |
| `PROVISIONING_PROFILE` | Base64 output from step 2 |
| `KEYCHAIN_PASSWORD` | Any random string, e.g. `gh-build-swiftst` |

---

## Step 5 — Verify

Once all 7 secrets are added, push any change to `main` on the repo. The GitHub Action will trigger automatically and build + upload to TestFlight. You can watch it live under the **Actions** tab on GitHub.
