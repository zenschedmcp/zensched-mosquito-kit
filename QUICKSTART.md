# Quickstart

Setup is about 15 minutes, once. After that everything is plain English to your AI. Each step below tells you what to do and, where relevant, exactly what to type to the AI.

You need: Claude Desktop (or Cursor) and [Node.js LTS](https://nodejs.org/) installed. Nothing else.

Before you start, read the "What this kit is not" section of `README.md`. Short version: this is GPS-verified block proof plus a local extract of the Fog Record. It is **not** an official FIFRA / FDACS / Form H chemical log and **not** FieldSeeker ULV.

## 1. Make a data folder

Create a folder such as `C:\Users\YourName\mosquito-ops` (Windows) or `/Users/yourname/mosquito-ops` (Mac). Note the full path.

## 2. Add the two tools to your AI's config

Open the config file:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Cursor:** Settings → MCP → Add new global MCP server

Paste this in and fix only the `SQLITE_PATH` line to match your folder from step 1:

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

- On Windows, double every backslash: `"C:\\Users\\YourName\\mosquito-ops\\mosquito.db"`.
- Leave `zsc_your_key_here` as it is. You get the real key in the next step.

Save, then **fully quit and reopen** the AI app.

## 3. Create your ZenSched account

Type to the AI:

> Call zensched_guide, then account_create with org_name "GulfMist Mosquito". Show me the zsc_ key.

Copy the key into the config file in place of `zsc_your_key_here`. Save. Quit and reopen the app once more. (You can also ask the AI to call `account_use_key` with the key to continue right away, but update the file anyway so it sticks.)

## 4. Create the database tables

Copy the full contents of `schema.sql` and paste it into the chat with this line above it:

> Create these tables in my mosquito database. Run each statement one at a time with the SQLite tool, then list the tables to confirm.

## 5. Give the AI its instructions

Paste `SKILL.md` into the AI as standing instructions (Claude Desktop: a Project's instructions; Cursor: a rule). Then:

> My business is GulfMist Mosquito in Tampa, Florida, Eastern time. Save that to settings and create the Fog Record form.

The AI saves your settings (Tampa in September is `-04:00` EDT; after early November use `-05:00` EST — Florida has DST. SE Asia / Gulf shops leave their offset alone year-round) and calls `form_create` once (free) to build the Fog Record your crew fills in: chemical (select), gallons (number), one spray photo. No signature. Not a FIFRA / FDACS / Form H log and not FieldSeeker ULV. It stores the form id so every block gets it.

Ask it to widen the check-in circle for a truck driving the block:

> Set the check-in radius to 250 m.

That is `policy_update(0, '{"checkin_radius_m": 250}')`, not a per-block setting. Never "on that location".

## 6. Add your first contract and blocks

> Add Palm Grove HOA, board@palmgrove.example, 813-555-0160. Weekly $45 a block starting Monday 2026-09-07 at 20:00. Two blocks: Oak Loop, 1200 Oak Loop, Tampa FL 33609, gate 4412; Canal Court, 80 Canal Court, Tampa FL 33609.

> Add an after-rain fog for Orchid Bay Resort, manager@orchidbay.example, Beach Road, Tampa FL 33615, Thursday 2026-09-10 at 20:30, $80.

Behind the scenes the AI inserts the contracts and blocks, calls `location_create` with a **block-code + street** label (never the HOA or a person; geocode $0.03, may trigger the $5 activation deposit the first time), creates a 60-day `event_create` per block, attaches the Fog Record with `form_assign`, and saves the integer IDs. Gate notes and contract names go only into the local database. You just see a confirmation.

## 7. Invite your crew

> Invite Farid Hassan at farid@example.com as a tech and make him my default.

Farid gets an email ($0.25), installs the app ([Android](https://play.google.com/store/apps/details?id=com.zensched.app) / [iOS TestFlight](https://testflight.apple.com/join/Wp51m5Yq)), and activates. Give him the gate code yourself; the AI will not put it in ZenSched.

## 8. Schedule the week

> Schedule this week for Farid.

The AI reads `blocks_due`, creates one shift per block on ZenSched, and summarizes by night. Farid gets a push notification for each, with the Fog Record attached. It will confirm each block is about $0.35 once he punches and you read the spray photo.

## 9. After the work is done

> Record last night's fogs, show me the chemical log, then draft invoices for anyone with uninvoiced work.

The AI pulls the completed, GPS-verified shifts and the Fog Records from ZenSched (reading records is metered, so it tells you the cost first), saves a per-visit summary, advances Palm Grove to next week and clears Orchid Bay's after-rain date, shows the chemical-log extract (your copy, not a FIFRA / FDACS / Form H form), creates invoice records, and writes out each invoice as text you can paste into an email.

> Palm Grove paid INV-2026-0001.

Marks it paid.

## What next

- `README.md` for the full explanation, the FIFRA / FDACS / Form H / FieldSeeker boundary, troubleshooting table, and developer notes
- `example-workflow.md` to see the exact tool calls behind each step above
