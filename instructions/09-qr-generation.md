# Migration Phase 8 — QR Generation

> This is a **student lab activity**. This is **migration Phase 8** (the file is named `09` only because `09` is taken). In this phase we centralize QR **creation and parsing** in a dedicated `lib/qr.ts` module, so every screen agrees on one payload format.

---

## HOW TO USE THIS DOCUMENT (Read Me First)

In this phase you will:
1. **LEARN** — why the QR payload format must live in exactly one place
2. **CODE** — `lib/qr.ts`, then wire it into the Teacher screen and the attendance path
3. **VERIFY** — typecheck + generate a QR and scan it

**Time needed:** ~25 minutes
**You will need:** Phases 4-7 (Supabase data layer, roles, `lib/events.ts`).

---

## 1. WHAT ARE WE DOING AND WHY?

### The Problem

Right now the QR payload is built **inline** with `JSON.stringify({ v: 1, event, ... })` inside `teacher.tsx`, and **parsed** with a hand-rolled `JSON.parse` inside `registerAttendance`. Two screens each keep their own copy of the payload shape. If someone adds a field (say `room`) in one place and forgets the other, QR generation and QR reading silently disagree — and every scan fails.

### The Goal

Create **`lib/qr.ts`** with two single-source-of-truth functions:

| Function | Job |
|---|---|
| `buildQRPayload(event)` | Builds the JSON string the QR code displays. |
| `parseQRPayload(raw)` | Parses + validates a scanned string, returning a typed result. |

Then:
- `teacher.tsx` calls `buildQRPayload(...)` after the event is saved.
- `registerAttendance(...)` calls `parseQRPayload(raw)` instead of its inline `JSON.parse`.

### The Analogy: One Translator

Think of the QR code as a message written in a shared language. `lib/qr.ts` is the **only** dictionary for that language. The Teacher screen *writes* with it and the scanner *reads* with it — so they can never drift apart.

---

## 2. THE PAYLOAD FORMAT (unchanged!)

The QR still contains exactly what it did before — this phase only **centralizes** it:

```json
{
  "v": 1,
  "event": "EVT-2026-0002",
  "title": "Founders Day Assembly",
  "start": "2026-09-03T08:00:00",
  "end": "2026-09-03T10:00:00"
}
```

