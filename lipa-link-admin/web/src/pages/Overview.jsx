import { Activity, AlertTriangle, CloudUpload, HardDrive, RefreshCw, Users } from 'lucide-react';
import { useEffect, useState } from 'react';
import { go } from '../nav';
import { api } from '../api';
import ActivityChart from '../components/ActivityChart';
import { eventOf } from '../components/events';
import { AnimatedNumber, Avatar, Empty, FadeIn, FRESHNESS, FreshnessPill, IconBadge, SectionTitle, Skeleton, StatusPill } from '../components/ui';
import { formatBytes, prettyId, timeAgo } from '../format';

export default function Overview() {
  const [data, setData] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    const load = () => api('/overview').then(setData).catch((e) => setError(e.message));
    load();
    const t = setInterval(load, 20000);
    return () => clearInterval(t);
  }, []);

  if (error) return <Empty title="Serveur injoignable" message={error} />;

  const upToDatePct = data && data.users ? Math.round((data.byFreshness.uptodate / data.users) * 100) : 0;

  const kpis = data && [
    { label: 'Utilisateurs', value: data.users, icon: Users, color: 'var(--primary)', sub: `${data.activeToday} actif(s) aujourd'hui` },
    { label: 'Données à jour', value: upToDatePct, suffix: ' %', icon: RefreshCw, color: 'var(--success)', sub: `${data.byFreshness.pending} en attente de synchro` },
    { label: 'Sauvegardes', value: data.backups, icon: CloudUpload, color: 'var(--glow-b)', sub: `${data.autoBackup} en mode automatique` },
    { label: 'Stockage', value: data.storage, format: formatBytes, icon: HardDrive, color: 'var(--payable)', sub: `${data.customers} clients · ${data.debts} dettes` },
  ];

  return (
    <>
      <header className="topbar">
        <div className="grow">
          <h1>Vue d'ensemble</h1>
          <p>Sauvegardes et synchronisations en temps réel</p>
        </div>
      </header>

      <div className="grid kpis">
        {kpis
          ? kpis.map((k, i) => (
              <FadeIn key={k.label} index={i} className="glass card kpi">
                <IconBadge icon={k.icon} color={k.color} />
                <div>
                  <div className="value">
                    <AnimatedNumber value={k.value} format={k.format} />
                    {k.suffix}
                  </div>
                  <div className="label">{k.label}</div>
                </div>
                <div className="sub">{k.sub}</div>
              </FadeIn>
            ))
          : [0, 1, 2, 3].map((i) => <Skeleton key={i} height={170} />)}
      </div>

      <div className="grid two" style={{ marginTop: 16 }}>
        <FadeIn index={4} className="glass card">
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16, gap: 12, flexWrap: 'wrap' }}>
            <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
              <IconBadge icon={Activity} color="var(--receivable)" size={38} />
              <b style={{ fontSize: 17 }}>Activité · 14 jours</b>
            </div>
            <div className="legend">
              <span><i style={{ background: 'var(--glow-b)' }} />Sauvegardes</span>
              <span><i style={{ background: 'var(--receivable)' }} />Synchros</span>
            </div>
          </div>
          {data ? <ActivityChart data={data.activity} /> : <Skeleton height={200} />}
        </FadeIn>

        <FadeIn index={5} className="glass card">
          <b style={{ fontSize: 17 }}>État des données</b>
          <p className="muted" style={{ margin: '4px 0 18px', fontSize: 14 }}>Le serveur a-t-il la dernière version du téléphone ?</p>
          {data &&
            Object.entries(FRESHNESS).map(([k, f]) => {
              const n = data.byFreshness[k] || 0;
              const pct = data.users ? (n / data.users) * 100 : 0;
              return (
                <div key={k} style={{ marginBottom: 14 }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 14, marginBottom: 6 }}>
                    <span style={{ fontWeight: 600 }}>{f.label}</span>
                    <b className="tabular">{n}</b>
                  </div>
                  <div className="progress" style={{ '--c': f.color }}>
                    <div style={{ width: `${pct}%`, transition: 'width 0.9s cubic-bezier(.2,.8,.2,1)' }} />
                  </div>
                </div>
              );
            })}
        </FadeIn>
      </div>

      <div className="grid two">
        <div>
          <SectionTitle>
            <span style={{ display: 'inline-flex', gap: 8, alignItems: 'center' }}>
              <AlertTriangle size={14} /> À surveiller
            </span>
          </SectionTitle>
          <FadeIn index={6} className="glass" style={{ padding: 6 }}>
            {data?.attention.length ? (
              <div className="row-list">
                {data.attention.map((u) => (
                  <div key={u.id} className="row clickable" onClick={() => go(`users/${u.id}`)}>
                    <Avatar name={u.companyName} size={42} />
                    <div className="grow">
                      <div className="title">{u.companyName}</div>
                      <div className="sub mono">{prettyId(u.id)} · vu {timeAgo(u.lastSeenAt)}</div>
                    </div>
                    {u.freshness === 'uptodate' && u.backupLate ? (
                      <StatusPill icon={CloudUpload} label="Sauvegarde en retard" color="var(--warning)" />
                    ) : (
                      <FreshnessPill value={u.freshness} />
                    )}
                  </div>
                ))}
              </div>
            ) : (
              <Empty title="Tout est en ordre ✨" message="Tous les utilisateurs sont synchronisés." />
            )}
          </FadeIn>
        </div>

        <div>
          <SectionTitle>Dernière activité</SectionTitle>
          <FadeIn index={7} className="glass card">
            {data?.recent.length ? (
              <div className="timeline">
                {data.recent.map((e) => {
                  const ev = eventOf(e.type);
                  return (
                    <div key={e.id} className="ev" style={{ '--c': ev.color, cursor: 'pointer' }} onClick={() => e.device_id && go(`users/${e.device_id}`)}>
                      <b>{ev.label}</b> <span className="muted">· {e.companyName || prettyId(e.device_id)}</span>
                      <small>{e.message} · {timeAgo(e.created_at)}</small>
                    </div>
                  );
                })}
              </div>
            ) : (
              <Empty title="Aucune activité" message="Les actions des téléphones apparaîtront ici." />
            )}
          </FadeIn>
        </div>
      </div>
    </>
  );
}
