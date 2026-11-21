import { Ban, CloudUpload, KeyRound, LogIn, LogOut, RefreshCw, RotateCcw, Settings2, ShieldCheck, Sparkles } from 'lucide-react';

export const EVENTS = {
  activate: { label: 'Activation', icon: Sparkles, color: 'var(--primary)' },
  login: { label: 'Connexion', icon: LogIn, color: 'var(--primary)' },
  sync: { label: 'Synchronisation', icon: RefreshCw, color: 'var(--receivable)' },
  backup: { label: 'Sauvegarde', icon: CloudUpload, color: 'var(--glow-b)' },
  restore: { label: 'Restauration', icon: RotateCcw, color: 'var(--warning)' },
  settings: { label: 'Réglages', icon: Settings2, color: 'var(--payable)' },
  disconnect: { label: 'Déconnexion', icon: LogOut, color: 'var(--on-surface-variant)' },
  blocked: { label: 'Suspension', icon: Ban, color: 'var(--danger)' },
  unblocked: { label: 'Réactivation', icon: ShieldCheck, color: 'var(--success)' },
};
export const eventOf = (type) => EVENTS[type] || { label: type, icon: KeyRound, color: 'var(--on-surface-variant)' };
