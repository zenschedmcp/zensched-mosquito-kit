# Example Workflow: What the AI Does Behind Each Request

This shows the exact tool calls the agent makes for a first week of operation, following `SKILL.md`. The owner only types the quoted lines; everything else is the agent's work. Assumes setup from `QUICKSTART.md` is complete (both MCP servers configured, `schema.sql` loaded, `SKILL.md` given as instructions).

IDs and responses are illustrative. ZenSched IDs are integers.

Shop: **GulfMist Mosquito**, Tampa, Florida, Eastern time (`-04:00` in September). One HOA (two weekly blocks) plus one after-rain resort block, one crew, then invoice.

Access notes (gate code) and any applicator license number stay in SQLite. They are never sent to ZenSched.

## Session start (every session)

```
sqlite_execute: PRAGMA foreign_keys = ON;
sqlite_query:   SELECT key, value FROM settings;
  → business_name = My Mosquito Fogging Co, timezone_offset = -05:00,
    default_worker_id = NULL, default_shift_start = 20:00,
    default_shift_minutes = 20, invoice_due_days = 30, invoice_prefix = INV,
    fog_record_form_id = NULL, event_window_days = 60,
    default_checkin_radius_m = 200
```

## "My business is GulfMist Mosquito in Tampa, Florida, Eastern time."

```
sqlite_execute: UPDATE settings SET value = 'GulfMist Mosquito' WHERE key = 'business_name';
sqlite_execute: UPDATE settings SET value = '-04:00' WHERE key = 'timezone_offset';
```

> Saved. I'll schedule everything in Eastern time (-04:00), default 20:00 night fog. You don't have a Fog Record form yet; it's free to create and every block will come back with chemical, gallons, and one spray photo. No signature — this is an internal visit record, not an official FIFRA or state pesticide log. Want me to set it up now?

Owner: *"yes"*

```
form_create:
  title: "Fog Record"
  idempotency_key: "form-fog-record"
  fields_json: (the JSON below, passed as one string)
```

```json
[
  {"type": "section", "label": "Fog record", "identifier": "sec_fog",
   "text": "Fill this in before you leave the block. Photograph the spray. This is an internal fog-visit record, not an official FIFRA pesticide-use log and not a state applicator report."},
  {"type": "select", "label": "Chemical", "identifier": "chemical", "required": true,
   "options": ["Permethrin", "Malathion", "Naled", "Pyrethrin", "Deltamethrin", "None"]},
  {"type": "number", "label": "Gallons", "identifier": "gallons", "required": true},
  {"type": "photo", "label": "Spray photo", "identifier": "spray", "max_images": 1}
]
```

```
  → form_id: 501, fields: [ ...4 fields echoed with identifiers... ]

sqlite_execute: UPDATE settings SET value = '501' WHERE key = 'fog_record_form_id';
```

> Fog Record form created. I'll attach it to every block automatically. There is no signature step. This is not an official FIFRA log.

Optional, first time, for a truck driving the block:

```
policy_get: policy_id 0
policy_update:
  policy_id: 0
  settings_json: '{"geofence_enabled": true, "require_on_site": true, "checkin_radius_m": 250}'
```

The radius is on the **policy**, not on any block.

## "Add Palm Grove HOA, board@palmgrove.example, 813-555-0160. Weekly $45 a block starting Monday 2026-09-07 at 20:00. Two blocks: Oak Loop, 1200 Oak Loop, Tampa FL 33609, gate 4412; Canal Court, 80 Canal Court, Tampa FL 33609."

