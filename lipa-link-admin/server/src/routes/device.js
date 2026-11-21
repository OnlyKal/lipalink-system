import { Router } from 'express';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { BACKUP_DIR, db, logEvent, now } from '../db.js';
import {
  newDeviceId,
  newRecoveryKey,
  newToken,
  normalizeRecoveryKey,
  requireDevice,
  safeEqual,
  sha256,
} from '../security.js';

export const deviceRouter = Router();

const str = (v, max = 200) => (v == null ? null : String(v).slice(0, max));
const num = (v) => (v == null || v === '' || Number.isNaN(Number(v)) ? null : Number(v));

/** Met à jour ce que l'on sait du téléphone (infos, entreprise, empreinte locale). */
function touch(deviceId, body = {}) {
  const d = db.prepare('SELECT * FROM devices WHERE id = ?').get(deviceId);
  const fields = { last_seen_at: now() };
  const info = body.device || {};
  if (info.platform) fields.platform = str(info.platform, 40);
  if (info.model) fields.device_model = str(info.model, 80);
  if (info.appVersion) fields.app_version = str(info.appVersion, 40);
  if (body.company?.name) fields.company_name = str(body.company.name, 120);
  if (body.company?.infos) fields.company_infos = JSON.stringify(body.company.infos).slice(0, 4000);
  if (num(body.rate) != null) fields.rate = num(body.rate);
  if (body.counts) fields.local_counts = JSON.stringify(body.counts);
  if (body.fingerprint) {
    fields.local_fingerprint = str(body.fingerprint, 64);
    if (body.fingerprint !== d.local_fingerprint) fields.local_changed_at = now();
  }
  const keys = Object.keys(fields);
  db.prepare(`UPDATE devices SET ${keys.map((k) => `${k} = @${k}`).join(', ')} WHERE id = @id`).run({
    ...fields,
    id: deviceId,
  });
}

function settingsOf(d) {
  return { autoBackup: !!d.auto_backup, autoSync: !!d.auto_sync };
}

function lastBackup(deviceId) {
  return db
    .prepare('SELECT id, kind, size, counts, created_at AS createdAt FROM backups WHERE device_id = ? ORDER BY id DESC LIMIT 1')
    .get(deviceId);
}

// ------------------------------------------------------ Activation

/** Première activation : le serveur attribue un identifiant XXXXXLIVIA. */
deviceRouter.post('/activate', (req, res) => {
  const id = newDeviceId();
  const token = newToken();
  const recoveryKey = newRecoveryKey();
  const autoBackup = req.body.settings?.autoBackup ?? true;
  const autoSync = req.body.settings?.autoSync ?? true;
  db.prepare(
    `INSERT INTO devices (id, token_hash, recovery_hash, created_at, auto_backup, auto_sync)
     VALUES (?, ?, ?, ?, ?, ?)`,
  ).run(id, sha256(token), sha256(recoveryKey), now(), autoBackup ? 1 : 0, autoSync ? 1 : 0);
  touch(id, req.body);
  logEvent(id, 'activate', 'Sauvegarde en ligne activée');
  res.status(201).json({ id, token, recoveryKey, settings: { autoBackup, autoSync } });
});

