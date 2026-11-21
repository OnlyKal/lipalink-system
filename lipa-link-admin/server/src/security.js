import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { DATA_DIR, db } from './db.js';

// Lettres et chiffres sans les caractères ambigus (0/O, 1/I/L).
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

function randomCode(length) {
  const bytes = crypto.randomBytes(length);
  let out = '';
  for (let i = 0; i < length; i++) out += ALPHABET[bytes[i] % ALPHABET.length];
  return out;
}

/** Identifiant unique d'un utilisateur : 5 caractères + « LIVIA ». */
export function newDeviceId() {
  const exists = db.prepare('SELECT 1 FROM devices WHERE id = ?');
  for (;;) {
    const id = `${randomCode(5)}LIVIA`;
    if (!exists.get(id)) return id;
  }
}

/** Clé de récupération (pour se reconnecter depuis un autre téléphone). */
export const newRecoveryKey = () => `${randomCode(4)}-${randomCode(4)}`;
export const newToken = () => crypto.randomBytes(32).toString('hex');
export const sha256 = (value) => crypto.createHash('sha256').update(String(value)).digest('hex');

export function normalizeRecoveryKey(key) {
  const clean = String(key || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
  return clean.length === 8 ? `${clean.slice(0, 4)}-${clean.slice(4)}` : clean;
}

export function safeEqual(a, b) {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

// ------------------------------------------------------------- Admin

const secretFile = path.join(DATA_DIR, '.secret');
const SECRET =
  process.env.ADMIN_SECRET ||
  (fs.existsSync(secretFile)
    ? fs.readFileSync(secretFile, 'utf8')
    : (() => {
        const s = crypto.randomBytes(32).toString('hex');
        fs.writeFileSync(secretFile, s, { mode: 0o600 });
        return s;
      })());

export const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'admin';
const ADMIN_TTL_MS = 12 * 60 * 60 * 1000;

const sign = (payload) => crypto.createHmac('sha256', SECRET).update(payload).digest('base64url');

export function issueAdminToken() {
  const payload = Buffer.from(JSON.stringify({ role: 'admin', exp: Date.now() + ADMIN_TTL_MS })).toString('base64url');
  return `${payload}.${sign(payload)}`;
}

export function verifyAdminToken(token) {
  const [payload, signature] = String(token || '').split('.');
  if (!payload || !signature || !safeEqual(sign(payload), signature)) return false;
  try {
    const data = JSON.parse(Buffer.from(payload, 'base64url').toString());
    return data.role === 'admin' && data.exp > Date.now();
  } catch {
    return false;
  }
}

const bearer = (req) => (req.headers.authorization || '').replace(/^Bearer\s+/i, '');

export function requireAdmin(req, res, next) {
  if (verifyAdminToken(bearer(req))) return next();
  res.status(401).json({ error: 'Session administrateur expirée' });
}

export function requireDevice(req, res, next) {
  const token = bearer(req);
  const device = token && db.prepare('SELECT * FROM devices WHERE token_hash = ?').get(sha256(token));
  if (!device) return res.status(401).json({ error: 'Appareil non reconnu, reconnectez-vous' });
  if (device.status === 'blocked') return res.status(403).json({ error: 'Compte suspendu par l\'administrateur' });
  req.device = device;
  next();
}