```
sqlite_execute:
  INSERT INTO contracts (contract_name, contract_type, contact_email, contact_phone,
                         billing_email, per_block_fee)
  VALUES ('Palm Grove HOA', 'hoa', 'board@palmgrove.example', '813-555-0160',
          'board@palmgrove.example', 45.00);
  → lastInsertRowid = 1

sqlite_execute:
  INSERT INTO blocks (contract_id, block_name, address, city, state, zip, place_label,
                      access_notes, service_frequency, next_fog_date, preferred_start)
  VALUES (1, 'Oak Loop', '1200 Oak Loop', 'Tampa', 'FL', '33609', 'Block - Oak Loop',
          'Gate 4412. Residents-only after 19:00.',
          'weekly', '2026-09-07', '20:00');
  → lastInsertRowid = 1

sqlite_execute:
  INSERT INTO blocks (contract_id, block_name, address, city, state, zip, place_label,
                      service_frequency, next_fog_date, preferred_start)
  VALUES (1, 'Canal Court', '80 Canal Court', 'Tampa', 'FL', '33609', 'Block - Canal Court',
          'weekly', '2026-09-07', '20:20');
  → lastInsertRowid = 2
```

Agent (first metered call this session, rule 11):

> Creating the two Palm Grove pins on ZenSched costs $0.06 for geocoding ($0.03 each). If your account isn't funded yet you'll get a prompt for the $5 activation deposit. Go ahead?

Owner: *"yes"*

```
location_create:
  name: "Block - Oak Loop"
  street_address: "1200 Oak Loop, Tampa, FL 33609"
  checkin_radius_m: 200
  idempotency_key: "loc-block-1"
  → location_id: 9301, lat: 27.9412, lng: -82.5210, pin_quality: "street"
    billing: { meter: "geocode", units: 1, price: 0.03 }

location_create:
  name: "Block - Canal Court"
  street_address: "80 Canal Court, Tampa, FL 33609"
  checkin_radius_m: 200
  idempotency_key: "loc-block-2"
  → location_id: 9302
```

The gate code is **not** in `notes`. It lives only in `blocks.access_notes`. `checkin_radius_m` on the location is informational; the enforced radius is the policy.

```
event_create:
  location_id: 9301
  title: "Fog - Oak Loop"
  start_date: "2026-09-07"
  end_date:   "2026-11-05"          ← start + 59 days (60-day cap)
  idempotency_key: "event-block-1-20260907"
  → event_id: 7301

form_assign:
  form_id: 501
  event_id: 7301
  → status: "assigned", form_id: 501, event_id: 7301, policy_id: 0

sqlite_execute:
  UPDATE blocks SET zensched_location_id = 9301, zensched_event_id = 7301, event_valid_until = '2026-11-05'
  WHERE block_id = 1;

event_create:
  location_id: 9302
  title: "Fog - Canal Court"
  start_date: "2026-09-07"
  end_date:   "2026-11-05"
  idempotency_key: "event-block-2-20260907"
  → event_id: 7302

form_assign: form_id 501, event_id 7302

sqlite_execute:
  UPDATE blocks SET zensched_location_id = 9302, zensched_event_id = 7302, event_valid_until = '2026-11-05'
  WHERE block_id = 2;
```

> Added Palm Grove HOA. Oak Loop and Canal Court, weekly $45 each, next fog Monday Sep 7 at 20:00 / 20:20. The gate code is saved on your computer only; give it to Farid directly. Both ZenSched events run through Nov 5; I'll renew them automatically when scheduling gets that far.

## "Add an after-rain fog for Orchid Bay Resort, manager@orchidbay.example, Beach Road, Tampa FL 33615, Thursday 2026-09-10 at 20:30, $80."

Same pattern. Frequency is `after_rain`. The agent does not re-ask about the $0.03 (owner already approved geocoding this session).

```
sqlite_execute:
  INSERT INTO contracts (contract_name, contract_type, contact_email, billing_email, per_block_fee)
  VALUES ('Orchid Bay Resort', 'resort', 'manager@orchidbay.example',
          'manager@orchidbay.example', 80.00);
  → lastInsertRowid = 2

sqlite_execute:
  INSERT INTO blocks (contract_id, block_name, address, city, state, zip, place_label,
                      service_rate, service_frequency, next_fog_date, preferred_start)
  VALUES (2, 'Beach Road', 'Beach Road', 'Tampa', 'FL', '33615', 'Block - Beach Road',
          80.00, 'after_rain', '2026-09-10', '20:30');
  → lastInsertRowid = 3

location_create:
  name: "Block - Beach Road"
  street_address: "Beach Road, Tampa, FL 33615"
  checkin_radius_m: 200
  idempotency_key: "loc-block-3"
  → location_id: 9303

event_create:
  location_id: 9303
  title: "Fog - Beach Road"
  start_date: "2026-09-10"
  end_date:   "2026-11-08"
  idempotency_key: "event-block-3-20260910"
  → event_id: 7303

form_assign: form_id 501, event_id 7303

sqlite_execute:
  UPDATE blocks SET zensched_location_id = 9303, zensched_event_id = 7303, event_valid_until = '2026-11-08'
  WHERE block_id = 3;
```

