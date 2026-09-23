# Plant Alert

A small iOS app for two people to look after the same house plants. Add a plant,
say how often and how much it needs watering, and get one notification each
morning listing whatever is due.

## How it works

- **Local first.** Everything lives in a SwiftData store on the phone, so the
  app works offline and with no account.
- **Shared through Supabase.** Both phones push to and pull from two Postgres
  tables. Conflicts resolve last-write-wins on `updated_at`; deletes are soft,
  so a removal propagates instead of being resurrected by the next pull.
- **Photos live in Supabase Storage**, not in the table. Rows carry only an
  `image_path`, which keeps them small enough that the app can keep pulling the
  whole table on every sync. Each photo is downscaled to a 1024px long edge
  before it is stored, and its path carries a fresh UUID so the other phone can
  tell a replacement from the picture it already has.
- **Reminders are local notifications.** The next 14 days of digests are
  scheduled ahead and rebuilt whenever anything changes — a notification's text
  is fixed when it is scheduled, so one repeating trigger could never name the
  right plants.

### Why not CloudKit

CloudKit (and therefore `CKShare`) needs a paid Apple Developer Program
membership; free provisioning profiles cannot carry the iCloud or push
entitlements at all. Supabase's free tier does the same job for two people on a
free Apple ID. Those entitlements have been stripped from
`plant_alert.entitlements` so the app signs with a free account.

## Setup

1. Create a free project at [supabase.com](https://supabase.com).
2. In the SQL Editor, run [`supabase/schema.sql`](supabase/schema.sql). It
   creates the tables and the `plant-photos` storage bucket.
3. In **Project Settings → API**, copy the Project URL and the `anon` public key.
4. In the app: **Settings** → paste both, and pick a household code.
5. Enter the **same three values** on the second phone, tap **Sync now** on each.

### On the household code

The `anon` key plus a household code is all it takes to read your plants — the
RLS policy in the schema grants the anonymous role full access, which is what
lets the app work without user accounts. Treat the household code as a password
and pick something unguessable, or add real Supabase auth if you want the data
properly locked down.

### Upgrading an existing project

If you ran an earlier version of the schema, add the photo support with:

```sql
alter table plants add column if not exists image_path text;
```

plus the `storage.buckets` and `storage.objects` statements at the end of
`schema.sql`.

## Running it

The deployment target is iOS 18.5. Open `plant-alert.xcodeproj` and run.

On a free Apple ID, set your team under **Signing & Capabilities** and note that
free-provisioned builds stop launching after 7 days and need re-installing from
Xcode.

Tests:

```sh
xcodebuild test -project plant-alert.xcodeproj -scheme plant-alert \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Layout

```
plant-alert/
  Models/      Plant, WateringEvent, the editor's draft type, photo handling,
               symbol/colour palette
  Services/    Settings, Supabase REST client, sync engine, notification scheduling
  Views/       Plant list, detail, editor, settings
supabase/
  schema.sql   Run this once in the Supabase SQL Editor
```
