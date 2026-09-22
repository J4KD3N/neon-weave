# Apple live checklist

What only an Apple Developer Program membership and a Mac can verify.
`tools/apple_check.gd` (`apple/READINESS.md`) says what the checkout has;
`--strict` exits 1 while a blocker stands. Tick these in order.

1. **Membership.** Enrol in the Apple Developer Program (the paid one; Developer ID certificates need it).
2. **Certificate.** In Xcode or developer.apple.com, create a *Developer ID Application* certificate. Export it from Keychain Access as a `.p12` with a password. Base64 it: `base64 -i cert.p12 | pbcopy`.
3. **API key.** App Store Connect → Users and Access → Integrations → App Store Connect API: a *Team* key with the *Developer* role. Download the `.p8` once. Note the Key ID and the Issuer ID. Base64 the `.p8`.
4. **Secrets.** In the GitHub repository settings, add: `APPLE_CERTIFICATE_P12` (the base64 p12), `APPLE_CERTIFICATE_PASSWORD`, `APPLE_API_KEY_P8` (the base64 p8), `APPLE_API_KEY_ID`, `APPLE_API_ISSUER`. The release workflow signs and notarizes only when all five exist; a fork without them still gets the ad-hoc build.
5. **Tag.** Push a `v*` tag (or run the release workflow by hand). Watch the "Sign and notarize macOS" step: rcodesign signs with the hardened runtime and `apple/entitlements.plist`, submits to the notary service, waits, and staples the ticket. A rejection prints the notary log; the usual causes are an entitlement the binary does not need or a library without a signature.
6. **On a Mac.** Download the macOS zip from the release, unzip, and run: `spctl -a -vv "Neon Weave.app"` says `accepted` and `source=Notarized Developer ID`; `codesign -dv --verbose=2 "Neon Weave.app"` shows the Developer ID and `runtime` in the flags; `xcrun stapler validate "Neon Weave.app"` says the ticket is stapled.
7. **A stranger.** Send the zip to someone whose Mac has never seen the app. Double-clicking opens it with no warning and no right-click dance. That is the done-when.
8. **Universal.** `lipo -info "Neon Weave.app/Contents/MacOS/Neon Weave"` lists `x86_64 arm64`. Run it on an Apple Silicon Mac and, if one is around, an Intel one.
9. **Gatekeeper on a clean account.** On the stranger's Mac or a fresh user account, quarantine is on by default; the app must still open after a download through a browser, not only from AirDrop.

Each step that passes is a line in `docs/decisions.md` under S59's decision; the gaps entry for macOS closes when all nine are ticked.