> Added Orchid Bay Resort, Beach Road. After-rain fog at $80, Thursday Sep 10 at 20:30. After Farid records it the next date clears — say "it rained" when you want it back on the list.

## "Invite Farid Hassan, farid@example.com, and make him the default."

> Inviting a technician costs $0.25. OK?

Owner: *"yes"*

```
worker_invite:
  email: "farid@example.com"
  first_name: "Farid"
  last_name: "Hassan"
  idempotency_key: "worker-farid@example.com"
  → worker_id: 701, status: "invited", invitation_sent: true
    billing: { meter: "worker_invite", units: 1, price: 0.25 }

sqlite_execute:
  INSERT INTO technicians (technician_name, email, zensched_worker_id)
  VALUES ('Farid Hassan', 'farid@example.com', 701);
  → lastInsertRowid = 1

sqlite_execute: UPDATE settings SET value = '701' WHERE key = 'default_worker_id';
```

> Invited Farid. He'll get an email with the app link and an activation code. He's the default crew now. Remember to give him Palm Grove's gate code; I keep that off ZenSched on purpose.

## "Schedule this week for Farid."

```
sqlite_query: SELECT * FROM blocks_due;
  → 2026-09-07 | Oak Loop     | weekly     | $45 | 20 min
               | block 1 | evt 7301 | event_needs_roll 0 | worker 701 Farid
               | start_iso 2026-09-07T20:00:00-04:00 | end_iso 2026-09-07T20:20:00-04:00
               | shift-block-1-20260907
    2026-09-07 | Canal Court  | weekly     | $45 | 20 min
               | block 2 | evt 7302 | event_needs_roll 0 | worker 701 Farid
               | start_iso 2026-09-07T20:20:00-04:00 | end_iso 2026-09-07T20:40:00-04:00
               | shift-block-2-20260907
    2026-09-10 | Beach Road   | after_rain | $80 | 20 min
               | block 3 | evt 7303 | event_needs_roll 0 | worker 701 Farid
               | start_iso 2026-09-10T20:30:00-04:00 | end_iso 2026-09-10T20:50:00-04:00
               | shift-block-3-20260910
  (3 rows)

shift_create:
  event_id: 7301
  worker_id: 701
  start: "2026-09-07T20:00:00-04:00"
  end:   "2026-09-07T20:20:00-04:00"
  idempotency_key: "shift-block-1-20260907"
  → shift_id: 89011, status: "scheduled", forms_installed: [501]

shift_create:
  event_id: 7302
  worker_id: 701
  start: "2026-09-07T20:20:00-04:00"
  end:   "2026-09-07T20:40:00-04:00"
  idempotency_key: "shift-block-2-20260907"
  → shift_id: 89012, status: "scheduled", forms_installed: [501]

shift_create:
  event_id: 7303
  worker_id: 701
  start: "2026-09-10T20:30:00-04:00"
  end:   "2026-09-10T20:50:00-04:00"
  idempotency_key: "shift-block-3-20260910"
  → shift_id: 89013, status: "scheduled", forms_installed: [501]
```

> Scheduled 3 blocks for Farid this week:
> - Mon 9/7 20:00–20:20  Palm Grove HOA, Oak Loop
> - Mon 9/7 20:20–20:40  Palm Grove HOA, Canal Court
> - Thu 9/10 20:30–20:50 Orchid Bay Resort, Beach Road (after rain)
>
> Farid has been notified in the app and every stop has the Fog Record attached. Each block is about $0.35 once he punches in and out and you read the spray photo ($0.10 + $0.10 + $0.15). Pass him the Palm Grove gate code yourself.

