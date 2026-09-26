# Migration Phase 9 — QR Attendance (Consolidation)

> This is a **student lab activity**. This is **migration Phase 9** (the file is named `10` because `10-qr-attendance.md` follows the numbering of the original lab). In this phase we **finish the migration**: attendance functions move into `lib/attendance.ts`, they reuse `getEventByCode` from `lib/events.ts`, and the legacy `lib/database.ts` is **deleted**.

---

## HOW TO USE THIS DOCUMENT (Read Me First)

In this phase you will:
1. **LEARN** — why deleting a file is the best proof that a refactor worked
2. **CODE** — move the last two functions, reuse the events service, delete `database.ts`
3. **VERIFY** — typecheck, grep, and run the full scan flow

**Time needed:** ~30 minutes
**You will need:** Phases 4-8 (Supabase data layer, roles, `lib/events.ts`, `lib/qr.ts`).

---

## 1. WHAT ARE WE DOING AND WHY?

### The Problem

For six phases, `lib/database.ts` has been the "everything file" — attendance, events, QR parsing... It's the last big ball of mud. Two screens (`scan.tsx`, `history.tsx`) still import from it, and it still does its own inline event lookup (`select` by `event_code`) even though `lib/events.ts` already has `getEventByCode`.

### The Goal

1. **Move** `registerAttendance` and `getAttendanceHistory` (plus their types) into `lib/attendance.ts`, where Phase 6 already put the teacher-side queries.
2. **Reuse** `getEventByCode` from `lib/events.ts` inside `registerAttendance` instead of a duplicate inline `select`.
3. **Repoint** `scan.tsx` and `history.tsx` to `@/lib/attendance`.
4. **Delete** `lib/database.ts`.

### The Analogy: Finishing the Move

Phases 7 and 8 moved the furniture out of the old house (`database.ts`) into new ones (`events.ts`, `qr.ts`). This phase moves the last two boxes and **turns off the lights** — if nothing breaks after the file is gone, you *proved* nothing depended on it.

---

## 2. THE NEW `lib/attendance.ts` LAYOUT

After this phase, `lib/attendance.ts` contains **everything attendance-related**:

| Section | Contents |
|---|---|
| Types | `AttendanceRecord`, `RegisterResult`, `Attendee`, `TeacherEventAttendance`, `TeacherEventSummary` (Phase 6) |
| Student writes | `registerAttendance` (moved here) |
| Student reads | `getAttendanceHistory` (moved here) |
| Teacher reads | `getTeacherEventAttendance`, `loadAttendeeNames`, `getTeacherEventSummary` (Phase 6) |

Import graph (no cycles):

```
attendance.ts ──> events.ts ──> supabase.ts
     │  └──────> qr.ts
     └─────────> supabase.ts
scan.tsx / history.tsx ──> attendance.ts
```

---

## 3. MOVING `registerAttendance`

The body is **unchanged** except for one improvement: the event find-or-create step now calls `getEventByCode(payload.event)` from `lib/events.ts` instead of its own inline `.select('id, title')`.

```typescript
import { getEventByCode } from './events';
import { parseQRPayload } from './qr';
import { supabase } from './supabase';

export async function registerAttendance(
  rawPayload: string,
  studentId: string
): Promise<RegisterResult> {
  const parsed = parseQRPayload(rawPayload);
  if (!parsed.ok) {
    return { success: false, message: parsed.message };
  }
  const payload = parsed.payload;

  // ...time-window checks unchanged...

  const foundEvent = await getEventByCode(payload.event);

  let event: { id: string; title: string };
  if (foundEvent) {
    event = { id: foundEvent.id, title: foundEvent.title };
  } else {
    const { data: newEvent, error: insertError } = await supabase
      .from('events')
      .insert([...])
      .select('id, title')
      .single();
    if (insertError) {
      return { success: false, message: 'Could not create event.' };
    }
    event = newEvent!;
  }

  // ...attendance insert + duplicate handling unchanged...
}
```

| Change | Why |
|---|---|
| `getEventByCode(payload.event)` | Reuse, don't duplicate — one query definition in `events.ts`. |
| Everything else identical | Behaviour must be byte-for-byte the same; this phase is *organization*, not features. |

