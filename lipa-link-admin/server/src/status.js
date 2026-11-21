import { db } from './db.js';

const DAY = 24 * 60 * 60 * 1000;
export const INACTIVE_AFTER_DAYS = 7;
export const BACKUP_LATE_AFTER_DAYS = 2;

const age = (iso) => (iso ? Date.now() - new Date(iso).getTime() : Infinity);

/**
 * État de fraîcheur des données d'un utilisateur, vu par l'administration :
 * - blocked  : compte suspendu ;
 * - never    : jamais synchronisé ;
 * - pending  : le téléphone a des modifications pas encore envoyées ;
 * - inactive : pas de contact depuis plus de 7 jours (on ne peut pas savoir) ;
 * - uptodate : le serveur a exactement les mêmes données que le téléphone.
 */
export function freshness(device) {
  if (device.status === 'blocked') return 'blocked';
  if (!device.last_sync_at) return 'never';
  if (device.local_fingerprint && device.local_fingerprint !== device.sync_fingerprint) return 'pending';
  if (age(device.last_seen_at) > INACTIVE_AFTER_DAYS * DAY) return 'inactive';
  return 'uptodate';
}

/** Sauvegarde auto en retard : vieille de plus de 2 jours ET les données ont changé depuis. */
export function backupLate(device) {
  if (!device.auto_backup || device.status === 'blocked') return false;
  if (age(device.last_backup_at) <= BACKUP_LATE_AFTER_DAYS * DAY) return false;
  return !device.backup_fingerprint || device.backup_fingerprint !== device.local_fingerprint;
}

const BALANCE_SQL = `
  WITH b AS (
    SELECT d.id, d.customerId, d.devise, d.own,
           d.borrowedAmount - COALESCE((SELECT SUM(a.amount) FROM sync_avance a
              WHERE a.device_id = d.device_id AND a.debtId = d.id), 0) AS rest
    FROM sync_debts d WHERE d.device_id = @id
  )
  SELECT
    COALESCE(SUM(CASE WHEN own = 'false' AND devise = 'USD' AND rest > 0.005 THEN rest END), 0) AS theyOweUSD,
    COALESCE(SUM(CASE WHEN own = 'false' AND devise = 'CDF' AND rest > 0.005 THEN rest END), 0) AS theyOweCDF,
    COALESCE(SUM(CASE WHEN own = 'true'  AND devise = 'USD' AND rest > 0.005 THEN rest END), 0) AS iOweUSD,
    COALESCE(SUM(CASE WHEN own = 'true'  AND devise = 'CDF' AND rest > 0.005 THEN rest END), 0) AS iOweCDF,
    COUNT(CASE WHEN rest > 0.005 THEN 1 END) AS openDebts
  FROM b
`;

export function balances(deviceId) {
  return db.prepare(BALANCE_SQL).get({ id: deviceId });
}

const parse = (json, fallback) => {
  try {
    return json ? JSON.parse(json) : fallback;
  } catch {
    return fallback;
  }
};

/** Vue publique d'un appareil (sans secrets). */
export function presentDevice(d, { detailed = false } = {}) {
  const counts = db
    .prepare(
      `SELECT (SELECT COUNT(*) FROM sync_customers WHERE device_id = @id) AS customers,
              (SELECT COUNT(*) FROM sync_debts WHERE device_id = @id) AS debts,
              (SELECT COUNT(*) FROM sync_avance WHERE device_id = @id) AS avance,
              (SELECT COUNT(*) FROM backups WHERE device_id = @id) AS backups,
              (SELECT COALESCE(SUM(size), 0) FROM backups WHERE device_id = @id) AS storage`,
    )
    .get({ id: d.id });

  const out = {
    id: d.id,
    status: d.status,
    freshness: freshness(d),
    backupLate: backupLate(d),
    companyName: d.company_name || 'Sans nom',
    companyInfos: parse(d.company_infos, {}),
    rate: d.rate,
    platform: d.platform,
    deviceModel: d.device_model,
    appVersion: d.app_version,
    autoBackup: !!d.auto_backup,
    autoSync: !!d.auto_sync,
    createdAt: d.created_at,
    lastSeenAt: d.last_seen_at,
    lastSyncAt: d.last_sync_at,
    lastBackupAt: d.last_backup_at,
    localChangedAt: d.local_changed_at,
    localCounts: parse(d.local_counts, null),
    syncedCounts: counts,
  };
  if (detailed) {
    out.balances = balances(d.id);
    out.adminNote = d.admin_note || '';
  }
  return out;
}
