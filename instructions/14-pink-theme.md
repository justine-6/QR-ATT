# Visual Refresh — Pink Aesthetic Theme

> This is a **student lab activity**. This restyles the app from the Phase 07 green kiosk palette to a soft **pink aesthetic** — same architecture (one token file drives the whole UI), new colors, plus a few leftover hardcoded colors swept into tokens.

---

## HOW TO USE THIS DOCUMENT (Read Me First)

In this phase you will:
1. **LEARN** — why re-theming is a one-file job when tokens are done right
2. **CODE** — new `constants/colors.ts` palette + a handful of hardcoded-color swaps
3. **VERIFY** — typecheck + eyeball every screen

**Time needed:** ~15 minutes
**You will need:** Phase 07 (visual identity tokens).

---

## 1. WHY THIS IS A ONE-FILE JOB

Phase 07 replaced hard-coded colors with `COLORS.*` tokens. Buttons, tabs, chips, badges, inputs, the loader, the header — everything already reads from `constants/colors.ts`. So switching the app's identity means **changing the token values**, then sweeping up the few stragglers that still hard-code a hex.

> 💡 The Analogy: `COLORS` is the paint locker. Every room was painted from it in Phase 07 — so repainting the building means mixing new paint in the locker, not repainting room by room.

---

## 2. THE NEW PALETTE

| Token | Before (kiosk green) | After (pink aesthetic) | Used by |
|---|---|---|---|
| `primary` | `#2E7D5B` | **`#DB2777`** | buttons, active tab, chips, links, badges, loader |
| `background` | `#F7F6F2` | **`#FDF6F9`** | every screen bg, splash |
| `surface` | `#EFF3F0` | **`#FAECF2`** | logo circle, pressed states, Student badge |
| `border` | `#DADFE3` | **`#F1DCE6`** | inputs, cards, tab bar hairline |
| `textPrimary` | `#14181F` | **`#1F1A1D`** | headings/body (warm ink) |
| `textSecondary` | `#5D6B7A` | **`#6E5A66`** | subtitles/hints (warm taupe) |
| `card` / `textOnPrimary` | white | white | cards / text on pink |
| `success` | `#2E7D5B` | `#2E7D5B` (kept) | scan success |
| `danger` | `#B3261E` | `#B3261E` (kept) | error text |
| `warning` / `shadow` / `logo` | as before | `#C97A2B` / `#1F1A1D` / `#DB2777` | misc |

**Design notes:**
- **White on `#DB2777` ≈ 4.6:1 contrast** — passes WCAG AA for the 17px bold button labels.
- Semantic colors (green success, red danger, amber warning) are **deliberately kept** so success/error still read as success/error against the pink chrome.
- `primary + '14'` (the active role-chip tint) automatically becomes a faint pink wash — no code change needed.

---

## 3. HARDCODED COLOR SWEEPS

The token change catches 95% of the UI. These stragglers were still literal hex values and are now token-driven:

| File | Before | After |
|---|---|---|
| `app/(tabs)/scan.tsx` | `#2E7D32` / `#C62828` (scan result) | `COLORS.success` / `COLORS.danger` |
| `app/(tabs)/teacher.tsx` | `#C62828` (error message) | `COLORS.danger` |
| `app/+not-found.tsx` | `#25292e` bg / `#fff` link | `COLORS.background` / `COLORS.primary` |
| `app.json` (splash) | `#ffffff` | `#FDF6F9` |
| `app/(tabs)/profile.tsx` | Student badge = `COLORS.logo` (= same green as Teacher) | Student badge = `COLORS.surface` + ink text; Teacher stays `primary` + white |

The profile-badge change also fixes a **real ambiguity**: previously Student and Teacher badges were literally the same color (both `#2E7D5B`, later both pink). Now: **Teacher = pink pill, Student = neutral pill** — distinguishable at a glance.

---

## 4. STEP-BY-STEP EXECUTION GUIDE (what to type, in order)

