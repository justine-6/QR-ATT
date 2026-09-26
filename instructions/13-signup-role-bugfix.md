# Bugfix — Sign-Up Role Stuck as Student (Teacher Never Saves)

> This is a **student lab activity**. Symptom: a user taps **Teacher** on the Sign Up screen, creates the account, signs in — and the app still treats them as a **Student** (Profile badge says Student, Teacher tab shows "Teachers Only" instead of the create-events form). This doc explains the root cause and the layered, **self-healing** fix.

---

## HOW TO USE THIS DOCUMENT (Read Me First)

In this phase you will:
1. **LEARN** — why the chosen role was silently discarded (three separate traps)
2. **CODE** — four layers that make the role stick AND repair itself
3. **VERIFY** — sign up as Teacher → land directly in the create-events section

**Time needed:** ~25 minutes
**You will need:** Phase 5 (profiles), Phase 7 (teacher role gate), and the ability to re-run `supabase/schema.sql`.

---

## 1. THE BUG

### Symptom

1. Open **Sign Up**, fill the form, tap the **Teacher** chip.
2. Register successfully, then sign in.
3. Profile shows **Student**. Teacher tab shows the **"Teachers Only"** lock instead of the create-event form.
4. In Supabase → `profiles`, the row's `role` column is `'student'` (the default).

The form captured the choice — `register.tsx` passes `{ full_name, role }` to `signUp(...)` — but the value never reached (or never stayed in) the database.

---

## 2. ROOT CAUSE — THREE SILENT TRAPS

The original code in `lib/auth.ts`:

```typescript
const { data, error } = await supabase.auth.signUp({ email, password });
if (!error && data.session && profile) {
  await supabase
    .from('profiles')
    .update({ full_name: profile.full_name, role: profile.role })
    .eq('id', data.session.user.id);
}
```

| # | Trap | What happens |
|---|---|---|
| 1 | `data.session &&` guard | With **email confirmation ON**, `signUp` returns `session: null` → the guard is false → the write **never runs**. |
| 2 | `.update(...)` result ignored | A plain `.update()` can match **0 rows** (trigger race, RLS denial) and still resolve without throwing — **silently** doing nothing. |
| 3 | No repair path | If the first write failed, nothing ever retried it — not at sign-in, not at app boot. The DB default `'student'` stood forever. |

> 💡 **The Analogy: a form lost between two offices.** The Sign Up screen filled out the "role" form, but it tried to file it at a counter that was closed (no session). Nobody re-filed it later, and nobody noticed it was missing (silent failure).

---

## 3. THE FIX — FOUR SELF-HEALING LAYERS

Each layer covers the failure of the layer before it. The key design rule: **every entry point into the app re-checks and repairs the role, and no write is ever trusted without a read-back.**

### Layer 1 — Carry the profile in the signup metadata (client → server)

```typescript
const { data, error } = await supabase.auth.signUp({
  email,
  password,
  options: profile
    ? { data: { full_name: profile.full_name, role: profile.role } }
    : undefined,
});
```

`options.data` is stored by Supabase Auth as `user_metadata` on the user. It lives **on the server**, so it's readable from the session at *any* later moment — other devices, cleared caches, and even if the schema was never re-run.

### Layer 2 — The DB trigger writes it atomically (schema)

```sql
insert into public.profiles (id, email, full_name, role)
values (
  new.id,
  new.email,
  nullif(new.raw_user_meta_data->>'full_name', ''),
  case when new.raw_user_meta_data->>'role' = 'teacher'
       then 'teacher'
       else 'student'
  end
);
```

The `handle_new_user` trigger reads the metadata in the **same transaction** as the user insert — no race, no session, no RLS.

> ⚠️ **You must re-run `supabase/schema.sql`** (SQL Editor → paste → Run). It is idempotent. Without it, Layers 1/3/4 still cover you — but Layer 2 is the clean path.

### Layer 3 — Device stash + verified write at sign-up (client)

```typescript
await stashIntent(email, profile);      // memory + SecureStore — always, before any write
if (data.session) {
  setAuth(data.session);
  verifiedRole = await syncProfile(data.session);  // write → READ BACK → verify
}
```

`syncProfile` upserts the row (insert-or-update — never a silent 0-row update), then **reads the row back** and only clears the stash when the DB provably matches. The old bug where "the stash was cleared even if the write failed" is gone.

### Layer 4 — Self-healing sync at EVERY entry point

```typescript
signUp(...)  → syncProfile(session)        // immediately, before navigation
signIn(...)  → await syncProfile(session)  // BEFORE the caller navigates
initAuth()   → await syncProfile(session)  // at every app boot, 1.5s-bounded
```

`syncProfile` resolves the intent from **stash → `user_metadata`** (in that order), compares it with the `profiles` row, upserts on mismatch, reads back to verify, and keeps the intent if anything failed (so the next boot retries). It never throws and it never blocks boot for more than 1.5s.

