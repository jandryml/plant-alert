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
- **90 days of history.** A nightly `pg_cron` job deletes watering events and
  deleted-plant tombstones older than 90 days, so the full-table pull stays
  small. The app trims its local copy the same way.
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
2. In **Authentication → Sign In / Providers**, turn on **Allow anonymous
   sign-ins**.
3. In the SQL Editor, run [`supabase/schema.sql`](supabase/schema.sql). It
   creates the tables, the `plant-photos` storage bucket, the access policies
   and the nightly retention job.
4. In **Project Settings → API**, copy the Project URL and the `anon` public key.
5. In the app: **Settings** → paste both, and tap **Generate** next to
   Household code.
6. Enter the **same three values** on the second phone, tap **Sync now** on each.

### How access works

Each phone signs in as its own anonymous Supabase user; the session lives in
the Keychain. On first sync the phone calls `join_household(code)`, which
creates the household if it is the first phone with that code and adds the
user as a member. Row and photo policies then admit a user only to households
they belong to, so the `anon` key on its own reads nothing.

The code is stored only as a SHA-256 hash and must be at least 12 characters;
the generated ones are about 80 bits. Anyone holding the code can still join,
so keep it between the two of you. If a phone loses its session, it signs in
as a new user and rejoins with the stored code on its own.

### Upgrading from the first version

The first version keyed rows by the code itself and let the `anon` role read
everything. In the SQL Editor run `drop table if exists plants,
watering_events;`, empty the `plant-photos` bucket, then follow the setup
above. Codes shorter than 12 characters have to be replaced. When each phone
joins, it re-uploads everything it has, photos included.

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