| Field | Meaning |
|---|---|
| `v` | Payload version. Always `1` for now — lets us support future formats safely. |
| `event` | The public event code (matches `events.event_code`). |
| `title` | Human-readable title (used if the event row doesn't exist yet). |
| `start` / `end` | Local ISO start/end times used for time-window validation. |

> 💡 Because `v` is checked before anything else, we can change the format later (a `v: 2`) without old QR codes crashing the app — they'd just be rejected with a clear message.

---

## 3. NEW FILE: `lib/qr.ts`

### 3a. The types

```typescript
export type QRPayload = {
  v: 1;
  event: string;
  title?: string;
  start?: string;
  end?: string;
};

export type ParseQRResult =
  | { ok: true; payload: QRPayload }
  | { ok: false; message: string };
```

| Type | Meaning |
|---|---|
| `QRPayload` | The one true shape of an attendance QR. |
| `ParseQRResult` | A **union**: either `{ ok: true, payload }` or `{ ok: false, message }`. Callers must branch on `ok` — the compiler forces you to handle failure. |

### 3b. `buildQRPayload` — generate

```typescript
export function buildQRPayload(event: {
  eventId: string;
  title: string;
  start?: string;
  end?: string;
}): string {
  const payload: QRPayload = {
    v: 1,
    event: event.eventId,
    title: event.title,
    start: event.start,
    end: event.end,
  };
  return JSON.stringify(payload);
}
```

- Takes the app's `event` shape (`eventId`, `start`, `end` — same names as `lib/events.ts`).
- Returns the JSON string for `<QRCode value={...} />`.

### 3c. `parseQRPayload` — validate

```typescript
export function parseQRPayload(raw: string): ParseQRResult {
  let payload: unknown;
  try {
    payload = JSON.parse(raw);
  } catch {
    return { ok: false, message: 'Invalid QR code.' };
  }

  if (
    typeof payload !== 'object' ||
    payload === null ||
    (payload as any).v !== 1 ||
    typeof (payload as any).event !== 'string' ||
    !(payload as any).event
  ) {
    return { ok: false, message: 'Not an attendance QR code.' };
  }

  return { ok: true, payload: payload as QRPayload };
}
```

| Step | Meaning |
|---|---|
| `try { JSON.parse(raw) }` | Not JSON at all → "Invalid QR code." |
| `v !== 1` or missing `event` | JSON but not ours → "Not an attendance QR code." |
| `return { ok: true, payload }` | Valid — hand back the typed payload. |

> ✅ Because it's a **discriminated union**, `if (result.ok)` gives TypeScript full knowledge of `result.payload` inside the branch. No `any` needed at the call site.

---

## 4. WIRING IT IN

### 4a. `teacher.tsx` — build after save

Before: QR only appears after a successful save (already true), but the payload was an inline `JSON.stringify`.
After:

```typescript
import { buildQRPayload } from '@/lib/qr';

// inside handleCreateEvent, after createEvent succeeds:
setPayload(buildQRPayload(event));
```

> ⚠️ Keep the ordering: **save first, QR second**. The QR must never be shown for an event that failed to persist — otherwise students scan a code the database doesn't know about.

### 4b. `registerAttendance` — parse with the shared reader

Before: inline `JSON.parse` + manual `payload.v !== 1` checks.
After: call `parseQRPayload(rawPayload)` and branch on `.ok`.

```typescript
const parsed = parseQRPayload(rawPayload);
if (!parsed.ok) {
  return { success: false, message: parsed.message };
}
const payload = parsed.payload;
// ...rest unchanged (time-window checks, event lookup, insert)
```

The rest of `registerAttendance` (time window, event find-or-create, attendance insert, duplicate handling) is untouched.

---

## 5. BEFORE vs AFTER — SIDE BY SIDE

| Aspect | BEFORE (Phase 7) | AFTER (Phase 8) |
|---|---|---|
| Payload shape | duplicated in `teacher.tsx` + `database.ts` | **one** definition in `lib/qr.ts` |
| Generation | inline `JSON.stringify` | `buildQRPayload(event)` |
| Parsing | inline `JSON.parse` + ad-hoc checks | `parseQRPayload(raw)` → typed union |
| Unknown QR handling | string messages | same messages, one source |
| Future format change (`v: 2`) | edit N places | edit one module |

---

## 5.5. STEP-BY-STEP EXECUTION GUIDE (what to type, in order)

### Step 1 — Create `lib/qr.ts` (NEW file, Section 3)
With `QRPayload`, `ParseQRResult`, `buildQRPayload`, `parseQRPayload`.

### Step 2 — Edit `app/(tabs)/teacher.tsx` (Section 4a)
- Add `import { buildQRPayload } from '@/lib/qr';`
- Replace the inline `JSON.stringify({ v: 1, event, ... })` with `setPayload(buildQRPayload(event));`
- Keep it **after** the successful `createEvent` call.

### Step 3 — Edit `lib/database.ts` (Section 4b)
- Add `import { parseQRPayload } from './qr';`
- Replace the inline `JSON.parse` + `v !== 1` checks with the `parseQRPayload` branch.
- Leave the time-window / event lookup / insert logic unchanged.

### Step 4 — Type check
```bash
npx tsc --noEmit
```
**Expected:** no errors. If `payload.event` is possibly-undefined, you removed the `!parsed.ok` early return — restore it.

### Step 5 — Run & test (Section 6)

### Step 6 — Tick off Section 7's checklist
Don't continue to Phase 9 until all boxes are checked.

---

## 6. TESTING YOUR WORK — THE LAB

### Step 1: Type check
```bash
npx tsc --noEmit
```
**Expected:** no errors.

### Step 2: Start the app
```bash
npx expo start
```

### Step 3: Happy path
1. Log in as **Teacher** → create an event → QR appears.
2. Log in as **Student** → Scan tab → scan that QR (or retype/show the payload).
3. ✅ "Attendance recorded!" — generation and parsing still agree.

### Step 4: Reject non-attendance QRs
1. Open the Scan tab and paste any random JSON, e.g. `{"hello":1}`.
2. ✅ "Not an attendance QR code." (not a crash)
3. Paste garbage that isn't JSON, e.g. `not-json`.
4. ✅ "Invalid QR code."

### Step 5: Regression — Teacher gate still works
1. Log in as **Student** → Teacher tab still shows "Teachers Only".

---

## 7. LAB CHECKLIST (Tick these off)

| # | Task | Done? |
|---|---|---|
| 1 | `npx tsc --noEmit` passes | ☐ |
| 2 | `lib/qr.ts` exists with `buildQRPayload` + `parseQRPayload` | ☐ |
| 3 | No inline `JSON.stringify({ v: 1, ... })` left in `teacher.tsx` | ☐ |
| 4 | No inline `JSON.parse(rawPayload)` left in `registerAttendance` | ☐ |
| 5 | Happy path still records attendance | ☐ |
| 6 | Random JSON → "Not an attendance QR code." | ☐ |
| 7 | Garbage text → "Invalid QR code." | ☐ |
| 8 | QR only appears after a successful save | ☐ |
| 9 | I can explain why one module owns the payload format | ☐ |

---

## 8. CHECK YOUR UNDERSTANDING (Quiz)

1. What are the two functions in `lib/qr.ts`, and which screen uses each?
2. Why is `ParseQRResult` a union type instead of a function that throws?
3. What is the `v` field for, and what happens when `v !== 1`?
4. Why must `setPayload(buildQRPayload(event))` come **after** `createEvent` succeeds?
5. If you add a `room` field to the payload, how many places must you change now? How many before this phase?

*(Answers at the bottom — try them first!)*

---

## 9. COMMON ERRORS

### Error: Student scans the QR but gets "Not an attendance QR code."
**Cause:** Generation and parsing disagree — usually a hand-edited `JSON.stringify` somewhere.
**Fix:** Always go through `buildQRPayload`. Never inline the object.

### Error: TS error on `parsed.payload` being possibly undefined
**Cause:** You didn't early-return on `!parsed.ok`.
**Fix:** `if (!parsed.ok) return ...;` before touching `parsed.payload`.

### Error: QR appears even when the save failed
**Cause:** `setPayload` is still in the catch path or before the error check.
**Fix:** Only call `setPayload` in the success branch.

---

## 10. WHAT YOU SHOULD HAVE NOW

✅ One module that owns the QR payload format
✅ Type-safe generation and parsing
✅ Non-attendance QRs rejected with clear messages
✅ Teacher screen only shows a QR after a successful save
✅ The scanner and the generator can no longer drift apart

**The QR pipeline is now single-sourced and validated.** 🎉

---

## CHECK YOUR UNDERSTANDING — ANSWERS

1. `buildQRPayload` (used by `teacher.tsx` to generate the QR) and `parseQRPayload` (used by `registerAttendance` to read/validate a scan).
2. A union makes failure **explicit and exhaustive**: the compiler forces every caller to branch on `ok`, so a `message` can't be silently ignored. Throwing would reintroduce the try/catch chains we removed.
3. A payload version marker. It lets future formats (`v: 2`) coexist with old QR codes — anything not `v: 1` is rejected with "Not an attendance QR code." instead of crashing.
4. A QR for an event that isn't in the database would be scannable but unregistrable. Save first, so every visible QR corresponds to a persisted row.
5. Now: one file (`lib/qr.ts`). Before: at least two (the Teacher screen's `JSON.stringify` and the scanner's `JSON.parse`) — the classic "forgot the other one" bug.

---

*Migration Phase 8 completed 2026-09-03.*
