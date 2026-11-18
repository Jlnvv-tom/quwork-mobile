# QuWork Mobile development

This document covers local development, emulator debugging, One-API environment selection, and APK builds for the QuWork mobile work. General repository rules remain in [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md).

## Environment

Use macOS with Android Studio, Android SDK/platform-tools, Flutter 3.47/Dart 3.13, JDK 17, Python 3, and Node.js. If Flutter or Android tools are not on `PATH`, put local paths in the untracked `tooling/env.sh`. Do not put credentials, tokens, certificates, or cookies there.

## One command, one action

Run these commands from the repository root:

| Action | Command |
|---|---|
| Start or reuse an Android emulator | `npm run quwork:emu:start` |
| Start Mock, build/install and launch the app | `npm run quwork:emu` |
| Launch against development One-API | `QUWORK_DEV_API_BASE_URL=https://your-dev-host npm run quwork:dev` |
| Launch against production One-API | `npm run quwork:prod` |
| Build a Mock Debug APK | `npm run quwork:apk` |
| Build a production Release APK | `npm run quwork:apk:release` |
| Follow emulator logs | `npm run quwork:logs` |
| Run Flutter analysis | `npm run quwork:analyze` |
| Run Flutter tests | `npm run quwork:test` |
| Start only the local Mock API | `npm run quwork:mock` |

Set `QUWORK_ANDROID_AVD` to choose an AVD or `QUWORK_ANDROID_DEVICE` to choose an adb serial.

## One-API environments

`QUWORK_API_BASE_URL` is the account control plane (`/api/...`); `QUWORK_LLM_BASE_URL` is the OpenAI-compatible model endpoint (`/v1/...`). The confirmed production defaults are `https://llm.rrzu.com` and `https://llm.rrzu.com/v1`. The repository does not contain a development hostname, so `QUWORK_DEV_API_BASE_URL` is required for development runs; set `QUWORK_DEV_LLM_BASE_URL` too when its model endpoint is not `${API_BASE}/v1`.

The local Mock server is bound to `127.0.0.1:8787`; the Android emulator reaches it at `10.0.2.2:8787`. Test phone: `13800138000`; code: `123456`. Mock never calls the real One-API.

Do not expose JWTs, `llm_token`, cookies, verification codes, QR secrets, or complete phone numbers in logs, screenshots, issues, or commits.

## Emulator and logs

Run `npm run quwork:emu:start`, then `npm run quwork:emu`. Sign in with the Mock test account. In another terminal, run `npm run quwork:logs` for Flutter and app logs. Emulator startup and Mock logs are written to `/tmp/quwork-android-emulator.log` and `/tmp/quwork-mock-server.log`.

To clear only emulator app data: `adb -s "${QUWORK_ANDROID_DEVICE:-emulator-5554}" shell pm clear io.github.ccch1mneyyy.dsh_app`.

## APK builds

`npm run quwork:apk` creates `app/build/app/outputs/flutter-apk/app-arm64-debug.apk` with Mock endpoints. `npm run quwork:apk:release` creates the production Release APK and uses the repository signing/runtime requirements. For other ABIs or version names, use `tooling/build-apk.sh` directly.

The current account endpoints are `POST /api/sendVerifyCode`, `POST /api/user/client/login`, `GET /api/user/self`, `GET /api/user/refresh`, `GET /api/user/available_models`, and the WeChat/login-out routes documented in the Chinese README. Model traffic uses `/v1/models` and `/v1/chat/completions`. One-API JWTs are control-plane credentials and must not become long-lived Gateway connection keys.