Nothing is written to SQLite here. If the owner asks "schedule this week" again, the identical idempotency keys make ZenSched return the same three shifts instead of creating duplicates.

## Farid does the work

Monday 19:58, Oak Loop, in the ZenSched app: **Check in** (GPS: 42 m from the pin, verified, $0.10). Fogs the loop. Opens **Fog Record**: Chemical = Permethrin; Gallons = 2.5; one spray photo. Submits (no signature). **Check out** 20:17 ($0.10).

Monday 20:22, Canal Court: check in, fog. Fog Record: Permethrin, 2.0 gal, one photo. Check out 20:38.

Thursday 20:28, Beach Road: check in. Fog Record: Permethrin, 3.0 gal, one photo. Check out 20:49.

## "Record last night's fogs." (and Thursday)

```
shift_list:
  date_from: "2026-09-07"
  date_to:   "2026-09-13"
  status:    "checked_out"
  → shifts: [
      { shift_id: 89011, event_id: 7301, worker_id: 701, date: "2026-09-07", start: "20:00", end: "20:20", status: "checked_out" },
      { shift_id: 89012, event_id: 7302, worker_id: 701, date: "2026-09-07", start: "20:20", end: "20:40", status: "checked_out" },
      { shift_id: 89013, event_id: 7303, worker_id: 701, date: "2026-09-10", start: "20:30", end: "20:50", status: "checked_out" }
    ], count: 3

sqlite_query: SELECT zensched_shift_id FROM fog_visits WHERE zensched_shift_id IN (89011, 89012, 89013);
  → (none; not yet recorded)

sqlite_query: SELECT block_id, contract_id FROM blocks WHERE zensched_event_id = 7301;
  → 1, 1
```

Agent (metered read, rule 11):

> There are 3 fog records to pull, all with a spray photo, so about $0.45 ($0.15 each). I'll read them once and keep the summaries locally. That's the last piece of the ~$0.35/block meter (punches already billed when Farid checked in and out). OK?

Owner: *"go"*

```
form_export:
  form_id: 501
  since: "2026-09-07"
  until: "2026-09-13"
  format: "json"
  → row_count: 3, rows: [
      { submission_id: 5501, worker_id: 701, event_id: 7301, submitted_at: "2026-09-07 20:14:08",
        data: { chemical: "permethrin", gallons: 2.5 },
        media: [ { cdn_url: "https://cdn.zensched.com/m/.../oak.jpg" } ] },
      { submission_id: 5502, worker_id: 701, event_id: 7302, submitted_at: "2026-09-07 20:35:22",
        data: { chemical: "permethrin", gallons: 2.0 },
        media: [ { cdn_url: "https://cdn.zensched.com/m/.../canal.jpg" } ] },
      { submission_id: 5503, worker_id: 701, event_id: 7303, submitted_at: "2026-09-10 20:46:01",
        data: { chemical: "permethrin", gallons: 3.0 },
        media: [ { cdn_url: "https://cdn.zensched.com/m/.../beach.jpg" } ] }
    ]
    billing: { meter: "form_media", units: 3, price: 0.45 }

shift_status: shift_id 89011
  → status "checked_out", actual_in "2026-09-07T19:58:10-04:00", actual_out "2026-09-07T20:17:05-04:00",
    punches: [ { type: "in", gps_verified: true, distance_from_site_m: 42 },
               { type: "out", gps_verified: true, distance_from_site_m: 38 } ]
(free)

sqlite_execute:
  INSERT INTO fog_visits (contract_id, block_id, completed_date, amount,
                          zensched_shift_id, zensched_event_id, zensched_worker_id,
                          actual_in, actual_out, duration_minutes, gps_verified, report_dc_id,
                          chemical, gallons, photo_urls)
  VALUES (1, 1, '2026-09-07', 45.00,
          89011, 7301, 701,
          '2026-09-07T19:58:10-04:00', '2026-09-07T20:17:05-04:00', 19, 1, 5501,
          'Permethrin', 2.5,
          '["https://cdn.zensched.com/m/.../oak.jpg"]');
  -- trigger: blocks.next_fog_date for Oak Loop → 2026-09-14 (+7)
  -- trigger: fog_visits.technician_id → 1 (Farid)

sqlite_execute:
  INSERT INTO fog_visits (contract_id, block_id, completed_date, amount,
                          zensched_shift_id, zensched_event_id, zensched_worker_id,
                          actual_in, actual_out, duration_minutes, gps_verified, report_dc_id,
                          chemical, gallons, photo_urls)
  VALUES (1, 2, '2026-09-07', 45.00,
          89012, 7302, 701,
          '2026-09-07T20:22:04-04:00', '2026-09-07T20:38:11-04:00', 16, 1, 5502,
          'Permethrin', 2.0,
          '["https://cdn.zensched.com/m/.../canal.jpg"]');
  -- trigger: Canal Court next_fog_date → 2026-09-14

sqlite_execute:
  INSERT INTO fog_visits (contract_id, block_id, completed_date, amount,
                          zensched_shift_id, zensched_event_id, zensched_worker_id,
                          actual_in, actual_out, duration_minutes, gps_verified, report_dc_id,
                          chemical, gallons, photo_urls)
  VALUES (2, 3, '2026-09-10', 80.00,
          89013, 7303, 701,
          '2026-09-10T20:28:02-04:00', '2026-09-10T20:49:40-04:00', 21, 1, 5503,
          'Permethrin', 3.0,
          '["https://cdn.zensched.com/m/.../beach.jpg"]');
  -- trigger: Beach Road next_fog_date → NULL (after_rain)
```

