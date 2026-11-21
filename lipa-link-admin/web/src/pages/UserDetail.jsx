import { AnimatePresence, motion } from 'framer-motion';
import {
  ArrowDownLeft, ArrowUpRight, Ban, Check, CloudUpload, Copy, Download, RefreshCw, ShieldCheck,
  Smartphone, Trash2, X,
} from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { api, download } from '../api';
import { eventOf } from '../components/events';
import {
  AnimatedNumber, Avatar, Empty, FadeIn, FRESHNESS, FreshnessPill, IconBadge, Segmented, Skeleton, StatusPill,
} from '../components/ui';
import { formatAmount, formatBytes, formatDate, formatMoney, prettyId, timeAgo } from '../format';

const TABS = [
  ['infos', 'Informations'],
  ['customers', 'Clients'],
  ['debts', 'Dettes'],
  ['backups', 'Sauvegardes'],
  ['events', 'Activité'],
];

const INFO_LABELS = { phone: 'Téléphone', email: 'E-mail', adresse: 'Adresse', rccm: 'RCCM', idnat: 'N° ID NAT', website: 'Site web' };

export default function UserDetail({ id, onClose, onChanged }) {
  const [user, setUser] = useState(null);
  const [error, setError] = useState('');
  const [tab, setTab] = useState('infos');
  const [toast, setToast] = useState('');

  const load = () => api(`/users/${id}`).then(setUser).catch((e) => setError(e.message));
  useEffect(() => {
    load();
    const t = setInterval(load, 15000);
    const esc = (e) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', esc);
    return () => {
      clearInterval(t);
      window.removeEventListener('keydown', esc);
    };
  }, [id]);

  const notify = (msg) => {
    setToast(msg);
    setTimeout(() => setToast(''), 2200);
  };

  async function patch(body, msg) {
    try {
      setUser(await api(`/users/${id}`, { method: 'PATCH', body }));
      onChanged();
      notify(msg);
    } catch (e) {
      notify(e.message);
    }
  }

  async function remove() {
    if (!confirm(`Supprimer définitivement ${id}, ses données synchronisées et toutes ses sauvegardes ?`)) return;
    await api(`/users/${id}`, { method: 'DELETE' });
    onChanged();
    onClose();
  }

  return (
    <>
      <motion.div className="overlay" onClick={onClose} initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} />
      <motion.aside
        className="drawer"
        initial={{ x: '105%' }}
        animate={{ x: 0 }}
        exit={{ x: '105%' }}
        transition={{ type: 'spring', damping: 30, stiffness: 260 }}
      >
        <button className="btn icon" style={{ position: 'absolute', top: 20, right: 20, zIndex: 2 }} onClick={onClose} title="Fermer (Échap)">
          <X size={20} />
        </button>

        {error ? (
          <Empty title="Utilisateur introuvable" message={error} />
        ) : !user ? (
          <>
            <Skeleton height={180} />
            <Skeleton height={300} style={{ marginTop: 16 }} />
          </>
        ) : (
          <>
            <Hero user={user} onCopy={() => { navigator.clipboard?.writeText(user.id); notify('Identifiant copié'); }} />
            <Freshness user={user} />
            <Balances b={user.balances} />

            <div style={{ margin: '24px 0 16px', overflowX: 'auto' }}>
              <Segmented id="detail" value={tab} onChange={setTab} options={TABS.map(([value, label]) => ({ value, label }))} />
            </div>

            <AnimatePresence mode="wait">
              <motion.div key={tab} initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -8 }} transition={{ duration: 0.25 }}>
                {tab === 'infos' && <Infos user={user} onPatch={patch} onDelete={remove} />}
                {tab === 'customers' && <Customers id={id} />}
                {tab === 'debts' && <Debts id={id} />}
                {tab === 'backups' && <Backups id={id} notify={notify} onChanged={() => { load(); onChanged(); }} />}
                {tab === 'events' && <Events id={id} />}
              </motion.div>
            </AnimatePresence>
          </>
        )}

        <AnimatePresence>
          {toast && (
            <motion.div className="toast" initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: 20 }}>
              <Check size={18} /> {toast}
            </motion.div>
          )}
        </AnimatePresence>
      </motion.aside>
    </>
  );
}

// ------------------------------------------------------------------ En-tête

