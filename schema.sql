-- ZenSched Mosquito-Fogging Local Database Schema
-- SQLite database for contracts, fog blocks (places), cadence, fog-visit
-- summaries, a local chemical extract, and billing.
-- DO NOT duplicate live schedule data from ZenSched (shifts, punches, timesheets).
--
-- HOW TO LOAD THIS FILE
--   Normal path: paste this whole file into your AI chat and say
--   "Create these tables in my mosquito database. Run each statement one at a time."
--   The AI runs each statement through the SQLite MCP tool (sqlite_execute).
--   Most SQLite MCP tools accept ONE statement per call, so every statement
--   below ends with a semicolon and stands alone.
--
--   Alternative (if you have the sqlite3 command-line tool):
--     sqlite3 mosquito.db < schema.sql
--
-- Every statement is idempotent (IF NOT EXISTS / INSERT OR IGNORE), so it is
-- safe to run this file again on an existing database.
--
-- NOT AN OFFICIAL FIFRA / PESTICIDE LOG. chemical_log is the owner's local
-- extract from the Fog Record (date, block, chemical, gallons, crew). It is
-- not a FIFRA Section 7 / 7 CFR 110 applicator report, not an EPA log, and
-- not a state department-of-agriculture use record. Licensed applicators
-- still keep whatever their state or country requires, on their own forms.
--
-- DATA MODEL
--   contracts → blocks (places) → fog_visits.
--   Each block is one ZenSched LOCATION (permanent). Events roll every
--   <=60 days (ZenSched cap). Look up the block before geocoding.
--
-- PRIVACY: blocks.access_notes (gate codes, residents-only streets, dogs)
-- and technicians.license_no live ONLY in this file on your computer.
-- They are never sent to ZenSched. SKILL.md forbids the agent from putting
-- them in any ZenSched notes field.

-- Foreign keys are OFF by default in SQLite. This must be run once per
-- connection for ON DELETE CASCADE to work. SKILL.md tells the agent to run it
-- at the start of each session.
PRAGMA foreign_keys = ON;

-- Settings: small key/value store so the agent does not have to be re-told the
-- basics every session (timezone, default crew, business name, form id).
-- default_checkin_radius_m is informational: the radius ZenSched enforces is
-- the account POLICY's, set with policy_update(0, {"checkin_radius_m": N}).
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT
);

INSERT OR IGNORE INTO settings (key, value) VALUES ('business_name', 'My Mosquito Fogging Co');
INSERT OR IGNORE INTO settings (key, value) VALUES ('timezone_offset', '-05:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_worker_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_shift_start', '20:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_shift_minutes', '20');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_due_days', '30');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_prefix', 'INV');
INSERT OR IGNORE INTO settings (key, value) VALUES ('fog_record_form_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('event_window_days', '60');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_checkin_radius_m', '200');