> Recorded 3 fogs, all GPS-verified.
>
> Palm Grove Monday: Oak Loop Permethrin 2.5 gal; Canal Court Permethrin 2.0 gal. Both next due Sep 14.
> Orchid Bay Thursday: Beach Road Permethrin 3.0 gal. After-rain date cleared — say "it rained" when you want it back on the list.

## "Chemical log for last week."

```
sqlite_query: SELECT * FROM chemical_log WHERE fog_date BETWEEN '2026-09-07' AND '2026-09-13';
  → 2026-09-10 | Beach Road  | Orchid Bay Resort | Permethrin | 3.0 | Farid Hassan
    2026-09-07 | Canal Court | Palm Grove HOA    | Permethrin | 2.0 | Farid Hassan
    2026-09-07 | Oak Loop    | Palm Grove HOA    | Permethrin | 2.5 | Farid Hassan
```

> Your copy from the Fog Record — not an official FIFRA or state pesticide log:
>
> | Date | Block | Chemical | Gallons | Crew |
> |---|---|---|---|---|
> | Sep 7 | Oak Loop | Permethrin | 2.5 | Farid Hassan |
> | Sep 7 | Canal Court | Permethrin | 2.0 | Farid Hassan |
> | Sep 10 | Beach Road | Permethrin | 3.0 | Farid Hassan |
>
> Keep whatever FDACS (or your ministry) wants on their form separately.

## "Draft invoices for everyone with uninvoiced work."

```
sqlite_query: SELECT * FROM visits_to_invoice;
  → Orchid Bay Resort | 1 visit |  80.00 | 2026-09-10 .. 2026-09-10
    Palm Grove HOA    | 2 visits | 90.00 | 2026-09-07 .. 2026-09-07

sqlite_execute:
  INSERT INTO invoices (contract_id, invoice_date, due_date, total_amount, line_items)
  SELECT v.contract_id, date('now'),
         date('now', '+' || COALESCE(c.payment_terms_days, 30) || ' days'),
         SUM(v.amount),
         json_group_array(json_object('visit_id', v.visit_id, 'date', v.completed_date,
                                      'block', b.block_name, 'amount', v.amount,
                                      'shift_id', v.zensched_shift_id))
  FROM fog_visits v JOIN blocks b ON b.block_id = v.block_id
  JOIN contracts c ON c.contract_id = v.contract_id
  WHERE v.invoiced = 0 AND v.contract_id = 1 GROUP BY v.contract_id;

sqlite_execute: UPDATE fog_visits SET invoiced = 1 WHERE invoiced = 0 AND contract_id = 1;
sqlite_query:   SELECT invoice_number, invoice_date, due_date, total_amount FROM invoices WHERE invoice_id = last_insert_rowid();
  → INV-2026-0001 | 2026-09-11 | 2026-10-11 | 90.00     (number assigned by trigger)

(same three statements for contract 2 → INV-2026-0002, 80.00)
```

