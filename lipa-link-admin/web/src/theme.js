import { useEffect, useState } from 'react';

const KEY = 'lipalink_theme';
const media = window.matchMedia('(prefers-color-scheme: dark)');

/** Thème Auto / Clair / Sombre, mémorisé (comme ThemeController). */
export function useTheme() {
  const [mode, setMode] = useState(() => localStorage.getItem(KEY) || 'system');
  useEffect(() => {
    const apply = () => {
      const dark = mode === 'dark' || (mode === 'system' && media.matches);
      document.documentElement.dataset.theme = dark ? 'dark' : 'light';
    };
    apply();
    localStorage.setItem(KEY, mode);
    media.addEventListener('change', apply);
    return () => media.removeEventListener('change', apply);
  }, [mode]);
  return [mode, setMode];
}