### Step 1 — Replace `constants/colors.ts` (Section 2)
New token values: `primary #DB2777`, `background #FDF6F9`, `surface #FAECF2`, `border #F1DCE6`, `textPrimary #1F1A1D`, `textSecondary #6E5A66`, `logo #DB2777`; keep `card`, `textOnPrimary`, `success`, `danger`, `warning`, `shadow`.

### Step 2 — Sweep hardcoded colors (Section 3)
- `scan.tsx`: success/error styles → `COLORS.success` / `COLORS.danger`.
- `teacher.tsx`: `messageError` → `COLORS.danger`.
- `+not-found.tsx`: import `COLORS`, bg → `COLORS.background`, link → `COLORS.primary`.
- `profile.tsx`: add `roleBadgeTextStudent` (`color: COLORS.textPrimary`); Student badge bg → `COLORS.surface`; apply the new text style in the Student branch.
- `app.json`: splash `"backgroundColor": "#FDF6F9"`.

### Step 3 — Type check
```bash
npx tsc --noEmit
```
**Expected:** no errors.

### Step 4 — Run & test (Section 5)
```bash
npx expo start
```

### Step 5 — Tick off Section 6's checklist.

---

## 5. TESTING YOUR WORK — THE LAB

### Step 1: Type check
```bash
npx tsc --noEmit
```

### Step 2: Start the app
```bash
npx expo start
```

### Step 3: Walk every screen
1. **Login / Register** — pink-tinted bg, pink primary button, pink active role chip, warm ink text.
2. **Home** — pink logo circle, pink primary CTA.
3. **Scan** — permission + result messages in token colors; scan a QR → green success / red error still distinct from the pink chrome.
4. **History** — student rows, pink count badges (teacher), Student/Teacher views.
5. **Teacher** — form, chips, error message in `COLORS.danger`; QR unchanged.
6. **Profile** — Teacher badge pink pill, Student badge neutral pill.
7. **Not-found** — on-brand light bg with pink link (type a bad URL).

### Step 4: Regression
Create event → scan → history still works (colors only, zero logic touched).

---

## 6. LAB CHECKLIST (Tick these off)

| # | Task | Done? |
|---|---|---|
| 1 | `npx tsc --noEmit` passes | ☐ |
| 2 | `constants/colors.ts` matches the Section 2 table | ☐ |
| 3 | Zero stray `#C62828` / `#2E7D32` / `#25292e` in app code | ☐ |
| 4 | Splash bg is `#FDF6F9` | ☐ |
| 5 | Login/Register/Home show pink primary | ☐ |
| 6 | Success/error messages still read green/red | ☐ |
| 7 | Teacher vs Student badges are visually distinct | ☐ |
| 8 | Tab bar active tint is pink, borders pink-tinted | ☐ |
| 9 | Scan → attendance round-trip unaffected | ☐ |
| 10 | I can explain why one file re-themed the whole app | ☐ |

---

## 7. CHECK YOUR UNDERSTANDING (Quiz)

1. Why did changing ~7 values in one file restyle every screen?
2. Why keep `success` green and `danger` red instead of making everything pink?
3. What does the active role chip's `COLORS.primary + '14'` produce now?
4. Why was the Student badge change more than a color preference?
5. Why did `app.json`'s splash color need updating too?

*(Answers: 1 — Phase 07 removed hardcoded colors; all components read `COLORS.*`, so the token swap propagates everywhere. 2 — semantic colors must stay recognizable; a pink "success" would be ambiguous next to pink chrome. 3 — `#DB277714` — a ~8% alpha pink wash on the active chip. 4 — the old Student badge used `COLORS.logo`, which was identical to `primary`, so both roles looked the same. 5 — it's the first paint on app launch; leaving it white would flash a mismatched color before the pink screens render.)*

---

## 8. WHAT YOU SHOULD HAVE NOW

✅ A cohesive pink aesthetic across every screen
✅ No stray hardcoded hex colors in app code
✅ Distinct Teacher / Student badges
✅ Semantics preserved — success/error/warning still mean what they say
✅ Zero logic changes — the whole refresh is presentation-only

**One locker of pink paint, one repaint, zero regressions.** 🎉

---

*Visual refresh completed 2026-09-26.*