/** Reconnexion (nouveau téléphone, réinstallation) avec l'ID et la clé de récupération. */
deviceRouter.post('/login', (req, res) => {
  const id = String(req.body.id || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
  const d = db.prepare('SELECT * FROM devices WHERE id = ?').get(id);
  const key = normalizeRecoveryKey(req.body.recoveryKey);
  if (!d || !safeEqual(d.recovery_hash, sha256(key))) {
    return res.status(401).json({ error: 'Identifiant ou clé de récupération incorrect' });
  }
  if (d.status === 'blocked') return res.status(403).json({ error: 'Compte suspendu par l\'administrateur' });
  const token = newToken();
  db.prepare('UPDATE devices SET token_hash = ? WHERE id = ?').run(sha256(token), id);
  touch(id, req.body);
  logEvent(id, 'login', `Connexion depuis ${req.body.device?.model || 'un appareil'}`);
  res.json({ id, token, settings: settingsOf(d), lastBackup: lastBackup(id) || null });
});

// ------------------------------------------------- Routes protégées

deviceRouter.use(requireDevice);

deviceRouter.get('/me', (req, res) => {
  const d = req.device;
  res.json({
    id: d.id,
    settings: settingsOf(d),
    lastSyncAt: d.last_sync_at,
    lastBackupAt: d.last_backup_at,
    lastBackup: lastBackup(d.id) || null,
  });
});

/** Contact régulier : le téléphone annonce l'empreinte de ses données. */
deviceRouter.post('/heartbeat', (req, res) => {
  touch(req.device.id, req.body);
  const d = db.prepare('SELECT * FROM devices WHERE id = ?').get(req.device.id);
  res.json({
    settings: settingsOf(d),
    upToDate: !!d.sync_fingerprint && d.sync_fingerprint === d.local_fingerprint,
    lastSyncAt: d.last_sync_at,
    lastBackupAt: d.last_backup_at,
  });
});

deviceRouter.put('/settings', (req, res) => {
  const d = req.device;
  const autoBackup = req.body.autoBackup ?? !!d.auto_backup;
  const autoSync = req.body.autoSync ?? !!d.auto_sync;
  db.prepare('UPDATE devices SET auto_backup = ?, auto_sync = ?, last_seen_at = ? WHERE id = ?').run(
    autoBackup ? 1 : 0,
    autoSync ? 1 : 0,
    now(),
    d.id,
  );
  const parts = [];
  if (autoBackup !== !!d.auto_backup) parts.push(`sauvegarde ${autoBackup ? 'automatique' : 'manuelle'}`);
  if (autoSync !== !!d.auto_sync) parts.push(`synchronisation ${autoSync ? 'automatique' : 'manuelle'}`);
  if (parts.length) logEvent(d.id, 'settings', `Passage en ${parts.join(' et ')}`);
  res.json({ settings: { autoBackup, autoSync } });
});

// ------------------------------------------------- Synchronisation

const rows = (v) => (Array.isArray(v) ? v : []);

/** Remplace la copie serveur des données du téléphone. */
deviceRouter.post('/sync', (req, res) => {
  const id = req.device.id;
  const { data = {}, fingerprint } = req.body;
  const customers = rows(data.customers);
  const debts = rows(data.debts);
  const avance = rows(data.avance);

  db.transaction(() => {
    for (const t of ['sync_customers', 'sync_debts', 'sync_avance']) {
      db.prepare(`DELETE FROM ${t} WHERE device_id = ?`).run(id);
    }
    const insC = db.prepare('INSERT INTO sync_customers VALUES (?, ?, ?, ?, ?)');
    for (const c of customers) insC.run(id, c.id, str(c.fullname), str(c.phone), str(c.email));
    const insD = db.prepare('INSERT INTO sync_debts VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
    for (const d of debts) {
      insD.run(id, d.id, d.customerId, str(d.todayDate), str(d.dueDate), num(d.borrowedAmount) ?? 0,
        str(d.devise, 8), str(d.motif, 500), str(d.status, 20), str(d.own, 8));
    }
    const insA = db.prepare('INSERT INTO sync_avance VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
    for (const a of avance) {
      insA.run(id, a.id, a.debtId, a.customerId, num(a.amount) ?? 0, str(a.paidDate), str(a.devise, 8), str(a.own, 8));
    }
    db.prepare('UPDATE devices SET last_sync_at = ?, sync_fingerprint = ? WHERE id = ?').run(now(), str(fingerprint, 64), id);
    touch(id, {
      ...req.body,
      rate: data.rate,
      company: data.company,
      counts: { customers: customers.length, debts: debts.length, avance: avance.length },
    });
  })();

  logEvent(id, 'sync', `${customers.length} clients · ${debts.length} dettes · ${avance.length} paiements`);
  res.json({ ok: true, syncedAt: now() });
});

// ------------------------------------------------------- Sauvegardes

const KEEP_BACKUPS = 30;

deviceRouter.post('/backups', (req, res) => {
  const id = req.device.id;
  const kind = req.body.kind === 'auto' ? 'auto' : 'manual';
  const data = req.body.data || {};
  const counts = {
    customers: rows(data.customers).length,
    debts: rows(data.debts).length,
    avance: rows(data.avance).length,
  };
  const gz = zlib.gzipSync(JSON.stringify(data));
  const file = `${id}-${Date.now()}.json.gz`;
  fs.writeFileSync(path.join(BACKUP_DIR, file), gz);
  const createdAt = now();
  const info = db
    .prepare('INSERT INTO backups (device_id, kind, file, size, fingerprint, counts, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)')
    .run(id, kind, file, gz.length, str(req.body.fingerprint, 64), JSON.stringify(counts), createdAt);
  db.prepare('UPDATE devices SET last_backup_at = ?, backup_fingerprint = ? WHERE id = ?').run(
    createdAt, str(req.body.fingerprint, 64), id,
  );
  touch(id, { ...req.body, counts });

  // On garde les 30 dernières sauvegardes par utilisateur.
  const old = db.prepare('SELECT id, file FROM backups WHERE device_id = ? ORDER BY id DESC LIMIT -1 OFFSET ?').all(id, KEEP_BACKUPS);
  for (const b of old) {
    fs.rmSync(path.join(BACKUP_DIR, b.file), { force: true });
    db.prepare('DELETE FROM backups WHERE id = ?').run(b.id);
  }

  logEvent(id, 'backup', `Sauvegarde ${kind === 'auto' ? 'automatique' : 'manuelle'} · ${counts.customers} clients`);
  res.status(201).json({ id: info.lastInsertRowid, kind, size: gz.length, counts, createdAt });
});

deviceRouter.get('/backups', (req, res) => {
  const list = db
    .prepare('SELECT id, kind, size, counts, created_at AS createdAt FROM backups WHERE device_id = ? ORDER BY id DESC')
    .all(req.device.id)
    .map((b) => ({ ...b, counts: JSON.parse(b.counts || '{}') }));
  res.json(list);
});

/** Contenu d'une sauvegarde (pour la restauration sur le téléphone). */
deviceRouter.get('/backups/:backupId', (req, res) => {
  const b = db.prepare('SELECT * FROM backups WHERE id = ? AND device_id = ?').get(req.params.backupId, req.device.id);
  if (!b) return res.status(404).json({ error: 'Sauvegarde introuvable' });
  const data = JSON.parse(zlib.gunzipSync(fs.readFileSync(path.join(BACKUP_DIR, b.file))).toString());
  logEvent(req.device.id, 'restore', `Restauration de la sauvegarde du ${new Date(b.created_at).toLocaleString('fr-FR')}`);
  res.json({ id: b.id, createdAt: b.created_at, data });
});

deviceRouter.post('/disconnect', (req, res) => {
  db.prepare('UPDATE devices SET token_hash = ? WHERE id = ?').run(sha256(newToken()), req.device.id);
  logEvent(req.device.id, 'disconnect', 'Déconnexion du téléphone');
  res.json({ ok: true });
});
