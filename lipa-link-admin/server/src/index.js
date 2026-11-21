import cors from 'cors';
import express from 'express';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import './db.js';
import { adminRouter } from './routes/admin.js';
import { deviceRouter } from './routes/device.js';
import { ADMIN_PASSWORD } from './security.js';

const app = express();
app.set('trust proxy', 1);
app.use(cors());
app.use(express.json({ limit: '25mb' }));

app.get('/api/health', (req, res) => res.json({ ok: true, name: 'LipaLink Cloud' }));
app.use('/api/device', deviceRouter);
app.use('/api/admin', adminRouter);

// En production, le serveur sert aussi le dashboard compilé (web/dist).
const dist = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'web', 'dist');
if (fs.existsSync(dist)) {
  app.use(express.static(dist));
  app.get(/^(?!\/api).*/, (req, res) => res.sendFile(path.join(dist, 'index.html')));
}

app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: 'Erreur interne du serveur' });
});

const PORT = Number(process.env.PORT || 4100);
// En production, HOST=127.0.0.1 : seul nginx (HTTPS) est exposé.
const HOST = process.env.HOST;
const onReady = () => {
  console.log(`LipaLink Cloud → http://localhost:${PORT}`);
  if (ADMIN_PASSWORD === 'admin') console.warn('⚠  Mot de passe admin par défaut « admin » : définissez ADMIN_PASSWORD.');
};
const server = HOST ? app.listen(PORT, HOST, onReady) : app.listen(PORT, onReady);
server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`✖ Le port ${PORT} est déjà utilisé par une autre application. Lancez avec un autre port : PORT=4200 npm start`);
  } else {
    console.error(err);
  }
  process.exit(1);
});
