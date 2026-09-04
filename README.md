# ZenSched Mosquito-Fogging Reference Kit

A copy-pasteable setup for a 1–4 truck mosquito-fogging crew (municipal night routes, HOA loops, resort grounds, private neighborhoods in Florida, the Gulf, and Southeast Asia) that wants an AI assistant to run block scheduling, GPS-verified fog visits, a local chemical extract, and invoicing. ZenSched handles the live schedule, the crew's phone app, GPS check-ins on the block, and the Fog Record (chemical, gallons, one spray photo). A small local database on your computer holds your contracts, blocks, prices, cadence, visit summaries, and invoices.

**You do not need to know how to program or write SQL to use this.** You type plain English to your AI assistant ("schedule tonight", "add the Palm Grove HOA", "what did Farid put down on Oak Loop", "who owes me money?") and the AI does the work using two tools you set up once. Setup takes about 15 minutes and is the only technical part.

If you *are* a developer, skip to [For developers](#for-developers).

## What this kit is not — read this first

**What it is:** GPS-verified proof that a truck was on the block, a Fog Record (which chemical, how many gallons, one spray photo), a local extract of those records for your own files, and invoices built from completed fogs.

**What it is not:**

- **Not an official FIFRA / FDACS / Form H chemical log.** `chemical_log` is *your* copy of what the crew typed on the phone (date, block, chemical, gallons, tech). It is not a FIFRA Section 7 / 7 CFR 110 applicator report, not an EPA log, not a Florida 5E-13.040 record or **FDACS-13652** monthly filing, not a Malaysia **Form H**, and not an NEA / DOH / municipality pesticide book. Florida FDACS, a Gulf municipality, and every Southeast Asian vector-control office still want *their* form. This kit does not produce it and does not claim you are compliant because you used it. Do not tell an FDACS, DOA, NEA, or municipality auditor "it's in ZenSched."
- **Not FieldSeeker ULV.** The night's trail is an ordered sequence of geofenced punches at block pins. There is no nozzle-on breadcrumb, no restricted-area sprayer geofence, and no spray-path GIS. Keep FieldSeeker if that is the district chemical / GIS system of record.
- **Not a spray-drift model or a larval-dip lab.** There is no wind/temperature log, no trap count, and no Bti dip record. The Fog Record is chemical + gallons + one photo.
- **Not a signed legal document.** The Fog Record has no signature field. On ZenSched a signature field replaces the Submit button, so adding one would make every stop look like the crew (or the city) had signed something. Submitting the form is just submitting the form.

If any of those is a deal-breaker, this kit is not for you. If you want block cadence, GPS on the street, and a local extract you can file next to your real state or ministry forms, read on.

## What lives where

**ZenSched (source of truth for what happened, when, and where):**

- Locations (one GPS pin per fog block; the check-in radius is a **policy** setting)
- Workers (crew with the mobile app)
- Events (one "Fog" job per block, renewed every 60 days)
- Shifts (each scheduled fog, with push notifications to the truck)
- GPS punches (check-in/check-out with distance-from-the-pin verification)
- The Fog Record form (chemical, gallons, one spray photo) and every submission
- Timesheets (verified hours worked)

**Local SQLite database (`mosquito.db`, on your computer):**

- Contracts (city / HOA / resort / private) with per-block fee and billing
- Blocks (the places you fog), including access notes (gate code, residents-only) that **never leave your computer**
- Cadence per block (weekly / biweekly / monthly / after-rain / on-demand) and next fog date
- Technicians, including applicator license numbers that **never leave your computer**
- Completed fog visits with a summary of each Fog Record, the chemical-log extract, and invoices
- Your settings (timezone, default crew, invoice prefix, Fog Record form id)

**Never duplicated:** the live schedule, punches, timesheets, and spray photos stay in ZenSched. The local database only stores *references* to them plus a short per-visit summary so you can answer "what did we put down on Oak Loop" without paying to re-read reports.

### Privacy note

Gate codes, residents-only notes, applicator license numbers, and contract / person names are stored only in the local database. `SKILL.md` forbids the AI from putting them into any ZenSched field. Location and event labels are **block code + street** (`Oak Loop - 1200 Oak Loop`), never the HOA, hotel, or a resident. Give gate codes to your crew yourself, by whatever channel you trust. ZenSched only ever sees the block label, the street address, and the GPS pin.

## How it works day to day

Your AI assistant has two sets of tools:

1. **ZenSched tools** (`location_create`, `shift_create`, `form_submissions`, `shift_list`, ...) that talk to ZenSched over the internet.
2. **A SQLite tool** (`sqlite_query`, `sqlite_execute`) that reads and writes `mosquito.db` on your computer.

When you say "schedule tonight," the AI reads which blocks are due from the local database (`next_fog_date` in the next 7 days), creates one shift per block on ZenSched, and tells you what it did. Your crew sees the stops in the app, checks in on the block (GPS-verified), fogs, fills in the Fog Record with a spray photo, and checks out. Later you say "record last night's fogs" and the AI pulls the completed shifts and records, saves a summary locally, advances each block's next date (weekly +1 week, after-rain clears it), and you can ask for the chemical extract. You never run SQL yourself. `SKILL.md` in this repo is the instruction sheet that teaches the AI how to do all of this; you paste it into your AI tool once.

A typical block costs about **$0.35** on ZenSched: GPS in $0.10 + GPS out $0.10 + reading a Fog Record that has the spray photo $0.15. Geocoding a new block is $0.03 once. The AI states the cost before it spends.

## Setup

### 0. What you need

- **An AI tool that supports MCP.** These instructions use Claude Desktop (Windows or Mac). Cursor works too.
- **Node.js 20 or newer.** The SQLite tool runs on it. Download the LTS installer from [nodejs.org](https://nodejs.org/) and run it with the defaults. This is the only software install.
- You do **not** need the `sqlite3` command-line program, Python, or Git.

### 1. Make a folder for your data

Create a folder where the database will live and write down its full path. Examples:

- Windows: `C:\Users\YourName\mosquito-ops`
- Mac: `/Users/yourname/mosquito-ops`

The database file will be created automatically inside this folder the first time the AI uses it.

### 2. Add both tools to your AI's config file

Open the MCP configuration file for your AI tool:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json` (paste that into the File Explorer address bar)
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json` (in Claude Desktop: Settings → Developer → Edit Config)
- **Cursor:** Settings → MCP → Add new global MCP server

Paste in the contents of `mcp.json.example` from this repo, then change one line, the `SQLITE_PATH`, to point at your folder from step 1 plus `\mosquito.db` (Windows) or `/mosquito.db` (Mac):

```json
{
  "mcpServers": {
    "zensched": {
      "url": "https://mcp.zensched.com/mcp",
      "headers": { "Authorization": "Bearer zsc_your_key_here" }
    },
    "mosquito-db": {
      "command": "npx",
      "args": ["-y", "easy-sqlite-mcp"],
      "env": { "SQLITE_PATH": "/Users/yourname/mosquito-ops/mosquito.db" }
    }
  }
}
```

**Windows path gotcha:** inside a JSON file every backslash must be doubled. Write `"C:\\Users\\YourName\\mosquito-ops\\mosquito.db"`, not `"C:\Users\..."`. A single backslash will silently break the config.

**Leave `zsc_your_key_here` exactly as it is for now.** You do not have a key yet. The ZenSched tools that create your account work without one, and you will fill this in during step 3.

Save the file and **fully quit and reopen** your AI tool (on Mac, Cmd-Q; on Windows, right-click the tray icon → Quit). It only reads this file on startup.

### 3. Create your ZenSched account

In a new chat, type:

> Call `zensched_guide`, then call `account_create` with org_name "My Mosquito Fogging Co" (use my real business name if I told you one). Show me the `zsc_` key it returns.

Copy the `zsc_` key. Go back to the config file from step 2, replace `zsc_your_key_here` with your real key, save, and fully quit and reopen the AI tool again.

Some clients can adopt the key mid-session with `account_use_key`; you can ask the AI to try that to keep going immediately, but still update the config file so the key survives restarts. Keep the key private; it is the password to your account.

### 4. Create the database tables

Open `schema.sql` from this repo in any text editor, copy the whole thing, and paste it into the chat with this message in front of it:

> Create these tables in my mosquito database. Run each statement one at a time using the SQLite tool, then list the tables to confirm.

The AI will run the statements one at a time and confirm the tables exist. The `mosquito.db` file now exists in your folder.

If you happen to have the `sqlite3` command-line tool, `sqlite3 mosquito.db < schema.sql` does the same thing, but it is not required.

### 5. Teach the AI the workflow

Paste the contents of `SKILL.md` into your AI tool as standing instructions. In Claude Desktop, create a Project and put it in the project instructions; in Cursor, save it as a rule. Then tell it your basics once:

> My business is GulfMist Mosquito in Tampa, Florida (Eastern time). Save that in settings, and set up the Fog Record form.

It writes those to the `settings` table, creates the Fog Record form on ZenSched (free), and saves the form id so every block gets it automatically.

**Check-in radius.** The default pin uses `checkin_radius_m=200` on `location_create`, but ZenSched **enforces** the radius through the account's policy, not per block. With geofencing on it raises anything under 100 m to about 91 m (300 ft). A fog truck drives the length of a block, so ask the AI to "set the check-in radius to 250 m" (`policy_update`) the first time, or to move the pin onto the middle of the street (`location_update`, free). Do not ask it to widen the radius "on that location" — that field is informational only.

### 6. Funding (only when asked)

The first 200 ZenSched tool calls per day are free. Some things are metered: creating a location (geocoding, $0.03), inviting a technician ($0.25), each GPS-verified check-in or check-out ($0.10), and reading a Fog Record ($0.05, or $0.15 when it has the spray photo). When a metered call happens without funds, the AI will get a `payment_required` response and tell you how to add the $5 activation deposit, which is credited to your balance. You will not be charged without seeing this first.

A typical block is about $0.35 (in + out + photo record). A truck doing 12 blocks a night is about $4.20 in meters that night, plus $0.03 the first time you add each block. The AI states the cost before it spends.

## Using it

Everything after setup is plain English. Examples:

- "Add Palm Grove HOA, board@palmgrove.example, 813-555-0160. Weekly $45 a block starting Monday 20:00. Two blocks: Oak Loop, 1200 Oak Loop, Tampa FL 33609, gate 4412; Canal Court, 80 Canal Court, Tampa FL 33609."
- "Add an after-rain fog at Orchid Bay Resort, Beach Road, $80, Thursday if it rains."
- "Invite Farid Hassan, farid@example.com, and make him the default crew."
- "Schedule tonight for Farid."
- "Record last night's fogs."
- "Chemical log for last week."
- "Draft invoices for everyone with uninvoiced work."
- "Who still owes me money?"
- "Palm Grove paid INV-2026-0001."
- "Pause Palm Grove until May."
- "It rained — fog Oak Loop tomorrow night."

See `QUICKSTART.md` for the first-week walkthrough and `example-workflow.md` for exactly which tools the AI calls behind each of these.

### What "invoice" means here

"Draft an invoice" records the invoice in your database (number, date, due date, amount, which visits) and the AI writes out a plain-text invoice you can paste into an email or text message, with a line per block and a note that the visit was GPS-verified. It does **not** generate a PDF, email it for you, or collect payment. Invoices do not list chemicals, mix rates, or license numbers unless you ask. Each invoice footer says this is not an official FIFRA / FDACS / Form H pesticide log and not a FieldSeeker ULV trail. When the contract pays, tell the AI ("Palm Grove paid INV-2026-0001") and it marks it paid. If you outgrow this, the invoice records are simple enough to import into any accounting tool.

## Mobile app for technicians

- **Android:** [Google Play](https://play.google.com/store/apps/details?id=com.zensched.app)
- **iOS:** [TestFlight](https://testflight.apple.com/join/Wp51m5Yq)

When you invite a crew member, they get an email, install the app, and can immediately see their blocks, check in and out with GPS verification, and fill in the Fog Record with one spray photo. The record is attached to each stop automatically. There is no signature step — they tap Submit.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| AI says it has no ZenSched tools | Config file not saved, or the app was not fully restarted | Check the JSON is valid (paste it into [jsonlint.com](https://jsonlint.com)), then quit and reopen the app |
| AI says it has no SQLite / `mosquito-db` tools | Node.js not installed, or bad `SQLITE_PATH` | Install Node.js LTS; on Windows check every backslash is doubled |
| `SQLITE_PATH` points nowhere / "unable to open database" | Folder from step 1 does not exist | Create the folder; the file is created automatically but the folder is not |
| ZenSched tools return an auth error | Key still says `zsc_your_key_here`, or was pasted with a space | Re-paste the key, restart |
| `payment_required` | Metered call with no balance | Follow the instructions in the response; $5 deposit |
| AI creates shifts at the wrong hour | Timezone not set, stale Florida DST, or you expected 8am instead of 20:00 | "Set my timezone offset to -04:00 in settings" (Florida EDT mid-March–early November; EST `-05:00` otherwise). SE Asia / Gulf have **no DST** — do not flip `+08:00` / `+04:00` / `+03:00`. Night fog defaults to 20:00 |
| Shift creation fails for dates a couple of months out | The block's 60-day ZenSched event has expired | Say "renew the events"; the AI runs the roll-over in `SKILL.md` and retries |
| Crew's check-in not GPS-verified on a long block | Pin is at one end, truck is at the other, or radius is still the house default | Ask the AI to widen `checkin_radius_m` with `policy_update` (not on the location), or run `location_update` / `location_refine` ($0.10) |
| Crew does not see the Fog Record | Form not assigned to that block's event before the shift was created | "Attach the Fog Record to Oak Loop's event" (`form_assign(form_id, event_id=…)`); it installs on the existing shift — do not cancel and recreate. Recreating with the same `shift-block-{id}-{date}` key would only replay the cancelled shift for 24 hours |
| "Chemical log" comes back empty | Visits not recorded yet, or the crew marked chemical None | "Record last night's fogs" first; None / zero-gallon rows are omitted on purpose |
| AI asks you to run SQL yourself | It does not have `SKILL.md` loaded | Re-paste `SKILL.md` as project instructions |
| AI refuses to put a gate code in ZenSched | Working as intended | Give it to the crew directly |
| AI offers a FIFRA / FDACS / Form H log or a FieldSeeker ULV path | It shouldn't | This kit does not produce those; file the official book in your binder or FieldSeeker |

If something is confusing or broken in ZenSched itself, ask the AI to call `feedback_submit` with a description. It is free, needs no account, and a human reads every submission.

## For developers

**Architecture.** Two MCP servers, no application code. The agent is the integration layer; `SKILL.md` is the spec it follows. ZenSched is authoritative for operations (schedule, punches, forms); SQLite is authoritative for CRM, cadence, fog-visit summaries, the chemical extract, and billing; each side stores only the other's **integer** IDs, plus a per-visit report summary cached locally because submission reads are metered.

**Data model decisions.**

- **`contracts` → `blocks` (places) → `fog_visits`.** A contract (city, HOA, resort, private) owns many blocks. Each block is one place: one ZenSched **location**, permanent, stored on `blocks.zensched_location_id` as an integer. Created with `location_create(name="<block_name> - <street>", street_address=..., checkin_radius_m=200, idempotency_key=...)` — the label is block code + street, never the contract or a person. `checkin_radius_m` on `location_create` is informational; the enforced radius is `policy_update(0, '{"checkin_radius_m": N}')`, and with geofencing on the platform raises values under 100 m to 300 ft. Fog trucks should set the policy to 200–300 m.
- **Events are capped at 60 days by ZenSched**, so an event cannot be a permanent job template. Each block holds its *current* event in `blocks.zensched_event_id` and its last covered date in `blocks.event_valid_until`. The agent creates a new event (`event_create(location_id, title="Fog - <block_name> - <street>", start_date, end_date=start+59 days, idempotency_key="event-block-{block_id}-{YYYYMMDD}")`) whenever a shift date is later than `event_valid_until`, calls `form_assign(form_id, event_id=...)` on it, and updates the row. `blocks_due` exposes `event_needs_roll` per row and `events_expiring` lists blocks due for renewal within 14 days. Shifts already created on the old event remain valid. When recording a completed visit whose `event_id` no longer matches a block, the agent falls back to `event_get(event_id).location_id` against `blocks.zensched_location_id`.
- **Cadence is next-fog-date on the block, not the contract.** `blocks.service_frequency` is `weekly | biweekly | monthly | after_rain | on-demand`. One municipal contract can fog Zone A Monday and Zone B Wednesday. `blocks_due` is every active block with `next_fog_date <= today+7` joined to its active contract, emitting `start_iso` / `end_iso` (preferred start or `settings.default_shift_start` which is **20:00**, duration from `default_shift_minutes`) and the shift `idempotency_key`.
- **The `advance_fog_date_on_visit` trigger** sets `last_fog_date` and `next_fog_date` on every visit insert: +7 / +14 / +1 month / **NULL** (after_rain and on-demand). Recording a one-off on a weekly block also moves the cadence; `SKILL.md` tells the agent to set the date back if the owner says so. "It rained" is an explicit `UPDATE blocks SET next_fog_date = ?` on an `after_rain` row.
- Rate lives on the **block** (`service_rate`) with a fallback to `contracts.per_block_fee`. `fill_visit_amount` snapshots that onto `fog_visits.amount` when the agent leaves it NULL.
- `fog_visits.zensched_shift_id` and `technicians.zensched_worker_id` are integer `UNIQUE`. `fog_visits.report_dc_id` holds the form `submission_id`. `chemical` is `CHECK`-constrained to the form's option labels.
- `fill_visit_technician` sets `technician_id` from `zensched_worker_id` when the agent leaves it NULL.
- `invoices.invoice_number` is auto-assigned by trigger as `{prefix}-{YYYY}-{0001}`.
- **`chemical_log`** is a view over treated visits (omits `chemical` `None` and `gallons` 0 / NULL). One row per visit. It does not transmit anything and is not a FIFRA / FDACS / Form H form or a FieldSeeker ULV path.
- `blocks.access_notes`, `technicians.license_no`, and contract / person names are the columns that must never be sent to ZenSched; `SKILL.md` rule 6 enforces it. The location label is `<block_name> - <street>`. `blocks_due` still *selects* `access_notes` so the agent can tell the owner to pass them to the crew.
- `PRAGMA foreign_keys = ON` is in `schema.sql` and `SKILL.md` tells the agent to run it per session; SQLite does not persist it.

**Fog Record form.** Created once with `form_create(title, fields_json, idempotency_key="form-fog-record")`; the exact `fields_json` is in `SKILL.md` and `example-workflow.md` (byte-identical) and was validated against ZenSched's `_validate_fields`. Every field carries an explicit `identifier` so submission `data` keys are stable (`chemical`, `gallons`, `spray`; section `sec_fog`). Option keys are derived by ZenSched from the labels (lowercase, non-alphanumerics → `_`, truncated at 30 characters); every option here is well under 30 characters, so nothing truncates. **No `signature` field** — the phone keeps a Submit button, and submitting is not a legal attestation. Attaching is `form_assign(form_id, event_id=...)`.

**Idempotency keys.** Deterministic, derived from local IDs:

- location: `loc-block-{block_id}`
- event: `event-block-{block_id}-{YYYYMMDD window start}`
- shift: `shift-block-{block_id}-{YYYYMMDD}`
- form_assign: `assign-fog-record-{event_id}`
- worker: `worker-{email}`
- form: `form-fog-record`

Same-night re-fog or a crew swap appends `-2`, then `-3`, and so on. Never reuse a cancelled shift's key (24-hour replay). ZenSched caches idempotent responses for 24 hours.

**Timestamps.** `shift_create` takes `start` and `end` in ISO 8601 with an explicit offset. Always use the business's local offset from `settings.timezone_offset` (e.g. `2026-09-07T20:00:00-04:00`), never `Z`. The view builds these strings so the agent does not have to. Night fog defaults to 20:00. Florida observes DST (`-04:00` mid-March to early November, `-05:00` otherwise). Southeast Asia and the Gulf do not — leave `+08:00` / `+07:00` / `+04:00` / `+03:00` alone year-round.

**Metered reads.** `form_submissions` and `form_export` bill $0.05 per submission read ($0.15 with media); `form_export` is preferred for a week at a time. The kit stores the summary and media URLs on `fog_visits` on first read so later chemical-log questions are answered from SQLite. `shift_list`, `shift_status`, `event_get`, and `timesheet_export(mode="hours"|"raw")` are free.

**SQLite MCP server.** `mcp.json.example` uses [`easy-sqlite-mcp`](https://github.com/chenkumi/easy-sqlite-mcp) (Node, `better-sqlite3`, `SQLITE_PATH` env var — **`mosquito.db`**). Its `sqlite_execute` calls `prepare()`, so it accepts **one statement per call**; `schema.sql` is written so every statement stands alone and is idempotent. Any SQLite MCP server with read and write tools will work; adjust the tool names in `SKILL.md`.

**Schema test.** The schema was verified by splitting the file into its 40 statements with `sqlite3.complete_statement` and executing each individually (as the MCP server does) twice for idempotency (seed rows not duplicated), then exercising: all 6 tables, 5 views, and 7 triggers present; every view on an empty database; the `advance_fog_date_on_visit` trigger for weekly (+7), biweekly (+14), monthly (+1 month), **after_rain → NULL**, and on-demand (NULL); `fill_visit_technician` from `zensched_worker_id`; `fill_visit_amount` from contract `per_block_fee` and block `service_rate` override; `UNIQUE` on `zensched_shift_id` and `technicians.zensched_worker_id`; every `CHECK` (`contract_type`, frequency, `preferred_start`, `chemical`); `blocks_due` `start_iso` / `end_iso` / `idempotency_key` / worker / minutes / amount; `event_needs_roll` flipping exactly when `event_valid_until < next_fog_date`; inactive and +20-day rows excluded; `events_expiring`; `chemical_log` omitting `None` and zero gallons; invoice numbering (auto `INV-2026-0001`, explicit number kept); `visits_to_invoice` / `invoices_outstanding` filters; cascade delete and technician set-null; `updated_at`; integer types on ZenSched ID columns. Form payload validated against `_validate_fields` (4 fields, no signature, SKILL.md byte-identical to example-workflow.md, every option key ≤ 30 characters). 99 checks, all passing.

## Support

- ZenSched docs: <https://www.zensched.com/docs/>
- Tool reference: <https://www.zensched.com/docs/tools/>
- Feedback: ask your AI to call `feedback_submit` (categories: `bug`, `friction`, `missing_capability`, `docs`, `billing`, `feature`, `other`)

## License

MIT. See `LICENSE`.