> ⚠️ The find-or-create fallback (insert if the event doesn't exist) **stays**. A QR created by the Teacher tab is already saved, but a QR built manually or scanned while offline may not be — the scanner must still work.

---

## 4. MOVING `getAttendanceHistory`

Straight copy — the query is untouched:

```typescript
export async function getAttendanceHistory(
  studentId: string
): Promise<AttendanceRecord[]> {
  const { data, error } = await supabase
    .from('attendance')
    .select('id, scanned_at, events ( event_code, title )')
    .eq('student_id', studentId)
    .order('scanned_at', { ascending: false });

  if (error || !data) return [];

  return data.map((row: any) => ({
    id: row.id,
    eventId: row.events?.event_code ?? '',
    eventTitle: row.events?.title ?? '',
    scannedAt: row.scanned_at,
  }));
}
```

---

## 5. REPOINTING THE SCREENS

| File | Old import | New import |
|---|---|---|
| `app/(tabs)/scan.tsx` | `import { registerAttendance } from '@/lib/database';` | `import { registerAttendance } from '@/lib/attendance';` |
| `app/(tabs)/history.tsx` | `import { getAttendanceHistory, type AttendanceRecord } from '@/lib/database';` | `import { getAttendanceHistory, type AttendanceRecord } from '@/lib/attendance';` |

Nothing else in those files changes — same function names, same signatures (encapsulation, same as Phase 7).

---

## 6. DELETING `lib/database.ts`

```bash
# after tsc passes with the file still present:
rm lib/database.ts
```

Then **prove** it's gone:

```bash
grep -r "@/lib/database" app/ lib/ components/ || echo "NO REFERENCES — safe"
```

**Expected:** `NO REFERENCES — safe`

If grep finds a hit, fix that import first and re-run.

---

## 7. BEFORE vs AFTER — THE WHOLE MIGRATION

| Aspect | PHASE 3 (start) | PHASE 9 (end) |
|---|---|---|
| `lib/` files | `auth.ts`, `database.ts` (everything), `supabase.ts` | `auth.ts`, `supabase.ts`, `profiles.ts`, `events.ts`, `qr.ts`, `attendance.ts` |
| `lib/database.ts` | attendance + events + inline QR | **deleted** |
| Event queries | inline in `database.ts` | `lib/events.ts` |
| QR format | inline in 2 places | `lib/qr.ts` |
| Attendance | one grab-bag file | `lib/attendance.ts` (student + teacher) |
| Teacher tab | open to all | role-gated |

---

## 7.5. STEP-BY-STEP EXECUTION GUIDE (what to type, in order)

### Step 1 — Extend `lib/attendance.ts` (Sections 3-4)
- Add imports: `parseQRPayload` from `./qr`, `getEventByCode` from `./events`.
- Move `AttendanceRecord`, `RegisterResult`, `registerAttendance`, `getAttendanceHistory` from `lib/database.ts`.
- Replace the inline event `select` in `registerAttendance` with `getEventByCode(payload.event)` (keep the find-or-create insert fallback).

### Step 2 — Repoint imports (Section 5)
- `app/(tabs)/scan.tsx`: `@/lib/database` → `@/lib/attendance`.
- `app/(tabs)/history.tsx`: `@/lib/database` → `@/lib/attendance`.

### Step 3 — Type check BEFORE deleting
```bash
npx tsc --noEmit
```
**Expected:** no errors. If `database.ts` errors appear, they're unused leftovers — safe to delete next.

### Step 4 — Delete `lib/database.ts` (Section 6)
```bash
rm lib/database.ts
```
Then confirm zero references:
```bash
grep -r "@/lib/database" app/ lib/ components/ || echo "NO REFERENCES — safe"
```

### Step 5 — Final type check + export
```bash
npx tsc --noEmit
npx expo export --platform web
```

### Step 6 — Run & test (Section 8)

### Step 7 — Tick off Section 9's checklist (the final one 🎉)

---

## 8. TESTING YOUR WORK — THE LAB

### Step 1: Static proof
```bash
npx tsc --noEmit
grep -r "@/lib/database" app/ lib/ components/ || echo "NO REFERENCES — safe"
```
**Expected:** no TS errors, then `NO REFERENCES — safe`.

### Step 2: Start the app
```bash
npx expo start
```

### Step 3: Full student flow (after the move)
1. Log in as **Teacher** → Teacher tab → create event → QR appears.
2. Log in as **Student** → Scan tab → scan the QR.
3. ✅ "Attendance recorded!"
4. Open **History** tab → ✅ the event row is listed with its name and time.

### Step 4: Edge cases (must behave identically to before)
1. Scan the same QR twice → ✅ "Already registered for this event."
2. Scan a random JSON → ✅ "Not an attendance QR code."
3. Scan garbage text → ✅ "Invalid QR code."

### Step 5: Regression — Phase 6 teacher view
1. As **Teacher** → History tab → open the event → ✅ attendee names (or short IDs) still listed.

### Step 6: Regression — role gate
1. As **Student** → Teacher tab → ✅ "Teachers Only" lock screen.

---

## 9. FINAL LAB CHECKLIST (Tick these off)

| # | Task | Done? |
|---|---|---|
| 1 | `npx tsc --noEmit` passes | ☐ |
| 2 | `lib/attendance.ts` contains all attendance functions | ☐ |
| 3 | `registerAttendance` uses `getEventByCode` | ☐ |
| 4 | `scan.tsx` imports from `@/lib/attendance` | ☐ |
| 5 | `history.tsx` imports from `@/lib/attendance` | ☐ |
| 6 | `lib/database.ts` is deleted | ☐ |
| 7 | grep shows zero `@/lib/database` references | ☐ |
| 8 | Scan → History full flow works | ☐ |
| 9 | Duplicate scan + bad QR messages unchanged | ☐ |
| 10 | Teacher view (Phase 6) still works | ☐ |
| 11 | Teacher tab still role-gated | ☐ |
| 12 | I can explain the final `lib/` module map | ☐ |

---

## 10. CHECK YOUR UNDERSTANDING (Quiz)

1. Why is deleting `lib/database.ts` considered *proof* that the refactor worked?
2. Which two functions moved in this phase, and what is their new home?
3. Why does `registerAttendance` still insert an event if `getEventByCode` returns null?
4. List every module in `lib/` after this phase and one sentence on its job.
5. What two commands give you static proof before you delete anything?

*(Answers at the bottom — try them first!)*

---

## 11. COMMON ERRORS

### Error: `Cannot find module '@/lib/database'` after deleting
**Cause:** A file still imports it — likely one you forgot to repoint.
**Fix:** `grep -r "@/lib/database" app/ lib/ components/` and update each hit to `@/lib/attendance`.

### Error: Duplicate type names in `lib/attendance.ts`
**Cause:** You copied `AttendanceRecord`/`RegisterResult` but left the old declarations in place.
**Fix:** Keep exactly one declaration of each type per module.

### Error: Event found but no attendance row appears
**Cause:** You changed the insert while moving code — e.g. dropped the `student_id`/`event_id` fields.
**Fix:** Compare against the Phase 4 insert; this phase must not change behaviour.

### Error: `newEvent` possibly null
**Cause:** `.single()` typing with `!` removed.
**Fix:** Keep the `if (insertError) return ...` guard, then `event = newEvent!` or check null explicitly.

---

## 12. WHAT YOU SHOULD HAVE NOW

✅ A complete, modular `lib/` layer: auth, supabase, profiles, events, qr, attendance
✅ **No** grab-bag `database.ts` — the migration is finished
✅ Attendance scanning reusing the shared events service
✅ Every screen importing from the module that owns its data
✅ All behaviours preserved — same messages, same flows, same RLS

**The migration is complete. The old file is gone, and the app still works.** 🎉🎉

---

## CHECK YOUR UNDERSTANDING — ANSWERS

1. If the app typechecks and runs with the file deleted, nothing depended on it — the move was total. Deletion is the strongest form of "no dangling references."
2. `registerAttendance` and `getAttendanceHistory` → `lib/attendance.ts`.
3. Defensive find-or-create: a QR can exist without a DB row (hand-built, scanned offline, or created before `created_by` was set). The scanner must still record attendance rather than fail.
4. `auth.ts` — sign-in/sign-up session + `useAuth`; `supabase.ts` — the client; `profiles.ts` — role/profile reads; `events.ts` — event CRUD; `qr.ts` — payload build/parse; `attendance.ts` — all attendance reads/writes (student + teacher).
5. `npx tsc --noEmit` and `grep -r "@/lib/database" app/ lib/ components/` (expecting no output / "NO REFERENCES").

---

*Migration Phase 9 completed 2026-09-03.*