**Consequence:** even if every write failed at sign-up, the first sign-in — or simply **reopening the app** — repairs the role. And the Teacher tab's role gate, which re-reads `getProfile` on every focus, then shows the create-events form.

### The routing change — teachers land in create-events

```typescript
// register.tsx (after a session exists)
const finalRole = verifiedRole ?? role;
router.replace(finalRole === 'teacher' ? '/(tabs)/teacher' : '/(tabs)');

// login.tsx
const profile = await getProfile(data.session.user.id);
router.replace(profile?.role === 'teacher' ? '/(tabs)/teacher' : '/(tabs)');
```

A teacher is taken **straight to the Teacher tab**, which — with the repaired role — opens the create-event form (not the lock).

### Layer 5 — visible, self-healing role control (never-stuck accounts)

Layers 1–4 repair the role **when a source of truth exists** (stash or `user_metadata`).
An account created **before this fix has neither** — no client code can guess its intended
role. Layer 5 closes that gap:

1. **Profile → Role row** shows the DB value live, with a **"Make Teacher" / "Make Student"**
   button that writes via `updateProfile` (RLS `update own row` policy) and updates the badge
   immediately. This is the deterministic fix for *any* stuck account — one tap, no SQL.
2. **Profile self-heals on focus**: `loadProfile` runs `syncProfile(session)` *before* reading
   the row, so a stash/metadata intent repairs the badge the moment you open the screen.
3. **The Teacher tab gate self-heals**: if the first read says `student`, it runs
   `syncProfile` once and re-reads — the lock can lift **while you're looking at it**.
4. **Root layout is role-aware**: bouncing off `/login`/`/register` now targets
   `/(tabs)/teacher` for teachers instead of always force-landing on Home.


---

## 4. WHICH LAYER FIRES WHEN

| Scenario | 1 metadata | 2 trigger | 3 sign-up write | 4 heal (sign-in/boot) |
|---|---|---|---|---|
| Confirmation OFF, schema re-run | ✅ | ✅ | ✅ + read-back | ✅ (verifies again) |
| Confirmation ON, schema re-run | ✅ | ✅ | stash only | ✅ applies at sign-in |
| Schema **not** re-run | ✅ | ❌ | ✅ or stash | ✅ from stash/metadata |
| Write failed at sign-up | ✅ | maybe | stash kept | ✅ **retries until verified** |
| Session already signed in (old app run) | ✅ | — | — | ✅ **repairs at boot** |
| Account created **before this fix** | ❌ no metadata | ❌ | ❌ | ❌ → one-time SQL (Section 8) |

---

## 5. STEP-BY-STEP EXECUTION GUIDE (what to type, in order)

### Step 1 — Edit `lib/auth.ts`
1. Add `import * as SecureStore from 'expo-secure-store';` at the top.
2. Add: `Intent` type, `INTENT_KEY`, `memoryIntent`, `normalizeRole`, `stashIntent`, `readIntent`, `clearIntent`.
3. Add the exported **`syncProfile(session)`** function exactly as in Section 3/4 (intent → compare → upsert → read-back → clear-only-on-verified).
4. `signUp`: pass `options.data`; **always** `stashIntent` first; when a session exists, `setAuth` then `verifiedRole = await syncProfile(...)`; return `{ data, error, verifiedRole }`.
5. `signIn`: after `setAuth(data.session)`, **`await syncProfile(data.session)`**.
6. `initAuth`: after restoring the session, `await Promise.race([syncProfile(session), timeout(1500ms)])` **before** the `finally` that flips `initialized`.

### Step 2 — Edit `app/register.tsx`
Destructure `verifiedRole` from `signUp` and route: teacher → `/(tabs)/teacher`, otherwise → `/(tabs)`.

### Step 3 — Edit `app/login.tsx`
After a successful `signIn`, `await getProfile(session.user.id)` and route teacher → `/(tabs)/teacher`, otherwise → `/(tabs)`.

### Step 4 — Edit `supabase/schema.sql`
Replace the body of `handle_new_user` with the metadata-reading version (Layer 2).

### Step 5 — Re-run the schema ⚠️
Supabase → **SQL Editor** → paste the entire `supabase/schema.sql` → **Run**.

### Step 6 — Restart the dev server WITH a cleared cache ⚠️
```bash
npx expo start -c
```
Metro serves cached JS — testing old bundles is the #1 way to think a fix "didn't work".

### Step 7 — Type check
```bash
npx tsc --noEmit
```

### Step 8 — Run & test (Section 6), then repair old accounts (Section 8).

---

## 6. TESTING YOUR WORK — THE LAB

### Step 1: Cold start
```bash
npx expo start -c
```
Sign out of any existing session first (Profile → Sign Out).

### Step 2: The main scenario — Teacher signs up and lands in create-events
1. Register a **brand-new** email, tap the **Teacher** chip.
2. If you see "Check your email!", confirm it, then sign in from the login screen.
3. ✅ You are taken **directly to the Teacher tab** and see the **Create Event QR** form (no lock).
4. ✅ Profile shows the **Teacher** badge.
5. ✅ Supabase → `profiles`: `role = 'teacher'`.

