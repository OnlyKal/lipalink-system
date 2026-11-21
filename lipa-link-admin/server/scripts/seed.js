// Crée quelques utilisateurs de démonstration en passant par la vraie API
// (comme le ferait l'application mobile). Serveur démarré requis.
//   npm run seed            → http://localhost:4100
//   API=http://… npm run seed
const API = process.env.API || 'http://localhost:4100';

async function call(method, url, body, token) {
  const res = await fetch(`${API}/api/device${url}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`${url}: ${json.error}`);
  return json;
}

const NAMES = ['Mama Neema', 'Papa Jean', 'Esther K.', 'Grâce M.', 'Patrick B.', 'Furaha', 'Amani S.', 'Josué', 'Riziki', 'Bahati L.'];
const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];

function fakeData(n) {
  const customers = NAMES.slice(0, n).map((fullname, i) => ({ id: i + 1, fullname, phone: `+24399${1000000 + i * 7919}`, email: '' }));
  const debts = [];
  const avance = [];
  for (const c of customers) {
    for (let k = 0; k < 1 + Math.floor(Math.random() * 3); k++) {
      const id = debts.length + 1;
      const devise = pick(['USD', 'CDF']);
      const amount = devise === 'USD' ? 20 + Math.round(Math.random() * 480) : 20000 + Math.round(Math.random() * 400) * 1000;
      const due = new Date(Date.now() + (Math.random() * 40 - 15) * 86400000).toISOString().slice(0, 10);
      debts.push({ id, customerId: c.id, todayDate: new Date().toISOString().slice(0, 10), dueDate: due, borrowedAmount: amount, devise, motif: pick(['Marchandises', 'Prêt', 'Crédit boutique', 'Avance sur salaire']), status: 'pending', own: pick(['false', 'false', 'true']) });
      if (Math.random() > 0.4) avance.push({ id: avance.length + 1, debtId: id, customerId: c.id, amount: Math.round(amount * Math.random() * 0.8), paidDate: new Date().toISOString(), devise, own: 'false' });
    }
  }
  return { customers, debts, avance };
}

const shops = [
  { name: 'BOUTIQUE ESPOIR', city: 'Goma', model: 'Samsung Galaxy A14' },
  { name: 'ÉTS FURAHA', city: 'Bukavu', model: 'Tecno Spark 10' },
  { name: 'PHARMACIE AMANI', city: 'Kinshasa', model: 'iPhone 12' },
  { name: 'QUINCAILLERIE BAHATI', city: 'Lubumbashi', model: 'Infinix Hot 30' },
];

for (const [i, shop] of shops.entries()) {
  const device = { platform: shop.model.startsWith('iPhone') ? 'ios' : 'android', model: shop.model, appVersion: '1.0.0' };
  const company = { name: shop.name, infos: { phone: `+243 99 000 00${i}`, email: '', adresse: shop.city, rccm: '', idnat: '', website: '' } };
  const { id, token, recoveryKey } = await call('POST', '/activate', { device, company, settings: { autoBackup: i !== 2, autoSync: i !== 3 } });
  const data = { ...fakeData(4 + i * 2), company, rate: 2850 };
  const fingerprint = `fp-${id}-1`;
  await call('POST', '/sync', { data, fingerprint, device }, token);
  if (i !== 3) await call('POST', '/backups', { data, fingerprint, kind: 'auto', device }, token);
  if (i === 1) await call('POST', '/heartbeat', { fingerprint: `fp-${id}-2`, counts: { customers: 7, debts: 12, avance: 6 } }, token);
  console.log(`✓ ${id}  ${shop.name}  (clé de récupération ${recoveryKey})`);
}