-- Contracts: who hires you and who pays you. A city / vector-control
-- department, an HOA, a resort, or a private neighborhood. per_block_fee
-- is the default $ per fogged block; a block can override it.
-- contact_name is LOCAL ONLY.
CREATE TABLE IF NOT EXISTS contracts (
  contract_id INTEGER PRIMARY KEY AUTOINCREMENT,
  contract_name TEXT NOT NULL,
  contract_type TEXT NOT NULL DEFAULT 'hoa'
    CHECK (contract_type IN ('municipal', 'hoa', 'resort', 'private', 'other')),
  contact_name TEXT,                                -- LOCAL ONLY: AP / board / site contact
  contact_email TEXT,
  contact_phone TEXT,
  billing_email TEXT,
  payment_terms_days INTEGER NOT NULL DEFAULT 30,   -- net 30; cash = 0
  per_block_fee REAL,                               -- default $ per completed fog visit
  billing_notes TEXT,
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Blocks: the places you fog. One row = one street block / zone / loop.
-- Each block is one ZenSched LOCATION, created once and kept forever.
-- One ZenSched EVENT per block per rolling window of at most 60 days
-- (ZenSched caps event length). zensched_event_id is the CURRENT event and
-- event_valid_until is its last valid date. When a visit date is later than
-- event_valid_until, the agent creates a new event and updates both columns.
-- Cadence lives here so one municipal contract can fog Zone A Monday and
-- Zone B Wednesday.
-- place_label is the ONLY name sent to ZenSched. access_notes is LOCAL ONLY.
CREATE TABLE IF NOT EXISTS blocks (
  block_id INTEGER PRIMARY KEY AUTOINCREMENT,
  contract_id INTEGER NOT NULL,
  block_name TEXT NOT NULL,                         -- 'Oak Loop', 'Jalan Melati A'
  address TEXT NOT NULL,                            -- pin: mid-block or a corner
  city TEXT,
  state TEXT,
  zip TEXT,
  place_label TEXT,                                 -- sent to ZenSched: 'Block - Oak Loop'
  access_notes TEXT,                                -- LOCAL ONLY: gate, residents-only, dogs
  acreage REAL,
  service_rate REAL,                                -- NULL = contracts.per_block_fee
  service_frequency TEXT NOT NULL
    CHECK (service_frequency IN ('weekly', 'biweekly', 'monthly', 'after_rain', 'on-demand')),
  next_fog_date TEXT,                               -- ISO date: '2026-09-07'
  last_fog_date TEXT,                               -- set automatically when a visit is recorded
  preferred_start TEXT                              -- 'HH:MM' 24-hour local; NULL = settings.default_shift_start
    CHECK (preferred_start IS NULL OR preferred_start GLOB '[0-2][0-9]:[0-5][0-9]'),
  zensched_worker_id INTEGER,                       -- preferred crew; NULL = settings.default_worker_id
  zensched_location_id INTEGER,                     -- from location_create (permanent)
  zensched_event_id INTEGER,                        -- from event_create (current <=60-day window)
  event_valid_until TEXT,                           -- ISO date: last day the current event covers
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (contract_id) REFERENCES contracts(contract_id) ON DELETE CASCADE
);

-- Technicians: your fog-truck roster. zensched_worker_id comes from worker_invite.
-- license_no is LOCAL ONLY (state / ministry applicator number) and never
-- sent to ZenSched.
CREATE TABLE IF NOT EXISTS technicians (
  technician_id INTEGER PRIMARY KEY AUTOINCREMENT,
  technician_name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  zensched_worker_id INTEGER UNIQUE,                -- from worker_invite
  license_no TEXT,                                  -- LOCAL ONLY
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Fog visits: one row per COMPLETED fog of a block, linked to the ZenSched
-- shift and the Fog Record form submission. This is the billing record plus
-- a small summary so chemical_log is a local query.
-- chemical is CHECK-constrained to the Fog Record option labels.
CREATE TABLE IF NOT EXISTS fog_visits (
  visit_id INTEGER PRIMARY KEY AUTOINCREMENT,
  contract_id INTEGER NOT NULL,
  block_id INTEGER NOT NULL,
  technician_id INTEGER,                            -- local roster row (trigger fills from worker id)
  completed_date TEXT NOT NULL,                     -- ISO date: '2026-09-07'
  amount REAL,                                      -- NULL -> block rate or contract per_block_fee (trigger)
  zensched_shift_id INTEGER UNIQUE,                 -- prevents recording the same shift twice
  zensched_event_id INTEGER,
  zensched_worker_id INTEGER,
  actual_in TEXT,                                   -- from shift_status / timesheet_export
  actual_out TEXT,
  duration_minutes INTEGER,
  gps_verified INTEGER,                             -- 1 if the check-in punch was on site
  report_dc_id INTEGER,                             -- Fog Record submission_id
  chemical TEXT CHECK (chemical IS NULL OR chemical IN ('Permethrin', 'Malathion', 'Naled', 'Pyrethrin', 'Deltamethrin', 'None')),
  gallons REAL,                                     -- as the crew typed on the Fog Record
  photo_urls TEXT,                                  -- JSON array of media URLs from the report
  notes TEXT,
  invoiced INTEGER DEFAULT 0,                       -- 1 = included in an invoice
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (contract_id) REFERENCES contracts(contract_id) ON DELETE CASCADE,
  FOREIGN KEY (block_id) REFERENCES blocks(block_id) ON DELETE CASCADE,
  FOREIGN KEY (technician_id) REFERENCES technicians(technician_id) ON DELETE SET NULL
);

-- Invoices: billing records, one per contract per run.
-- invoice_number is filled in automatically by a trigger if left NULL.
CREATE TABLE IF NOT EXISTS invoices (
  invoice_id INTEGER PRIMARY KEY AUTOINCREMENT,
  contract_id INTEGER NOT NULL,
  invoice_number TEXT UNIQUE,                       -- human-readable: 'INV-2026-0001'
  invoice_date TEXT NOT NULL,
  due_date TEXT,
  total_amount REAL NOT NULL,
  paid INTEGER DEFAULT 0,                           -- 1 = paid, 0 = unpaid
  paid_date TEXT,
  sent_date TEXT,                                   -- when you actually emailed/texted it
  line_items TEXT,                                  -- JSON array of visit references
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (contract_id) REFERENCES contracts(contract_id) ON DELETE CASCADE
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_contracts_active ON contracts(is_active);
CREATE INDEX IF NOT EXISTS idx_blocks_contract ON blocks(contract_id, is_active);
CREATE INDEX IF NOT EXISTS idx_blocks_next_fog ON blocks(next_fog_date, is_active);
CREATE INDEX IF NOT EXISTS idx_blocks_zensched_location ON blocks(zensched_location_id);
CREATE INDEX IF NOT EXISTS idx_blocks_zensched_event ON blocks(zensched_event_id);
CREATE INDEX IF NOT EXISTS idx_technicians_worker ON technicians(zensched_worker_id);
CREATE INDEX IF NOT EXISTS idx_fog_visits_contract ON fog_visits(contract_id, completed_date);
CREATE INDEX IF NOT EXISTS idx_fog_visits_block ON fog_visits(block_id, completed_date);
CREATE INDEX IF NOT EXISTS idx_fog_visits_invoiced ON fog_visits(invoiced);
CREATE INDEX IF NOT EXISTS idx_invoices_contract ON invoices(contract_id);
CREATE INDEX IF NOT EXISTS idx_invoices_paid ON invoices(paid);

-- Keep updated_at current
CREATE TRIGGER IF NOT EXISTS update_contract_timestamp
AFTER UPDATE ON contracts
BEGIN
  UPDATE contracts SET updated_at = datetime('now') WHERE contract_id = NEW.contract_id;
END;

CREATE TRIGGER IF NOT EXISTS update_block_timestamp
AFTER UPDATE ON blocks
BEGIN
  UPDATE blocks SET updated_at = datetime('now') WHERE block_id = NEW.block_id;
END;

CREATE TRIGGER IF NOT EXISTS update_technician_timestamp
AFTER UPDATE ON technicians
BEGIN
  UPDATE technicians SET updated_at = datetime('now') WHERE technician_id = NEW.technician_id;
END;

-- Fill technician_id from the roster when the agent only has the ZenSched worker id.
CREATE TRIGGER IF NOT EXISTS fill_visit_technician
AFTER INSERT ON fog_visits
WHEN NEW.technician_id IS NULL AND NEW.zensched_worker_id IS NOT NULL
BEGIN
  UPDATE fog_visits
  SET technician_id = (SELECT technician_id FROM technicians WHERE zensched_worker_id = NEW.zensched_worker_id)
  WHERE visit_id = NEW.visit_id;
END;

-- Snapshot the fee when the agent leaves amount NULL: block override, then
-- the contract's per_block_fee, then 0.
CREATE TRIGGER IF NOT EXISTS fill_visit_amount
AFTER INSERT ON fog_visits
WHEN NEW.amount IS NULL
BEGIN
  UPDATE fog_visits
  SET amount = COALESCE(
        (SELECT service_rate FROM blocks WHERE block_id = NEW.block_id),
        (SELECT per_block_fee FROM contracts WHERE contract_id = NEW.contract_id),
        0)
  WHERE visit_id = NEW.visit_id;
END;

-- Recording a completed fog visit automatically advances the block's cadence.
-- after_rain and on-demand clear the next date (the owner sets the next night).
-- The agent should NOT hand-maintain next_fog_date after this.
CREATE TRIGGER IF NOT EXISTS advance_fog_date_on_visit
AFTER INSERT ON fog_visits
BEGIN
  UPDATE blocks
  SET last_fog_date = NEW.completed_date,
      next_fog_date = CASE service_frequency
        WHEN 'weekly'    THEN date(NEW.completed_date, '+7 days')
        WHEN 'biweekly'  THEN date(NEW.completed_date, '+14 days')
        WHEN 'monthly'   THEN date(NEW.completed_date, '+1 month')
        ELSE NULL                                    -- after_rain / on-demand
      END
  WHERE block_id = NEW.block_id;
END;

-- Auto-number invoices: INV-2026-0001, INV-2026-0002, ...
CREATE TRIGGER IF NOT EXISTS number_invoice
AFTER INSERT ON invoices
WHEN NEW.invoice_number IS NULL
BEGIN
  UPDATE invoices
  SET invoice_number = (SELECT COALESCE(value, 'INV') FROM settings WHERE key = 'invoice_prefix')
                       || '-' || strftime('%Y', NEW.invoice_date)
                       || '-' || printf('%04d', NEW.invoice_id)
  WHERE invoice_id = NEW.invoice_id;
END;

-- Who is due in the next 7 days (today + 6). The agent's weekly scheduling
-- query. One row = one shift_create call. Columns ending in _iso are ready
-- to pass as shift_create start/end; idempotency_key is ready too.
-- event_needs_roll = 1 means create a new ZenSched event first (see SKILL.md).
-- access_notes is included so the agent can tell the owner to pass it to the
-- crew; it must never go into a ZenSched field.
CREATE VIEW IF NOT EXISTS blocks_due AS
SELECT
  b.block_id,
  b.block_name,
  b.address,
  b.city,
  b.state,
  b.zip,
  b.place_label,
  b.access_notes,
  b.acreage,
  b.service_frequency,
  b.next_fog_date,
  COALESCE(b.service_rate, c.per_block_fee, 0) AS amount,
  COALESCE(b.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start')) AS start_time,
  COALESCE(CAST((SELECT value FROM settings WHERE key = 'default_shift_minutes') AS INTEGER), 20) AS default_minutes,
  b.zensched_location_id,
  b.zensched_event_id,
  b.event_valid_until,
  CASE WHEN b.event_valid_until IS NULL OR b.event_valid_until < b.next_fog_date THEN 1 ELSE 0 END AS event_needs_roll,
  c.contract_id,
  c.contract_name,
  c.contract_type,
  COALESCE(b.zensched_worker_id, (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_worker_id')) AS worker_id,
  (SELECT t.technician_name FROM technicians t
    WHERE t.zensched_worker_id = COALESCE(b.zensched_worker_id,
           (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_worker_id'))) AS technician_name,
  b.next_fog_date || 'T'
    || COALESCE(b.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start'))
    || ':00' || (SELECT value FROM settings WHERE key = 'timezone_offset') AS start_iso,
  strftime('%Y-%m-%dT%H:%M:%S', datetime(
      b.next_fog_date || ' '
      || COALESCE(b.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start'))
      || ':00',
      '+' || COALESCE(CAST((SELECT value FROM settings WHERE key = 'default_shift_minutes') AS INTEGER), 20) || ' minutes'))
    || (SELECT value FROM settings WHERE key = 'timezone_offset') AS end_iso,
  'shift-block-' || b.block_id || '-' || strftime('%Y%m%d', b.next_fog_date) AS idempotency_key
FROM blocks b
JOIN contracts c ON c.contract_id = b.contract_id AND c.is_active = 1
WHERE b.is_active = 1
  AND b.next_fog_date IS NOT NULL
  AND b.next_fog_date <= date('now', '+7 days')
ORDER BY b.next_fog_date, COALESCE(b.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start')), b.block_name;

-- Blocks whose current ZenSched event expires within 14 days (or has none)
-- and that belong to an active contract. Roll these proactively.
CREATE VIEW IF NOT EXISTS events_expiring AS
SELECT
  b.block_id,
  b.block_name,
  c.contract_name,
  b.address,
  b.zensched_location_id,
  b.zensched_event_id,
  b.event_valid_until
FROM blocks b
JOIN contracts c ON c.contract_id = b.contract_id AND c.is_active = 1
WHERE b.is_active = 1
  AND (b.event_valid_until IS NULL OR b.event_valid_until <= date('now', '+14 days'))
ORDER BY b.event_valid_until;

-- Completed fogs that have not been invoiced yet, grouped by contract.
CREATE VIEW IF NOT EXISTS visits_to_invoice AS
SELECT
  c.contract_id,
  c.contract_name,
  c.billing_email,
  c.billing_notes,
  c.payment_terms_days,
  COUNT(v.visit_id)       AS visit_count,
  SUM(v.amount)           AS total_amount,
  MIN(v.completed_date)   AS first_visit_date,
  MAX(v.completed_date)   AS last_visit_date
FROM fog_visits v
JOIN contracts c ON c.contract_id = v.contract_id
WHERE v.invoiced = 0
GROUP BY c.contract_id
ORDER BY c.contract_name;

-- Unpaid invoices, oldest first.
CREATE VIEW IF NOT EXISTS invoices_outstanding AS
SELECT
  i.invoice_id,
  i.invoice_number,
  c.contract_name,
  c.billing_email,
  i.invoice_date,
  i.due_date,
  i.total_amount,
  i.sent_date,
  CASE WHEN i.due_date < date('now') THEN 1 ELSE 0 END AS overdue
FROM invoices i
JOIN contracts c ON c.contract_id = i.contract_id
WHERE i.paid = 0
ORDER BY i.due_date;

-- Owner's local chemical extract: one row per treated fog visit.
-- This is the owner's copy, not a FIFRA / 7 CFR 110 form and not a
-- state pesticide-use report. Visits where the crew marked chemical
-- "None" or gallons is 0 / NULL are omitted.
CREATE VIEW IF NOT EXISTS chemical_log AS
SELECT
  v.visit_id,
  v.completed_date                               AS fog_date,
  b.block_name,
  b.address,
  b.city,
  b.state,
  c.contract_name,
  v.chemical,
  v.gallons,
  COALESCE(t.technician_name, 'crew ' || v.zensched_worker_id) AS technician,
  v.notes,
  v.zensched_shift_id,
  v.report_dc_id
FROM fog_visits v
JOIN blocks b ON b.block_id = v.block_id
JOIN contracts c ON c.contract_id = v.contract_id
LEFT JOIN technicians t ON t.technician_id = v.technician_id
WHERE v.chemical IS NOT NULL
  AND v.chemical != 'None'
  AND v.gallons IS NOT NULL
  AND v.gallons > 0
ORDER BY v.completed_date DESC, b.block_name;