function Hero({ user, onCopy }) {
  return (
    <FadeIn className="hero glass" style={{ isolation: 'isolate' }}>
      <div style={{ display: 'flex', gap: 18, alignItems: 'center', flexWrap: 'wrap', paddingRight: 48 }}>
        <Avatar name={user.companyName} size={72} />
        <div style={{ flex: 1, minWidth: 200 }}>
          <div style={{ fontSize: 26, fontWeight: 800, letterSpacing: -0.6 }}>{user.companyName}</div>
          <div style={{ display: 'flex', gap: 8, marginTop: 10, flexWrap: 'wrap', alignItems: 'center' }}>
            <button className="id-tag mono" onClick={onCopy} title="Copier l'identifiant" style={{ cursor: 'pointer' }}>
              {prettyId(user.id)} <Copy size={14} />
            </button>
            <FreshnessPill value={user.freshness} />
          </div>
        </div>
      </div>
      <div style={{ display: 'flex', gap: 18, marginTop: 18, flexWrap: 'wrap', fontSize: 14 }} className="muted">
        <span style={{ display: 'inline-flex', gap: 6, alignItems: 'center' }}>
          <Smartphone size={15} />{user.deviceModel || 'Appareil inconnu'} · {user.platform || '—'} · v{user.appVersion || '?'}
        </span>
        <span>Vu {timeAgo(user.lastSeenAt)}</span>
        <span>Inscrit le {formatDate(user.createdAt, false)}</span>
      </div>
    </FadeIn>
  );
}

