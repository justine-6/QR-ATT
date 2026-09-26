# SETUP COMMANDS — QR Attendance App

> **Target:** First-year students | **Expo SDK:** 54 | **Expo Go:** 54.0.8

---

## PREREQUISITES

| Tool | Download | Verify |
|---|---|---|
| Node.js (LTS) | https://nodejs.org/en | `node --version` |
| VS Code | https://code.visualstudio.com | (open it) |
| Expo Go 54.0.8 | Play Store → "Expo Go" | (version in app settings) |

---

## STEP 1 — Create the App

```powershell
cd D:\QR-ATT
npx create-expo-app@latest qr-att

# When prompted, select "SDK 54"
# Wait for npm install (~2 min)
```

---

## STEP 2 — Install Matching Versions

The default install may need these fixed versions that match Expo Go 54.0.8:

```powershell
npm install expo@~54.0.35 react@19.1.0 react-native@0.81.5 expo-router@~6.0.24 @expo/vector-icons@^15.0.3 expo-linking@~8.0.12 expo-constants@~18.0.13 expo-font@~14.0.12 expo-status-bar@~3.0.9 expo-splash-screen@~31.0.13 react-native-screens@~4.16.0 react-native-safe-area-context@~5.6.0 react-native-gesture-handler@~2.28.0 react-native-reanimated@~4.1.1 react-dom@19.1.0 react-native-web@~0.21.0 @types/react@~19.1.0 typescript@~5.9.2 --legacy-peer-deps
```

---

## STEP 3 — Start

```powershell
npx expo start
```

Scan QR code with Expo Go. Or press `W` for web.

> **The phone's Expo Go must be the SDK 54 build** (Expo Go → Settings: `Supported SDK 54`).
> If it shows 55/56/57 you get *"Project is incompatible with this version of Expo Go"* — the
> project is correct, the phone's Expo Go is the wrong build:
> **Android:** Play Store build, or <https://expo.dev/go?sdkVersion=54&platform=android>
> **iOS:** App Store build (the App Store ships SDK 54).

---

## LAB INSTRUCTIONS

The step-by-step student lab docs live in [`instructions/`](instructions/):

- `instructions/03-database-design.md` — build the Supabase tables, RLS and trigger
- `instructions/04-database-service.md` — `lib/database.ts` talks to the cloud
- `instructions/05-profiles.md` — names & roles on signup and the Profile screen
- `instructions/06-attendance-by-role.md` — role-aware History (teacher sees their events' attendance)
- `instructions/07-visual-identity.md` — kiosk colour tokens, flat buttons, aligned auth screens
- `instructions/08-events.md` — `lib/events.ts` service + role-gated Teacher tab (Migration Phase 7)
- `instructions/09-qr-generation.md` — `lib/qr.ts` build/parse helpers (Migration Phase 8)
- `instructions/10-qr-attendance.md` — attendance consolidated into `lib/attendance.ts`, `lib/database.ts` deleted (Migration Phase 9)
- `instructions/11-attendance-history.md` — final read queries: student history + count-only teacher summary (Migration Phase 10)
- `instructions/12-qr-connection-flow.md` — reference: the full QR create → scan → save chain
- `instructions/migration-log.md` — every migration phase: files, reasons, testing, results
- `instructions/13-signup-role-bugfix.md` — fix: Teacher role chosen at sign-up now persists
- `instructions/14-pink-theme.md` — visual refresh: pink aesthetic theme
- `instructions/troubleshooting.md` — stuck loading screen, Expo Go "incompatible" error, role bug

The SQL they refer to is `supabase/schema.sql`. **Where a doc and any other note disagree, follow the doc in `instructions/`.**

---

## TROUBLESHOOTING

| Problem | Solution |
|---|---|
| npm install fails | Use `npm install --legacy-peer-deps` |
| App crashes in Expo Go | Make sure all versions match STEP 2 exactly |
| QR won't scan | Phone + computer on same WiFi |
| White screen | Wait 10s, or shake → Reload |
| TypeScript errors | Run `npx tsc --noEmit` |
| Spinner never disappears (Expo Go / APK / web) | See [`instructions/troubleshooting.md`](instructions/troubleshooting.md) § 1 |
| "Project is incompatible with this version of Expo Go" | Phone's Expo Go SDK must be **54** — see [`instructions/troubleshooting.md`](instructions/troubleshooting.md) § 2 |
| Signed up as Teacher but the app says Student | See [`instructions/13-signup-role-bugfix.md`](instructions/13-signup-role-bugfix.md) + re-run `supabase/schema.sql` |
