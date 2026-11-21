const nf = new Intl.NumberFormat('fr-FR', { maximumFractionDigits: 2 });
export const formatAmount = (v) => nf.format(Math.round((Number(v) || 0) * 100) / 100);
export const formatMoney = (v, devise) => `${formatAmount(v)} ${devise === 'USD' ? '$' : 'FC'}`;

export function formatBytes(b) {
  if (!b) return '0 o';
  const u = ['o', 'Ko', 'Mo', 'Go'];
  const i = Math.min(Math.floor(Math.log(b) / Math.log(1024)), u.length - 1);
  return `${(b / 1024 ** i).toFixed(i ? 1 : 0).replace('.', ',')} ${u[i]}`;
}

const rtf = new Intl.RelativeTimeFormat('fr', { numeric: 'auto' });
export function timeAgo(iso) {
  if (!iso) return 'jamais';
  const s = (new Date(iso).getTime() - Date.now()) / 1000;
  const abs = Math.abs(s);
  if (abs < 45) return "à l'instant";
  if (abs < 3600) return rtf.format(Math.round(s / 60), 'minute');
  if (abs < 86400) return rtf.format(Math.round(s / 3600), 'hour');
  if (abs < 86400 * 30) return rtf.format(Math.round(s / 86400), 'day');
  return rtf.format(Math.round(s / (86400 * 30)), 'month');
}

export const formatDate = (iso, withTime = true) =>
  iso
    ? new Date(iso).toLocaleString('fr-FR', {
        day: '2-digit', month: 'short', year: 'numeric',
        ...(withTime ? { hour: '2-digit', minute: '2-digit' } : {}),
      })
    : '—';

/** Affichage de l'identifiant : 7KQ2M·LIVIA. */
export const prettyId = (id) => (id?.endsWith('LIVIA') ? `${id.slice(0, -5)}·LIVIA` : id);
