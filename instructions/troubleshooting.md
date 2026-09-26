# Troubleshooting

Two problems were reported: the app **never leaves the loading screen** (Expo Go, APK and web
browser), and Expo Go shows **"Project is incompatible with this version of Expo Go"**.

---

## 1. Stuck on the loading screen

### Symptom

`npx expo start`, scan the QR (or open the APK / the exported web URL) → the pink spinner is
the only thing that ever appears. It does not matter whether you are signed in or not.

### Root cause (verified against the compiled bundle, not guessed)

`app.json` enables the React Compiler:

```json
"experiments": { "reactCompiler": true }
```

`lib/auth.ts` used to read module-level `let` variables and build a fresh object on every call:

```ts
export function useAuth(): AuthState {
  return { session, user, loading, initialized };   // ← built from module-level `let`s
}
```

The compiler cannot see those `let`s change, so it memoized the object on first render. The
compiled output in the built bundle was literally:

```js
e.useAuth = function () {
  ...
  t[3] === Symbol.for("react.memo_cache_sentinel")
    ? (b = { session: u, user: o, loading: l, initialized: c }, t[3] = b)  // built ONCE
    : b = t[3];                                                            // stale forever
  return b
}
```

Every screen therefore kept reading `initialized: false` for the whole lifetime of the app, so
`app/_layout.tsx` returned its spinner forever. The same staleness meant sign-in/sign-out never
updated the gate either (logout could keep showing the real app).

A second, separate bug broke the web build: `lib/supabase.ts` passed AsyncStorage to Supabase
unconditionally. AsyncStorage reads `window` at call time, so static rendering crashed the export
with `ReferenceError: window is not defined` and left only the static spinner HTML behind.

### Fix (already applied in this repo)

| File | Change |
| --- | --- |
| `lib/auth.ts` | `useAuth()` is now `useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot)` and returns an **immutable snapshot** object that is rebuilt (new reference) inside `publish()`. Nothing is constructed inside the component, so there is nothing for the compiler to memoize. |
| `lib/auth.ts` | `initAuth()` wraps everything in `try/finally` and always sets `initialized = true`, and its 4 s `Promise.race` keeps a hanging `getSession()` from blocking startup. |
| `app/_layout.tsx` | The `<Stack>` is now **always mounted**; the spinner is a `pointerEvents="none"` absolute-fill overlay drawn only while `!initialized`. The navigator therefore exists on the very first render, so `router.replace('/login')` can never fire before it is ready. |
| `lib/supabase.ts` | Uses a no-op memory storage **only when `typeof window === 'undefined'`** (static rendering). Browser / Expo / RN still get real AsyncStorage, so logins survive a refresh. |

### How to verify the fix

```bash
npx tsc --noEmit            # type check
npx expo export --platform web   # must finish with "Exported: ..."
```

Then inspect the compiled bundle — `useAuth` must compile to a bare `useSyncExternalStore` call
with **no object literal** in it:

```bash
# Windows PowerShell
$f = (Get-ChildItem <export-dir>\_expo\static\js\web\*.js | Select-Object -First 1)
( Get-Content $f.FullName -Raw ).Contains('useSyncExternalStore')
```

Expected at runtime: the spinner disappears within a few seconds (immediately on a warm start)
and the **Sign In** screen appears. In the exported HTML, `login.html` must contain the login
form markup — not just the spinner.

**Serving the export:** the generated HTML loads its bundle from an absolute path
(`<script src="/_expo/static/js/web/entry-….js">`). Opening `index.html` straight from disk
(`file://`) 404s that script and leaves the static spinner on screen forever even though the code
is fine. Serve the folder from a web root instead — e.g. `npx expo start --web`, or
`npx serve <export-dir>` — and always test the app through `npx expo start`, not by
double-clicking the HTML file.

### If it ever regresses, check in this order

1. Anything returning a **new object literal** from a hook that reads module-level mutable state
   (`let`/`var` outside the component) is a React Compiler staleness trap — back it with
   `useSyncExternalStore` or `useState` instead.
2. `initAuth()` must have a `finally` that flips `initialized`.
3. Never gate the app by **unmounting** the navigator before init finishes; draw a loader on top.
4. `lib/supabase.ts` must not touch AsyncStorage when `window` is undefined, or the static export
   dies.

---

## 2. "Project is incompatible with this version of Expo Go"

Each Expo Go build ships **exactly one** Expo SDK. Expo Go compares its supported SDK against the
`expo` package version of your project and refuses to load anything else.

### Step 1 — read this project's SDK

```bash
npx expo config --type public
```

For this repo the answer is:

```text
sdkVersion: '54.0.0'      # package.json: "expo": "~54.0.37"
```

(The project deliberately stays on SDK 54 because the lab docs in `instructions/` are written for
it, and `npx expo install --check` + `npx expo-doctor` both report the dependency set is clean:
18/18 checks passed.)

### Step 2 — read your phone's Expo Go supported SDK

Open Expo Go on the device → **Settings (Android) / About (iOS)**. It prints
`Supported SDK <NN>` (or the version the release notes name).

