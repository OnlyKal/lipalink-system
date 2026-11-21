import { motion } from 'framer-motion';
import { useState } from 'react';

/** Barres groupées : sauvegardes et synchronisations des 14 derniers jours. */
export default function ActivityChart({ data }) {
  const [hover, setHover] = useState(null);
  const W = 640, H = 200, pad = 24;
  const max = Math.max(1, ...data.flatMap((d) => [d.backups, d.syncs]));
  const slot = (W - pad) / data.length;
  const bw = Math.min(14, slot / 3);
  const y = (v) => H - pad - (v / max) * (H - pad * 2);

  return (
    <div style={{ position: 'relative' }}>
      <svg viewBox={`0 0 ${W} ${H}`} width="100%" style={{ display: 'block', overflow: 'visible' }}>
        {[0, 0.5, 1].map((t) => (
          <line key={t} x1={pad} x2={W} y1={y(max * t)} y2={y(max * t)} stroke="var(--outline)" strokeDasharray="3 5" />
        ))}
        {data.map((d, i) => {
          const x = pad + i * slot + slot / 2;
          return (
            <g key={d.day} onMouseEnter={() => setHover(i)} onMouseLeave={() => setHover(null)}>
              <rect x={x - slot / 2} y={0} width={slot} height={H} fill={hover === i ? 'var(--glass)' : 'transparent'} rx={10} />
              {[['backups', 'var(--glow-b)', -bw - 1], ['syncs', 'var(--receivable)', 1]].map(([k, c, dx]) => (
                <motion.rect
                  key={k}
                  x={x + dx}
                  width={bw}
                  rx={bw / 2.5}
                  fill={c}
                  initial={{ y: H - pad, height: 0 }}
                  animate={{ y: y(d[k]), height: Math.max(d[k] ? 3 : 0, H - pad - y(d[k])) }}
                  transition={{ duration: 0.7, delay: i * 0.03, ease: [0.2, 0.8, 0.2, 1] }}
                />
              ))}
              {(i % 2 === 0 || i === data.length - 1) && (
                <text x={x} y={H - 4} textAnchor="middle" fontSize="11" fill="var(--on-surface-variant)">
                  {new Date(d.day).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short' })}
                </text>
              )}
            </g>
          );
        })}
      </svg>
      {hover != null && (
        <div className="glass" style={{ position: 'absolute', top: -8, left: `${((hover + 0.5) / data.length) * 100}%`, transform: 'translate(-50%, -100%)', padding: '8px 12px', fontSize: 13, whiteSpace: 'nowrap', pointerEvents: 'none' }}>
          <b>{new Date(data[hover].day).toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' })}</b>
          <div className="muted">{data[hover].backups} sauvegarde(s) · {data[hover].syncs} synchro(s)</div>
        </div>
      )}
    </div>
  );
}
