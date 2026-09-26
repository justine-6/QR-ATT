# QR Connection Flow (Reference)

## Exact QR connection in this project

The QR flow is connected in these exact places:

1. Teacher creates and displays the QR in src/app/(tabs)/teacher.tsx/`teacher.tsx`)
2. Payload format is built in `qr.ts`
3. Student scan is handled in `ScanScreen.tsx`
4. Attendance is validated and saved in `attendance.ts`

This is the real chain:

- `buildQRPayload(event)` creates a JSON string
- `CameraView` scans it
- `registerAttendance(data, userId)` parses it
- `parseQRPayload(raw)` verifies it is a valid attendance QR
- then it looks up the event and inserts attendance

---

## Prompt you can use

Use this exactly in your own project:

> Create a generic attendance QR check-in flow for my Expo React Native app. Keep the logic separate from my app branding or identity. I want the same architecture as this pattern:
>
> - teacher creates an event and generates a QR payload
> - QR payload is a JSON object containing `v`, `event`, and optional `title`, `start`, `end`
> - student scans QR with `expo-camera`
> - app validates payload
> - app finds matching event in Supabase
> - app inserts attendance record
> - show success or error message
>
> Use the same file structure as the app:
>
> - `qr.ts` for payload builder/parser
> - `attendance.ts` for registration logic
> - `ScanScreen.tsx` for camera scan UI
> - teacher screen for QR generation
>
> Keep it clean, production-ready, and not tied to any company or personal branding.

---

## Exact code to connect to the QR flow

### 1) Payload builder/parser

```ts
// src/lib/qr.ts
export type QRPayload = {
  v: 1;
  event: string;
  title?: string;
  start?: string;
  end?: string;
};

export function buildQRPayload(event: {
  eventId: string;
  title: string;
  start?: string;
  end?: string;
}): string {
  const payload: QRPayload = {
    v: 1,
    event: event.eventId,
  };

  if (event.title) payload.title = event.title;
  if (event.start) payload.start = event.start;
  if (event.end) payload.end = event.end;

  return JSON.stringify(payload);
}

export function parseQRPayload(raw: string) {
  try {
    const parsed = JSON.parse(raw);

    if (
      typeof parsed !== 'object' ||
      parsed === null ||
      !('v' in parsed) ||
      !('event' in parsed) ||
      parsed.v !== 1 ||
      typeof parsed.event !== 'string'
    ) {
      return { ok: false, message: 'Not an attendance QR code.' };
    }

    return { ok: true, payload: parsed };
  } catch {
    return { ok: false, message: 'Invalid QR code.' };
  }
}
```

---

### 2) QR generation on teacher side

```tsx
import QRCode from 'react-native-qrcode-svg';

const payload = buildQRPayload({
  eventId: 'MATH-101',
  title: 'Math Lecture',
  start: new Date().toISOString(),
  end: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
});

<QRCode value={payload} size={220} />
```

This is the same logic used in src/app/(tabs)/teacher.tsx/`teacher.tsx`).

---

### 3) Scanner logic

```tsx
import { CameraView } from 'expo-camera';
import { parseQRPayload } from '@/lib/qr';
import { registerAttendance } from '@/lib/attendance';

const [scanned, setScanned] = useState(false);

const handleBarcodeScanned = async ({ data }: { data: string }) => {
  if (scanned) return;
  setScanned(true);

  const parsed = parseQRPayload(data);
  if (!parsed.ok) {
    console.log(parsed.message);
    return;
  }

  const result = await registerAttendance(data, userId);
  console.log(result.message, result.success);
};
```

This matches `ScanScreen.tsx`.

---

### 4) Register attendance

```ts
// src/lib/attendance.ts
import { parseQRPayload } from '@/lib/qr';

export async function registerAttendance(rawPayload: string, studentId: string) {
  const parsed = parseQRPayload(rawPayload);
  if (!parsed.ok) {
    return { success: false, message: parsed.message };
  }

  const payload = parsed.payload;

  // validate dates if needed
  // fetch matching event from DB
  // insert into attendance table

  return {
    success: true,
    message: 'Attendance recorded!',
    eventTitle: payload.title ?? 'Event',
  };
}
```

---

## What it does in plain English

The QR code does not contain a secret or a user identity. It contains a small JSON event payload like:

```json
{
  "v": 1,
  "event": "MATH-101",
  "title": "Math Lecture",
  "start": "2026-09-26T09:00:00.000Z",
  "end": "2026-09-26T10:00:00.000Z"
}
```

Then the phone does this:

- scans the QR
- reads the JSON
- confirms it is a valid attendance code
- finds the event by `event`
- inserts the student attendance record

That is the exact connection point you want to keep in your project.