**The two major numbers must match.** If the phone says 55/56/57 and the project says 54, the
error is expected — nothing in the project is wrong.

### Step 3 — apply the matching fix

**Fix A — put an SDK 54 Expo Go on the phone (recommended, no project changes):**

- **Android:**
  1. **Uninstall** the current Expo Go first (it is SDK 57). Android refuses to install an older
     build over a newer one (`INSTALL_FAILED_VERSION_DOWNGRADE`).
  2. On the **phone**, open the link from the error message:
     `https://expo.dev/go?sdkVersion=54&platform=android&device=true` — it serves the SDK 54 APK.
  3. Open the downloaded file and allow "install unknown apps" for your browser/file manager.
  4. Prevent Play Store from silently upgrading it back to SDK 57: Play Store →
     Settings → Network preferences → Auto-update apps → **Don't auto-update apps** (or re-side-load
     the SDK 54 build whenever it reverts).
  5. Re-scan the dev-server QR code.
- **iOS:** the App Store build is SDK 54, so just update Expo Go from the App Store.
- Alternatively the `expo-go` CLI downloads a build matching your SDK:
  `npx expo-go --help` (Android devices/emulators and iOS simulators only — Apple blocks
  side-loading older builds on physical iPhones).

**Fix B — move the project onto the phone's SDK instead:**

```bash
npx expo upgrade          # interactive: picks the target SDK, rewrites package.json
npx expo install --fix    # align every native dependency to that SDK
npx expo-doctor
```

Only take this path if you deliberately want to leave SDK 54 — it changes every dependency and
the lab docs in `instructions/` are pinned to SDK 54, so they would need re-checking.

### Known upstream bug (only affects SDK 56 projects)

Expo Go **56.0.1** rejects every SDK 56 project with this exact message because the client
compares `56.0.0` from the manifest against its own `56.0.1` version string instead of the SDK
major (expo/expo issue #46846, fixed by PR #46944 by comparing major versions). Workaround: use
the 56.0.0 client build. **This does not apply to this project** — it is SDK 54, so an SDK 54
Expo Go always accepts it.

### If the message persists after matching the SDK

```bash
npx expo-doctor@latest     # 18/18 checks passed for this repo
npx expo install --check   # "Dependencies are up to date"
```

- `app.json` has **no** `sdkVersion` field (only `package.json`'s `expo` dependency sets it) —
  if you ever add one, it must read `54.0.0`.
- Kill the dev server, delete the Metro cache and restart: `npx expo start -c`.
- On Android, also confirm the phone is on the same network (or use `--tunnel`), because a
  stale bundle cached in Expo Go can show old behaviour after you change code.

---

## 3. Signed up as Teacher, but the app says Student

**Symptom:** you tapped the **Teacher** chip at sign-up, but after signing in the Profile badge
says Student and the Teacher tab is locked. In Supabase → `profiles`, `role` is `'student'`.

**Root cause:** the old `signUp` only wrote the role `if (data.session && profile)` with a plain
`.update()` whose result was never checked. With email confirmation on there is **no session** at
sign-up (write skipped), and even with a session a `.update()` can silently match 0 rows.

**Fix (already in this repo — see `instructions/13-signup-role-bugfix.md` for the full writeup):**

1. `lib/auth.ts` now runs `syncProfile` at **sign-up, sign-in, and every app boot**: it reads the
   role intent from the device stash / the signup `user_metadata`, upserts the `profiles` row on
   mismatch, **reads it back to verify**, and only then clears the intent. Teachers are routed
   straight to the Teacher (create-events) tab after sign-up/sign-in.
2. **Re-run `supabase/schema.sql`** — the `handle_new_user` trigger now reads
   `raw_user_meta_data` so the role lands atomically at insert time (SQL Editor → paste → Run).
3. **Restart Metro with a cleared cache** — `npx expo start -c`. A cached JS bundle is the most
   common reason a fix "didn't work".
4. If the Teacher tab still shows the lock, sign out/in or restart the app — boot runs the repair
   automatically (bounded to 1.5s so it can never hang the loading screen).

**Accounts created BEFORE this fix** carry no metadata/stash — they don't self-heal. Fix them once:

```sql
update public.profiles
set role = 'teacher', updated_at = now()
where email = 'you@example.com';
```

---

## Quick reference

| Symptom | Likely cause | Where |
| --- | --- | --- |
| Spinner forever, on every platform | Hook returning a memoized object built from module-level state | `lib/auth.ts` |
| Web export crashes with `window is not defined` | AsyncStorage used during static rendering | `lib/supabase.ts` |
| `Project is incompatible with this version of Expo Go` | Phone's Expo Go SDK ≠ project SDK (54) | device, not the code |
| Session lost on every refresh | no-op storage passed to Supabase in the browser | `lib/supabase.ts` |
| Signed up as Teacher, shows Student | role write skipped when `session` is null (silent `.update()`) | `lib/auth.ts` + schema trigger — see §3 |
| Old accounts stuck as Student | fix was never applied retroactively | one `update ... where email` SQL |
