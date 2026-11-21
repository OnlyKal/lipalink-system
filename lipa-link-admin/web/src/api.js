const TOKEN_KEY = 'lipalink_admin_token';

export const auth = {
  get: () => localStorage.getItem(TOKEN_KEY),
  set: (t) => localStorage.setItem(TOKEN_KEY, t),
  clear: () => localStorage.removeItem(TOKEN_KEY),
};

let onUnauthorized = () => {};
export const setUnauthorizedHandler = (fn) => (onUnauthorized = fn);

export async function api(path, { method = 'GET', body } = {}) {
  const res = await fetch(`/api/admin${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(auth.get() ? { Authorization: `Bearer ${auth.get()}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json().catch(() => ({}));
  if (res.status === 401 && path !== '/login') onUnauthorized();
  if (!res.ok) throw new Error(data.error || 'Erreur réseau');
  return data;
}

/** Téléchargement d'un fichier protégé (le jeton passe par l'en-tête). */
export async function download(path) {
  const res = await fetch(`/api/admin${path}`, { headers: { Authorization: `Bearer ${auth.get()}` } });
  if (!res.ok) throw new Error('Téléchargement impossible');
  const name = /filename="([^"]+)"/.exec(res.headers.get('Content-Disposition') || '')?.[1] || 'sauvegarde.json';
  const url = URL.createObjectURL(await res.blob());
  const a = Object.assign(document.createElement('a'), { href: url, download: name });
  a.click();
  URL.revokeObjectURL(url);
}
