import { animate, motion, useMotionValue, useTransform } from 'framer-motion';
import { useEffect } from 'react';
import { formatAmount } from '../format';

export const FRESHNESS = {
  uptodate: { label: 'À jour', color: 'var(--success)', live: true },
  pending: { label: 'Modifs non synchronisées', color: 'var(--warning)' },
  inactive: { label: 'Inactif', color: 'var(--on-surface-variant)' },
  never: { label: 'Jamais synchronisé', color: 'var(--payable)' },
  blocked: { label: 'Suspendu', color: 'var(--danger)' },
};

export function StatusPill({ label, color, live, icon: Icon }) {
  return (
    <span className={`status-pill${live ? ' live' : ''}`} style={{ '--c': color }}>
      {Icon ? <Icon size={13} /> : <span className="dot" />}
      {label}
    </span>
  );
}

export const FreshnessPill = ({ value }) => <StatusPill {...(FRESHNESS[value] || FRESHNESS.never)} />;

export function IconBadge({ icon: Icon, color = 'var(--primary)', size = 44 }) {
  return (
    <span className="icon-badge" style={{ '--c': color, width: size, height: size, borderRadius: size * 0.32 }}>
      <Icon size={size * 0.45} strokeWidth={2.2} />
    </span>
  );
}

// Dégradé stable par nom (comme InitialsAvatar dans l'app).
const GRADIENTS = [
  ['#6366F1', '#8B5CF6'], ['#14B8A6', '#0EA5E9'], ['#F59E0B', '#EF4444'],
  ['#22C55E', '#14B8A6'], ['#EC4899', '#8B5CF6'], ['#0EA5E9', '#6366F1'],
];
export function Avatar({ name = '?', size = 48 }) {
  const initials = name.trim().split(/\s+/).slice(0, 2).map((w) => w[0]).join('').toUpperCase() || '?';
  let h = 0;
  for (const ch of name) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  const [a, b] = GRADIENTS[h % GRADIENTS.length];
  return (
    <span className="avatar" style={{ width: size, height: size, fontSize: size * 0.36, background: `linear-gradient(135deg, ${a}, ${b})` }}>
      {initials}
    </span>
  );
}

/** Nombre qui « compte » jusqu'à sa valeur (comme AnimatedAmount). */
export function AnimatedNumber({ value, format = formatAmount }) {
  const mv = useMotionValue(0);
  const text = useTransform(mv, (v) => format(v));
  useEffect(() => {
    const controls = animate(mv, Number(value) || 0, { duration: 0.9, ease: [0.2, 0.8, 0.2, 1] });
    return controls.stop;
  }, [value, mv]);
  return <motion.span className="tabular">{text}</motion.span>;
}

/** Apparition en fondu + glissement, décalée selon l'index (comme FadeSlideIn). */
export function FadeIn({ index = 0, children, className, style, ...rest }) {
  return (
    <motion.div
      className={className}
      style={style}
      initial={{ opacity: 0, y: 24 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.45, delay: Math.min(index, 10) * 0.06, ease: [0.2, 0.8, 0.2, 1] }}
      {...rest}
    >
      {children}
    </motion.div>
  );
}

export function Segmented({ value, onChange, options, id }) {
  return (
    <div className="segmented">
      {options.map((o) => (
        <button key={o.value} className={value === o.value ? 'on' : ''} onClick={() => onChange(o.value)}>
          {value === o.value && <motion.span layoutId={`seg-${id}`} className="seg-bg" transition={{ type: 'spring', bounce: 0.2, duration: 0.45 }} />}
          <span>{o.label}</span>
          {o.count != null && <span className="muted">{o.count}</span>}
        </button>
      ))}
    </div>
  );
}

export function SectionTitle({ children, trailing }) {
  return (
    <div className="section-title">
      <span>{children}</span>
      {trailing}
    </div>
  );
}

export function Empty({ title, message }) {
  return (
    <div className="empty">
      <b>{title}</b>
      {message}
    </div>
  );
}

export const Skeleton = ({ height = 120, style }) => <div className="skeleton" style={{ height, ...style }} />;