### Step 3: The repair scenario — a session that was already stuck
1. While signed in as a stuck account, kill and reopen the app (or reload the page).
2. ✅ Boot runs `syncProfile` → the role repairs itself → Teacher tab now opens the form.

### Step 4: Sign-out / sign-in path
Sign out, sign back in → ✅ still Teacher, routed to the Teacher tab again.

### Step 5: Student regression
Register a fresh account with the **Student** chip → ✅ lands on Home, Teacher tab still locked.

---

## 7. LAB CHECKLIST (Tick these off)

| # | Task | Done? |
|---|---|---|
| 1 | `npx tsc --noEmit` passes | ☐ |
| 2 | `signUp` passes `options.data { full_name, role }` | ☐ |
| 3 | Trigger reads `raw_user_meta_data` (schema re-run) | ☐ |
| 4 | `stashIntent` runs **before** any write attempt | ☐ |
| 5 | `syncProfile` upserts, reads back, clears only on verified match | ☐ |
| 6 | `syncProfile` called at sign-up, sign-in **and** boot (1.5s bounded) | ☐ |
| 7 | New Teacher sign-up → **lands on Teacher tab with the form open** | ☐ |
| 8 | Stuck session heals after an app restart | ☐ |
| 9 | Profile → Role shows the DB value; **"Make Teacher" unlocks the tab** | ☐ |
| 10 | Teacher gate self-heals (lock lifts after one re-read) | ☐ |
| 11 | New Student sign-up → lands on Home; Teacher tab locked | ☐ |
| 12 | `profiles.role = 'teacher'` verified in Supabase | ☐ |

---

## 8. RECOVERING ACCOUNTS CREATED BEFORE THIS FIX

Accounts created **before** this fix carry **no** `user_metadata` and **no** device stash — the app has no way to know they wanted Teacher. Two ways to fix them:

**Option A — one tap in the app (Layer 5):** open **Profile → Role → "Make Teacher"**.
The badge flips immediately and the Teacher tab unlocks.

**Option B — one SQL command:**

```sql
update public.profiles
set role = 'teacher', updated_at = now()
where email = 'teacher@example.com';
```

(Or simply register again with a fresh email — new signups self-heal from then on.)

---

## 9. COMMON ERRORS

### Error: "Still student" after the fix
Check in order:
1. Did you restart with `npx expo start -c`? (cached JS is the usual culprit)
2. Did you re-run `supabase/schema.sql`?
3. Was the account created **before** this fix? → Section 8 SQL.
4. Was the Teacher chip actually tapped on **this** sign-up?
5. Sign out, sign back in (sign-in runs `syncProfile`), or restart the app (boot runs it).
6. Check the Metro console for `syncProfile:` warnings — they print write/read-back failures instead of failing silently.

### Error: `Cannot find module 'expo-secure-store'`
```bash
npx expo install expo-secure-store
```

### Error: Signup fails with a profiles insert error
The trigger insert failed — check the metadata keys are exactly `full_name` / `role`. The `case when ... else 'student'` guard means a garbage role value can never violate the check constraint.

### Error: Role is teacher but the Teacher tab still locks
The gate re-reads `getProfile` on every focus. Switch tabs and come back; if it still locks, the DB row is not `'teacher'` — check Table Editor and the console warnings from `syncProfile`.

---

## 10. WHAT YOU SHOULD HAVE NOW

✅ Teacher chosen at sign-up → Teacher everywhere, verified by read-back
✅ Self-healing at sign-up, sign-in **and** boot — no silent failures left
✅ Teachers land directly in the **create-events section**
✅ Students unaffected
✅ One SQL command for accounts that predate the fix

**The role the user picks is now the role the app serves — and the app keeps proving it.** 🎉

---

## CHECK YOUR UNDERSTANDING (Quiz)

1. Why did the old `if (data.session && profile)` guard silently skip the role write?
2. Why is `upsert` + read-back safer than a bare `.update()`?
3. Why does `user_metadata` matter even when the device stash fails?
4. Why is `syncProfile` run at boot, not only at sign-in?
5. Why must the stash only be cleared **after** a verified read-back?

*(Answers: 1 — with email confirmation on, `session` is null, so the guard is false and the write never runs. 2 — update can match 0 rows without error; upsert always writes, and the read-back proves the final state. 3 — it's stored server-side on the user, so it survives other devices, cleared caches, and unavailable SecureStore — any future session can repair the role from it. 4 — a session that was already signed in never triggers sign-in again; boot repair is the only way to heal it without forcing a re-login. 5 — clearing on trust would permanently lose the intent when the write failed silently — the exact bug we're fixing.)*

---

*Bugfix completed 2026-09-26 (v2 — self-healing sync + create-events routing).*
