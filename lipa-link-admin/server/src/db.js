import Database from 'better-sqlite3';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

export const DATA_DIR = process.env.DATA_DIR || path.join(here, '..', 'data');
export const BACKUP_DIR = path.join(DATA_DIR, 'backups');
fs.mkdirSync(BACKUP_DIR, { recursive: true });

export const db = new Database(path.join(DATA_DIR, 'lipalink.db'));
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

db.exec(`
  -- Un appareil (= un utilisateur LipaLink) identifié par XXXXXLIVIA.
  CREATE TABLE IF NOT EXISTS devices (
    id              TEXT PRIMARY KEY,
    token_hash      TEXT NOT NULL,
    recovery_hash   TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'active',   -- active | blocked
    company_name    TEXT,
    company_infos   TEXT,                             -- JSON (téléphone, e-mail, adresse…)
    rate            REAL,
    platform        TEXT,
    device_model    TEXT,
    app_version     TEXT,
    auto_backup     INTEGER NOT NULL DEFAULT 1,
    auto_sync       INTEGER NOT NULL DEFAULT 1,
    created_at      TEXT NOT NULL,
    last_seen_at    TEXT,
    last_sync_at    TEXT,
    last_backup_at  TEXT,
    local_fingerprint TEXT,    -- empreinte des données sur le téléphone (dernier contact)
    local_changed_at  TEXT,    -- quand cette empreinte a changé pour la dernière fois
    sync_fingerprint  TEXT,    -- empreinte des données synchronisées sur le serveur
    local_counts    TEXT,      -- JSON {customers, debts, avance}
    admin_note      TEXT
  );

  CREATE TABLE IF NOT EXISTS backups (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id   TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    kind        TEXT NOT NULL,        -- manual | auto
    file        TEXT NOT NULL,
    size        INTEGER NOT NULL,
    fingerprint TEXT,
    counts      TEXT,                 -- JSON
    created_at  TEXT NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_backups_device ON backups(device_id, created_at);

  -- Copie synchronisée des tables du téléphone (remplacée à chaque synchro).
  CREATE TABLE IF NOT EXISTS sync_customers (
    device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    id        INTEGER NOT NULL,
    fullname  TEXT, phone TEXT, email TEXT,
    PRIMARY KEY (device_id, id)
  );
  CREATE TABLE IF NOT EXISTS sync_debts (
    device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    id INTEGER NOT NULL, customerId INTEGER,
    todayDate TEXT, dueDate TEXT, borrowedAmount REAL, devise TEXT,
    motif TEXT, status TEXT, own TEXT,
    PRIMARY KEY (device_id, id)
  );
  CREATE TABLE IF NOT EXISTS sync_avance (
    device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    id INTEGER NOT NULL, debtId INTEGER, customerId INTEGER,
    amount REAL, paidDate TEXT, devise TEXT, own TEXT,
    PRIMARY KEY (device_id, id)
  );

  CREATE TABLE IF NOT EXISTS events (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id  TEXT REFERENCES devices(id) ON DELETE CASCADE,
    type       TEXT NOT NULL,   -- activate | login | sync | backup | restore | settings | disconnect | blocked …
    message    TEXT,
    created_at TEXT NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_events_device ON events(device_id, created_at);
`);

// Migrations légères (colonnes ajoutées après la première version).
const deviceColumns = db.prepare('PRAGMA table_info(devices)').all().map((c) => c.name);
if (!deviceColumns.includes('backup_fingerprint')) {
  db.exec('ALTER TABLE devices ADD COLUMN backup_fingerprint TEXT');
}

export const now = () => new Date().toISOString();

export function logEvent(deviceId, type, message = null) {
  db.prepare('INSERT INTO events (device_id, type, message, created_at) VALUES (?, ?, ?, ?)')
    .run(deviceId, type, message, now());
}
