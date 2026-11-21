import { Router } from 'express';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { BACKUP_DIR, db, logEvent } from '../db.js';
import { ADMIN_PASSWORD, issueAdminToken, requireAdmin, safeEqual } from '../security.js';
import { backupLate, freshness, presentDevice } from '../status.js';

export const adminRouter = Router();

adminRouter.post('/login', (req, res) => {
  if (!safeEqual(String(req.body.password || ''), ADMIN_PASSWORD)) {
    return res.status(401).json({ error: 'Mot de passe incorrect' });
  }
  res.json({ token: issueAdminToken() });
});

adminRouter.use(requireAdmin);

const parseCounts = (b) => ({ ...b, counts: JSON.parse(b.counts || '{}') });

// --------------------------------------------------------- Vue d'ensemble

adminRouter.get('/overview', (req, res) => {
  const devices = db.prepare('SELECT * FROM devices').all();
  const byFreshness = { uptodate: 0, pending: 0, inactive: 0, never: 0, blocked: 0 };
  for (const d of devices) byFreshness[freshness(d)]++;

  const dayAgo = new Date(Date.now() - 86400000).toISOString();
  const totals = db
    .prepare(
      `SELECT (SELECT COUNT(*) FROM backups) AS backups,
              (SELECT COALESCE(SUM(size), 0) FROM backups) AS storage,
              (SELECT COUNT(*) FROM sync_customers) AS customers,
              (SELECT COUNT(*) FROM sync_debts) AS debts`,
    )
    .get();

  // Activité des 14 derniers jours (sauvegardes et synchros par jour).
  // Jours calculés en UTC, comme les dates stockées (ISO).
  const since = new Date(Date.now() - 13 * 86400000);
  since.setUTCHours(0, 0, 0, 0);
  const daily = db
    .prepare(
      `SELECT substr(created_at, 1, 10) AS day,
              SUM(type = 'backup') AS backups, SUM(type = 'sync') AS syncs
       FROM events WHERE created_at >= ? GROUP BY day`,
    )
    .all(since.toISOString());
  const byDay = Object.fromEntries(daily.map((d) => [d.day, d]));
  const activity = Array.from({ length: 14 }, (_, i) => {
    const day = new Date(since.getTime() + i * 86400000).toISOString().slice(0, 10);
    return { day, backups: byDay[day]?.backups || 0, syncs: byDay[day]?.syncs || 0 };
  });

  const attention = devices
    .filter((d) => ['pending', 'never', 'inactive'].includes(freshness(d)) || backupLate(d))
    .sort((a, b) => (b.last_seen_at || '').localeCompare(a.last_seen_at || ''))
    .slice(0, 6)
    .map((d) => presentDevice(d));

  const recent = db
    .prepare(
      `SELECT e.*, d.company_name AS companyName FROM events e
       LEFT JOIN devices d ON d.id = e.device_id ORDER BY e.id DESC LIMIT 12`,
    )
    .all();

  res.json({
    users: devices.length,
    activeToday: devices.filter((d) => d.last_seen_at && d.last_seen_at >= dayAgo).length,
    autoBackup: devices.filter((d) => d.auto_backup).length,
    autoSync: devices.filter((d) => d.auto_sync).length,
    byFreshness,
    ...totals,
    activity,
    attention,
    recent,
  });
});

// ------------------------------------------------------------ Utilisateurs

adminRouter.get('/users', (req, res) => {
  const q = String(req.query.q || '').trim().toLowerCase();
  const filter = String(req.query.status || 'all');
  const list = db
    .prepare('SELECT * FROM devices ORDER BY COALESCE(last_seen_at, created_at) DESC')
    .all()
    .map((d) => presentDevice(d))
    .filter((u) => filter === 'all' || u.freshness === filter)
    .filter(
      (u) =>
        !q ||
        u.id.toLowerCase().includes(q) ||
        u.companyName.toLowerCase().includes(q) ||
        Object.values(u.companyInfos || {}).some((v) => String(v).toLowerCase().includes(q)),
    );
  res.json(list);
});

function findDevice(req, res) {
  const d = db.prepare('SELECT * FROM devices WHERE id = ?').get(req.params.id);
  if (!d) res.status(404).json({ error: 'Utilisateur introuvable' });
  return d;
}

adminRouter.get('/users/:id', (req, res) => {
  const d = findDevice(req, res);
  if (d) res.json(presentDevice(d, { detailed: true }));
});

adminRouter.patch('/users/:id', (req, res) => {
  const d = findDevice(req, res);
  if (!d) return;
  if (req.body.status && ['active', 'blocked'].includes(req.body.status) && req.body.status !== d.status) {
    db.prepare('UPDATE devices SET status = ? WHERE id = ?').run(req.body.status, d.id);
    logEvent(d.id, req.body.status === 'blocked' ? 'blocked' : 'unblocked',
      req.body.status === 'blocked' ? 'Compte suspendu par l\'administrateur' : 'Compte réactivé par l\'administrateur');
  }
  if (typeof req.body.adminNote === 'string') {
    db.prepare('UPDATE devices SET admin_note = ? WHERE id = ?').run(req.body.adminNote.slice(0, 2000), d.id);
  }
  res.json(presentDevice(db.prepare('SELECT * FROM devices WHERE id = ?').get(d.id), { detailed: true }));
});

