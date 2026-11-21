import { CloudUpload, Download, Search } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { api, download } from '../api';
import { Avatar, Empty, FadeIn, Segmented, Skeleton, StatusPill } from '../components/ui';
import { formatBytes, formatDate, prettyId, timeAgo } from '../format';
import { go } from '../nav';

export default function Backups() {
  const [rows, setRows] = useState(null);
  const [q, setQ] = useState('');
  const [kind, setKind] = useState('all');

  useEffect(() => {
    api('/backups').then(setRows).catch(() => setRows([]));
  }, []);

  const list = useMemo(() => {
    if (!rows) return null;
    const s = q.trim().toLowerCase();
    return rows
      .filter((b) => kind === 'all' || b.kind === kind)
      .filter((b) => !s || b.deviceId.toLowerCase().includes(s) || (b.companyName || '').toLowerCase().includes(s));
  }, [rows, q, kind]);

  const total = rows?.reduce((s, b) => s + b.size, 0) || 0;

  return (
    <>
      <header className="topbar" style={{ flexWrap: 'wrap' }}>
        <div className="grow">
          <h1>Sauvegardes</h1>
          <p>{rows ? `${rows.length} sauvegarde(s) · ${formatBytes(total)} stockés` : 'Chargement…'}</p>
        </div>
        <label className="input" style={{ width: 'min(320px, 100%)' }}>
          <Search size={18} />
          <input placeholder="ID ou entreprise…" value={q} onChange={(e) => setQ(e.target.value)} />
        </label>
      </header>

      <div style={{ marginBottom: 20 }}>
        <Segmented id="bk" value={kind} onChange={setKind} options={[
          { value: 'all', label: 'Toutes' },
          { value: 'auto', label: 'Automatiques' },
          { value: 'manual', label: 'Manuelles' },
        ]} />
      </div>

      {!list ? (
        <Skeleton height={320} />
      ) : !list.length ? (
        <div className="glass"><Empty title="Aucune sauvegarde" message="Les sauvegardes envoyées par les téléphones apparaîtront ici." /></div>
      ) : (
        <FadeIn className="glass" style={{ overflowX: 'auto' }}>
          <table className="data">
            <thead>
              <tr><th>Utilisateur</th><th>Date</th><th>Type</th><th className="num">Clients</th><th className="num">Dettes</th><th className="num">Taille</th><th /></tr>
            </thead>
            <tbody>
              {list.map((b) => (
                <tr key={b.id}>
                  <td style={{ cursor: 'pointer' }} onClick={() => go(`users/${b.deviceId}`)}>
                    <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
                      <Avatar name={b.companyName || '?'} size={36} />
                      <div>
                        <b>{b.companyName || 'Sans nom'}</b>
                        <div className="mono muted" style={{ fontSize: 12 }}>{prettyId(b.deviceId)}</div>
                      </div>
                    </div>
                  </td>
                  <td>{formatDate(b.createdAt)}<div className="muted" style={{ fontSize: 12 }}>{timeAgo(b.createdAt)}</div></td>
                  <td>
                    <StatusPill icon={CloudUpload} label={b.kind === 'auto' ? 'Auto' : 'Manuelle'} color={b.kind === 'auto' ? 'var(--glow-b)' : 'var(--primary)'} />
                  </td>
                  <td className="num">{b.counts.customers}</td>
                  <td className="num">{b.counts.debts}</td>
                  <td className="num">{formatBytes(b.size)}</td>
                  <td className="num">
                    <button className="btn sm" onClick={() => download(`/backups/${b.id}/download`)} title="Télécharger"><Download size={16} /></button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </FadeIn>
      )}
    </>
  );
}