The agent then writes the invoices out as text:

> Here are your two invoices. Paste each into an email or text.
>
> ```
> GulfMist Mosquito
> Invoice INV-2026-0001
> To: Palm Grove HOA (board@palmgrove.example)
> Date: Sep 11, 2026    Due: Oct 11, 2026
>
>   Sep 7    Oak Loop fog                         $45.00
>   Sep 7    Canal Court fog                      $45.00
>
> Total due: $90.00
> Visits GPS-verified on the block.
> ```
>
> ```
> GulfMist Mosquito
> Invoice INV-2026-0002
> To: Orchid Bay Resort (manager@orchidbay.example)
> Date: Sep 11, 2026    Due: Oct 11, 2026
>
>   Sep 10   Beach Road fog                       $80.00
>
> Total due: $80.00
> Visit GPS-verified on the block.
> ```
>
> Say "sent" when they're out and I'll note the date.

## "Sent. Palm Grove already paid."

```
sqlite_execute: UPDATE invoices SET sent_date = date('now') WHERE invoice_number IN ('INV-2026-0001', 'INV-2026-0002');
sqlite_execute: UPDATE invoices SET paid = 1, paid_date = date('now') WHERE invoice_number = 'INV-2026-0001';
```

> Marked both sent and INV-2026-0001 paid. Orchid Bay's $80 (INV-2026-0002) is outstanding, due Oct 11.

## Eight weeks later: "Schedule this week."

```
sqlite_query: SELECT * FROM blocks_due;
  → 2026-11-09 | Oak Loop | weekly | evt 7301 | event_valid_until 2026-11-05 | event_needs_roll 1 | ...

event_create:
  location_id: 9301
  title: "Fog - Oak Loop"
  start_date: "2026-11-09"
  end_date:   "2027-01-07"
  idempotency_key: "event-block-1-20261109"
  → event_id: 7401

form_assign: form_id 501, event_id 7401
sqlite_execute: UPDATE blocks SET zensched_event_id = 7401, event_valid_until = '2027-01-07' WHERE block_id = 1;

shift_create: event_id 7401, worker_id 701, start "2026-11-09T20:00:00-05:00",
              end "2026-11-09T20:20:00-05:00", idempotency_key "shift-block-1-20261109"
```

> Scheduled Oak Loop for Mon Nov 9 20:00. Its ZenSched event was about to expire (Nov 5), so I renewed it through Jan 7. Beach Road has no next date (after-rain) so it is not on this week's list.

## Summary of who stored what

| Thing | Where | Why |
|---|---|---|
| Palm Grove $45 weekly, Orchid Bay $80 after-rain, contacts | SQLite | CRM; ZenSched does not model rates or recurrence |
| Gate code, applicator license | SQLite **only** | Privacy; never sent to ZenSched |
| Each block's GPS location | ZenSched (integer ID in `blocks`) | Needed for geofenced check-in |
| Each block's current ≤60-day event and its end date | ZenSched (integer ID + `event_valid_until` in `blocks`) | Shifts hang off events; renewed by the agent |
| The Fog Record form | ZenSched (ID in `settings`) | Installed on the crew's phone per shift |
| Farid, his invite, his app | ZenSched (integer ID in `technicians`) | Workforce and notifications |
| The week's three shifts | ZenSched only | Live schedule; never copied |
| GPS punches, actual times | ZenSched only | Verified record; queried via `shift_status` / `timesheet_export` |
| Three Fog Records with spray photos | ZenSched (originals); summary + photo URLs in `fog_visits` | Read once (metered), then chemical log / invoices from SQLite |
| Three `fog_visits` rows referencing shift and submission IDs | SQLite | Billing + chemical-log extract |
| Two invoices, one paid | SQLite | Billing |