/** Le serveur a-t-il la dernière version des données du téléphone ? */
function Freshness({ user }) {
  const f = FRESHNESS[user.freshness];
  const local = user.localCounts || {};
  const synced = user.syncedCounts;
  const explain = {
    uptodate: 'Le serveur a exactement les mêmes données que le téléphone.',
    pending: `Le téléphone a été modifié ${timeAgo(user.localChangedAt)} depuis la dernière synchronisation.`,
    inactive: "Le téléphone n'a pas contacté le serveur depuis plus de 7 jours : des modifications peuvent manquer.",
    never: "L'utilisateur a activé le cloud mais n'a encore rien synchronisé.",
    blocked: 'Compte suspendu : le téléphone ne peut plus sauvegarder ni synchroniser.',
  }[user.freshness];

  const rows = [
    ['Clients', local.customers, synced.customers],
    ['Dettes', local.debts, synced.debts],
    ['Paiements', local.avance, synced.avance],
  ];

  return (
    <FadeIn index={1} className="glass card" style={{ marginTop: 16, borderColor: `color-mix(in srgb, ${f.color} 35%, var(--glass-border))` }}>
      <div style={{ display: 'flex', gap: 14, alignItems: 'flex-start' }}>
        <IconBadge icon={user.freshness === 'uptodate' ? Check : RefreshCw} color={f.color} />
        <div style={{ flex: 1 }}>
          <b style={{ fontSize: 16 }}>{f.label}</b>
          <div className="muted" style={{ fontSize: 14, marginTop: 2 }}>{explain}</div>
        </div>
      </div>
      <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(170px, 1fr))', marginTop: 16, gap: 10 }}>
        <div className="info-list" style={{ gridTemplateColumns: '1fr', gap: 10 }}>
          <div><span>Dernière synchro</span><b>{timeAgo(user.lastSyncAt)}</b></div>
          <div><span>Dernière sauvegarde</span><b style={{ color: user.backupLate ? 'var(--warning)' : undefined }}>{timeAgo(user.lastBackupAt)}</b></div>
        </div>
        <table className="data" style={{ gridColumn: 'span 2', minWidth: 260 }}>
          <thead><tr><th /><th className="num">Téléphone</th><th className="num">Serveur</th></tr></thead>
          <tbody>
            {rows.map(([label, l, s]) => (
              <tr key={label}>
                <td>{label}</td>
                <td className="num">{l ?? '—'}</td>
                <td className="num" style={{ color: l != null && l !== s ? 'var(--warning)' : undefined, fontWeight: 700 }}>{s}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </FadeIn>
  );
}

function Balances({ b }) {
  const items = [
    ['Ses clients lui doivent', b.theyOweUSD, 'USD', 'var(--receivable)', ArrowDownLeft],
    ['Ses clients lui doivent', b.theyOweCDF, 'CDF', 'var(--receivable)', ArrowDownLeft],
    ['Il doit à ses clients', b.iOweUSD, 'USD', 'var(--payable)', ArrowUpRight],
    ['Il doit à ses clients', b.iOweCDF, 'CDF', 'var(--payable)', ArrowUpRight],
  ];
  return (
    <div className="grid balance-grid" style={{ marginTop: 16, gap: 12 }}>
      {items.map(([label, v, devise, c, Icon], i) => (
        <FadeIn key={i} index={2 + i} className="balance" style={{ '--c': c }}>
          <div className="label"><Icon size={15} color={c} />{label}</div>
          <div className="amount"><AnimatedNumber value={v} /><small>{devise}</small></div>
        </FadeIn>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------- Onglets

function useList(path) {
  const [rows, setRows] = useState(null);
  const reload = () => api(path).then(setRows).catch(() => setRows([]));
  useEffect(() => { reload(); }, [path]);
  return [rows, reload];
}

function Infos({ user, onPatch, onDelete }) {
  const [note, setNote] = useState(user.adminNote);
  const infos = Object.entries(INFO_LABELS).filter(([k]) => user.companyInfos?.[k]);
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      <div className="info-list">
        <div><span>Identifiant</span><b className="mono">{user.id}</b></div>
        <div><span>Taux du jour</span><b>{user.rate ? `1 USD = ${formatAmount(user.rate)} CDF` : '—'}</b></div>
        <div><span>Sauvegarde</span><b>{user.autoBackup ? 'Automatique' : 'Manuelle'}</b></div>
        <div><span>Synchronisation</span><b>{user.autoSync ? 'Automatique' : 'Manuelle'}</b></div>
        {infos.map(([k, label]) => <div key={k}><span>{label}</span><b>{user.companyInfos[k]}</b></div>)}
        <div><span>Stockage des sauvegardes</span><b>{formatBytes(user.syncedCounts.storage)} · {user.syncedCounts.backups} fichier(s)</b></div>
      </div>

      <div className="glass card">
        <b>Note interne</b>
        <p className="muted" style={{ margin: '2px 0 10px', fontSize: 13 }}>Visible uniquement par l'administration.</p>
        <textarea className="input" rows={3} value={note} onChange={(e) => setNote(e.target.value)} placeholder="Ex. client prioritaire, a changé de téléphone…" />
        <div style={{ marginTop: 10, display: 'flex', justifyContent: 'flex-end' }}>
          <button className="btn sm primary" disabled={note === user.adminNote} onClick={() => onPatch({ adminNote: note }, 'Note enregistrée')}>Enregistrer</button>
        </div>
      </div>

      <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
        {user.status === 'blocked' ? (
          <button className="btn" onClick={() => onPatch({ status: 'active' }, 'Compte réactivé')}><ShieldCheck size={18} />Réactiver le compte</button>
        ) : (
          <button className="btn danger" onClick={() => onPatch({ status: 'blocked' }, 'Compte suspendu')}><Ban size={18} />Suspendre le compte</button>
        )}
        <button className="btn danger" onClick={onDelete}><Trash2 size={18} />Supprimer l'utilisateur</button>
      </div>
    </div>
  );
}

function Customers({ id }) {
  const [rows] = useList(`/users/${id}/customers`);
  const [q, setQ] = useState('');
  const list = useMemo(() => rows?.filter((c) => !q || `${c.fullname} ${c.phone}`.toLowerCase().includes(q.toLowerCase())), [rows, q]);
  if (!rows) return <Skeleton height={240} />;
  if (!rows.length) return <div className="glass"><Empty title="Aucun client synchronisé" /></div>;
  return (
    <div className="glass" style={{ padding: 6 }}>
      <label className="input" style={{ margin: 8 }}>
        <input placeholder={`Rechercher parmi ${rows.length} clients…`} value={q} onChange={(e) => setQ(e.target.value)} />
      </label>
      <div className="row-list">
        {list.map((c) => {
          const owes = [['USD', c.theyOweUSD], ['CDF', c.theyOweCDF]].filter(([, v]) => v > 0);
          const due = [['USD', c.iOweUSD], ['CDF', c.iOweCDF]].filter(([, v]) => v > 0);
          return (
            <div key={c.id} className="row">
              <Avatar name={c.fullname || '?'} size={42} />
              <div className="grow">
                <div className="title">{c.fullname}</div>
                <div className="sub">{c.phone || 'Pas de téléphone'} · {c.debts} dette(s)</div>
              </div>
              <div style={{ textAlign: 'right', fontSize: 14 }}>
                {owes.map(([d, v]) => <div key={d} className="pos tabular">+{formatMoney(v, d)}</div>)}
                {due.map(([d, v]) => <div key={d} className="neg tabular">−{formatMoney(v, d)}</div>)}
                {!owes.length && !due.length && <StatusPill label="Soldé" color="var(--success)" />}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function Debts({ id }) {
  const [rows] = useList(`/users/${id}/debts`);
  if (!rows) return <Skeleton height={240} />;
  if (!rows.length) return <div className="glass"><Empty title="Aucune dette synchronisée" /></div>;
  const today = new Date().toISOString().slice(0, 10);
  return (
    <div className="glass" style={{ overflowX: 'auto' }}>
      <table className="data">
        <thead>
          <tr><th>Client</th><th>Motif</th><th>Échéance</th><th className="num">Montant</th><th className="num">Payé</th><th className="num">Reste</th><th>Statut</th></tr>
        </thead>
        <tbody>
          {rows.map((d) => {
            const settled = d.rest <= 0.005;
            const late = !settled && d.dueDate && d.dueDate.slice(0, 10) < today;
            const pct = d.borrowedAmount ? Math.min(100, (d.paid / d.borrowedAmount) * 100) : 0;
            return (
              <tr key={d.id}>
                <td>
                  <b>{d.fullname || `Client #${d.customerId}`}</b>
                  <div className="muted" style={{ fontSize: 12 }}>{d.own === 'true' ? 'Il doit au client' : 'Le client lui doit'}</div>
                </td>
                <td className="muted">{d.motif || '—'}</td>
                <td>{formatDate(d.dueDate, false)}</td>
                <td className="num">{formatMoney(d.borrowedAmount, d.devise)}</td>
                <td className="num">
                  {formatMoney(d.paid, d.devise)}
                  <div className="progress" style={{ '--c': 'var(--receivable)', height: 5, marginTop: 6 }}><div style={{ width: `${pct}%` }} /></div>
                </td>
                <td className={`num ${d.own === 'true' ? 'neg' : 'pos'}`}>{formatMoney(Math.max(0, d.rest), d.devise)}</td>
                <td>
                  {settled ? <StatusPill label="Réglée" color="var(--success)" /> : late ? <StatusPill label="En retard" color="var(--danger)" /> : <StatusPill label="En cours" color="var(--warning)" />}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function Backups({ id, notify, onChanged }) {
  const [rows, reload] = useList(`/users/${id}/backups`);
  if (!rows) return <Skeleton height={200} />;
  if (!rows.length) return <div className="glass"><Empty title="Aucune sauvegarde" message="L'utilisateur n'a encore envoyé aucune sauvegarde." /></div>;

  async function del(b) {
    if (!confirm(`Supprimer la sauvegarde du ${formatDate(b.createdAt)} ?`)) return;
    await api(`/backups/${b.id}`, { method: 'DELETE' });
    reload();
    onChanged();
    notify('Sauvegarde supprimée');
  }

  return (
    <div className="glass" style={{ padding: 6 }}>
      <div className="row-list">
        {rows.map((b, i) => (
          <div key={b.id} className="row">
            <IconBadge icon={CloudUpload} color={b.kind === 'auto' ? 'var(--glow-b)' : 'var(--primary)'} size={40} />
            <div className="grow">
              <div className="title">
                {formatDate(b.createdAt)} {i === 0 && <StatusPill label="La plus récente" color="var(--success)" />}
              </div>
              <div className="sub">
                {b.kind === 'auto' ? 'Automatique' : 'Manuelle'} · {b.counts.customers} clients · {b.counts.debts} dettes · {b.counts.avance} paiements · {formatBytes(b.size)}
              </div>
            </div>
            <button className="btn sm" onClick={() => download(`/backups/${b.id}/download`)} title="Télécharger (JSON)"><Download size={16} /></button>
            <button className="btn sm danger" onClick={() => del(b)} title="Supprimer"><Trash2 size={16} /></button>
          </div>
        ))}
      </div>
    </div>
  );
}

function Events({ id }) {
  const [rows] = useList(`/users/${id}/events`);
  if (!rows) return <Skeleton height={200} />;
  if (!rows.length) return <div className="glass"><Empty title="Aucune activité" /></div>;
  return (
    <div className="glass card">
      <div className="timeline">
        {rows.map((e) => {
          const ev = eventOf(e.type);
          return (
            <div key={e.id} className="ev" style={{ '--c': ev.color }}>
              <b>{ev.label}</b>
              <small>{e.message} · {formatDate(e.created_at)}</small>
            </div>
          );
        })}
      </div>
    </div>
  );
}
