import { motion } from 'framer-motion';
import { ChevronRight, CloudUpload, RefreshCw, Search, Smartphone } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { api } from '../api';
import { Avatar, Empty, FreshnessPill, Segmented, Skeleton } from '../components/ui';
import { formatBytes, prettyId, timeAgo } from '../format';
import { go } from '../nav';

const FILTERS = [
  ['all', 'Tous'],
  ['uptodate', 'À jour'],
  ['pending', 'En attente'],
  ['never', 'Jamais synchro'],
  ['inactive', 'Inactifs'],
  ['blocked', 'Suspendus'],
];

export default function Users() {
  const [all, setAll] = useState(null);
  const [q, setQ] = useState('');
  const [filter, setFilter] = useState('all');

  useEffect(() => {
    const load = () => api('/users').then(setAll).catch(() => setAll([]));
    load();
    const t = setInterval(load, 20000);
    return () => clearInterval(t);
  }, []);

  const list = useMemo(() => {
    if (!all) return null;
    const s = q.trim().toLowerCase();
    return all
      .filter((u) => filter === 'all' || u.freshness === filter)
      .filter((u) => !s || u.id.toLowerCase().includes(s) || u.companyName.toLowerCase().includes(s) ||
        Object.values(u.companyInfos || {}).some((v) => String(v).toLowerCase().includes(s)));
  }, [all, q, filter]);

  const count = (f) => (all ? (f === 'all' ? all.length : all.filter((u) => u.freshness === f).length) : null);

  return (
    <>
      <header className="topbar" style={{ flexWrap: 'wrap' }}>
        <div className="grow">
          <h1>Utilisateurs</h1>
          <p>Chaque téléphone activé reçoit un identifiant ·LIVIA</p>
        </div>
        <label className="input" style={{ width: 'min(340px, 100%)' }}>
          <Search size={18} />
          <input placeholder="ID, entreprise, téléphone…" value={q} onChange={(e) => setQ(e.target.value)} />
        </label>
      </header>

      <div style={{ marginBottom: 20 }}>
        <Segmented id="users" value={filter} onChange={setFilter} options={FILTERS.map(([value, label]) => ({ value, label, count: count(value) }))} />
      </div>

      {!list ? (
        <Skeleton height={360} />
      ) : list.length === 0 ? (
        <div className="glass"><Empty title="Aucun utilisateur" message={all.length ? 'Aucun résultat pour ces critères.' : "Les utilisateurs apparaissent dès qu'ils activent la sauvegarde dans l'app."} /></div>
      ) : (
        <div className="glass" style={{ overflowX: 'auto' }}>
          <table className="data users-table">
            <thead>
              <tr>
                <th>Utilisateur</th>
                <th>État</th>
                <th className="num">Clients</th>
                <th className="num">Dettes</th>
                <th className="num">Sauvegardes</th>
                <th>Mode</th>
                <th>Appareil</th>
                <th>Dernière synchro</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {list.map((u, i) => (
                <motion.tr
                  layout
                  key={u.id}
                  className="clickable"
                  onClick={() => go(`users/${u.id}`)}
                  initial={{ opacity: 0, y: 12 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.35, delay: Math.min(i, 12) * 0.03, ease: [0.2, 0.8, 0.2, 1] }}
                >
                  <td>
                    <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
                      <Avatar name={u.companyName} size={40} />
                      <div style={{ minWidth: 0 }}>
                        <b style={{ whiteSpace: 'nowrap' }}>{u.companyName}</b>
                        <div className="mono muted" style={{ fontSize: 12, fontWeight: 700 }}>{prettyId(u.id)}</div>
                      </div>
                    </div>
                  </td>
                  <td>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 4, alignItems: 'flex-start' }}>
                      <FreshnessPill value={u.freshness} />
                      {u.backupLate && (
                        <span className="status-pill" style={{ '--c': 'var(--warning)' }}><CloudUpload size={13} />Sauvegarde en retard</span>
                      )}
                    </div>
                  </td>
                  <td className="num"><b>{u.syncedCounts.customers}</b></td>
                  <td className="num"><b>{u.syncedCounts.debts}</b></td>
                  <td className="num">
                    <b>{u.syncedCounts.backups}</b>
                    <div className="muted" style={{ fontSize: 12 }}>{formatBytes(u.syncedCounts.storage)}</div>
                  </td>
                  <td>
                    <div className="chips" style={{ flexWrap: 'nowrap' }}>
                      <span className={`chip${u.autoBackup ? ' on' : ''}`} title={`Sauvegarde ${u.autoBackup ? 'automatique' : 'manuelle'}`}>
                        <CloudUpload size={12} />{u.autoBackup ? 'Auto' : 'Manuel'}
                      </span>
                      <span className={`chip${u.autoSync ? ' on' : ''}`} title={`Synchro ${u.autoSync ? 'automatique' : 'manuelle'}`}>
                        <RefreshCw size={12} />{u.autoSync ? 'Auto' : 'Manuel'}
                      </span>
                    </div>
                  </td>
                  <td className="muted" title={u.deviceModel || ''}>
                    <span className="device-cell"><Smartphone size={14} /><span>{u.deviceModel || '—'}</span></span>
                  </td>
                  <td style={{ whiteSpace: 'nowrap' }}>
                    {timeAgo(u.lastSyncAt)}
                    <div className="muted" style={{ fontSize: 12 }}>vu {timeAgo(u.lastSeenAt)}</div>
                  </td>
                  <td className="num muted"><ChevronRight size={18} /></td>
                </motion.tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