adminRouter.delete('/users/:id', (req, res) => {
  const d = findDevice(req, res);
  if (!d) return;
  for (const b of db.prepare('SELECT file FROM backups WHERE device_id = ?').all(d.id)) {
    fs.rmSync(path.join(BACKUP_DIR, b.file), { force: true });
  }
  db.prepare('DELETE FROM devices WHERE id = ?').run(d.id);
  res.json({ ok: true });
});

/** Clients synchronisés, avec leurs soldes par sens et devise. */
adminRouter.get('/users/:id/customers', (req, res) => {
  const rows = db
    .prepare(
      `WITH b AS (
         SELECT d.customerId, d.devise, d.own,
                d.borrowedAmount - COALESCE((SELECT SUM(a.amount) FROM sync_avance a
                  WHERE a.device_id = d.device_id AND a.debtId = d.id), 0) AS rest
         FROM sync_debts d WHERE d.device_id = @id
       )
       SELECT c.id, c.fullname, c.phone, c.email,
         COALESCE(SUM(CASE WHEN b.own = 'false' AND b.devise = 'USD' AND b.rest > 0.005 THEN b.rest END), 0) AS theyOweUSD,
         COALESCE(SUM(CASE WHEN b.own = 'false' AND b.devise = 'CDF' AND b.rest > 0.005 THEN b.rest END), 0) AS theyOweCDF,
         COALESCE(SUM(CASE WHEN b.own = 'true'  AND b.devise = 'USD' AND b.rest > 0.005 THEN b.rest END), 0) AS iOweUSD,
         COALESCE(SUM(CASE WHEN b.own = 'true'  AND b.devise = 'CDF' AND b.rest > 0.005 THEN b.rest END), 0) AS iOweCDF,
         COUNT(b.customerId) AS debts
       FROM sync_customers c
       LEFT JOIN b ON b.customerId = c.id
       WHERE c.device_id = @id
       GROUP BY c.id ORDER BY c.fullname COLLATE NOCASE`,
    )
    .all({ id: req.params.id });
  res.json(rows);
});

adminRouter.get('/users/:id/debts', (req, res) => {
  const rows = db
    .prepare(
      `SELECT d.*, c.fullname,
              COALESCE((SELECT SUM(a.amount) FROM sync_avance a WHERE a.device_id = d.device_id AND a.debtId = d.id), 0) AS paid,
              (SELECT COUNT(*) FROM sync_avance a WHERE a.device_id = d.device_id AND a.debtId = d.id) AS payments
       FROM sync_debts d
       LEFT JOIN sync_customers c ON c.device_id = d.device_id AND c.id = d.customerId
       WHERE d.device_id = ? ORDER BY d.id DESC`,
    )
    .all(req.params.id)
    .map((d) => ({ ...d, rest: d.borrowedAmount - d.paid }));
  res.json(rows);
});

adminRouter.get('/users/:id/backups', (req, res) => {
  res.json(
    db
      .prepare('SELECT id, kind, size, counts, created_at AS createdAt FROM backups WHERE device_id = ? ORDER BY id DESC')
      .all(req.params.id)
      .map(parseCounts),
  );
});

adminRouter.get('/users/:id/events', (req, res) => {
  res.json(
    db.prepare('SELECT * FROM events WHERE device_id = ? ORDER BY id DESC LIMIT 200').all(req.params.id),
  );
});

// --------------------------------------------------------------- Sauvegardes

adminRouter.get('/backups', (req, res) => {
  res.json(
    db
      .prepare(
        `SELECT b.id, b.device_id AS deviceId, b.kind, b.size, b.counts, b.created_at AS createdAt,
                d.company_name AS companyName
         FROM backups b JOIN devices d ON d.id = b.device_id
         ORDER BY b.id DESC LIMIT 500`,
      )
      .all()
      .map(parseCounts),
  );
});

adminRouter.get('/backups/:id/download', (req, res) => {
  const b = db.prepare('SELECT * FROM backups WHERE id = ?').get(req.params.id);
  if (!b) return res.status(404).json({ error: 'Sauvegarde introuvable' });
  const json = zlib.gunzipSync(fs.readFileSync(path.join(BACKUP_DIR, b.file)));
  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Content-Disposition', `attachment; filename="${b.device_id}-${b.created_at.slice(0, 10)}-${b.id}.json"`);
  res.send(json);
});

adminRouter.delete('/backups/:id', (req, res) => {
  const b = db.prepare('SELECT * FROM backups WHERE id = ?').get(req.params.id);
  if (!b) return res.status(404).json({ error: 'Sauvegarde introuvable' });
  fs.rmSync(path.join(BACKUP_DIR, b.file), { force: true });
  db.prepare('DELETE FROM backups WHERE id = ?').run(b.id);
  const last = db.prepare('SELECT MAX(created_at) AS at FROM backups WHERE device_id = ?').get(b.device_id);
  db.prepare('UPDATE devices SET last_backup_at = ? WHERE id = ?').run(last.at, b.device_id);
  res.json({ ok: true });
});
