# MyAnalyst mobile app (Flutter)

Android / iOS / web client for the MyAnalyst backend. Upload a CSV, see the cash-flow
snapshot, runway and cash-gap warning, compare financing options, read the AI summary,
ask questions, export a lender-ready PDF. English and 中文.

Requires Flutter 3.22 (Dart 3.4). Android 6.0+.

## Two builds

| Build | What it talks to | Command |
|---|---|---|
| **Demo** | Nothing: bundled sample analyses (`assets/mock/`), any sign-in works | `flutter build apk --release --dart-define=USE_MOCK=true --obfuscate --split-debug-info=build/debug-info` |
| **Live, phone on the same Wi-Fi** | The backend on your laptop | `flutter build apk --debug --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://<laptop-ip>:8000` |
| **Live, release** | A deployed backend (HTTPS only) | `flutter build apk --release --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=https://<server>` |

Release builds refuse plain `http://`. For the laptop setup run the backend with
`uvicorn main:app --host 0.0.0.0 --port 8000` and allow port 8000 through the firewall.

## Security

- **Sign-in:** 15-minute access token in memory only; rotating 30-day refresh token in
  the platform keystore (`flutter_secure_storage`). `lib/data/auth/` holds the dio
  interceptor: refreshes before expiry, retries once on 401, one refresh shared by
  concurrent requests.
- **Fingerprint / Face ID unlock** (`lib/security/app_lock.dart`): a 256-bit key that
  only biometrics can release from hardware-backed storage encrypts the refresh token
  (AES-256-GCM). The app relocks after 5 minutes in the background.
- AI output is rendered as plain text; charts are drawn natively (no WebView); server
  error details are never shown; Android cloud backup is off; release builds are
  obfuscated.

## Code map

- `lib/data/` — `http_repository.dart` (live API), `mock_repository.dart` (demo), `auth/`
- `lib/models/` — API models; `chart_data.dart` converts Plotly JSON to native charts
- `lib/ui/` — screens (`cash_page.dart` is the cash-flow screen)
- `lib/i18n/strings.dart` — every UI string in English and Chinese
- `lib/report/pdf_report.dart` — PDF export
- `lib/finance/financing.dart` — financing options (indicative costs; not advice)

## Tests

`flutter test`, including screen renders in `test/goldens/` and a contract test against a
real backend response (`test/fixtures/`). Against a running backend:
`flutter test test/live_backend_test.dart --dart-define=LIVE_API=http://127.0.0.1:8000`.
