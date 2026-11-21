import { AnimatePresence, motion } from 'framer-motion';
import { Archive, LayoutDashboard, LogOut, Monitor, Moon, Sun, Users as UsersIcon } from 'lucide-react';
import { useCallback, useEffect, useState } from 'react';
import { api, auth, setUnauthorizedHandler } from './api';
import Backups from './pages/Backups';
import Login from './pages/Login';
import Overview from './pages/Overview';
import UserDetail from './pages/UserDetail';
import Users from './pages/Users';
import { go } from './nav';
import { useTheme } from './theme';

const NAV = [
  { id: 'overview', label: "Vue d'ensemble", icon: LayoutDashboard },
  { id: 'users', label: 'Utilisateurs', icon: UsersIcon },
  { id: 'backups', label: 'Sauvegardes', icon: Archive },
];

/** Routage minimal par hash : #/users, #/users/7KQ2MLIVIA… */
function useRoute() {
  const read = () => window.location.hash.replace(/^#\/?/, '').split('/');
  const [route, setRoute] = useState(read);
  useEffect(() => {
    const on = () => setRoute(read());
    window.addEventListener('hashchange', on);
    return () => window.removeEventListener('hashchange', on);
  }, []);
  return route;
}

export function Ambient() {
  return (
    <div className="ambient">
      <div className="glow a" />
      <div className="glow b" />
    </div>
  );
}

export default function App() {
  const [theme, setTheme] = useTheme();
  const [logged, setLogged] = useState(!!auth.get());
  const [attention, setAttention] = useState(0);
  const [refreshKey, setRefreshKey] = useState(0);
  const [section = 'overview', userId] = useRoute();

  const logout = useCallback(() => {
    auth.clear();
    setLogged(false);
  }, []);
  useEffect(() => setUnauthorizedHandler(logout), [logout]);

  // Compteur « à surveiller » dans le menu, rafraîchi toutes les 30 s.
  useEffect(() => {
    if (!logged) return;
    const load = () =>
      api('/overview')
        .then((o) => setAttention(o.byFreshness.pending + o.byFreshness.never))
        .catch(() => {});
    load();
    const t = setInterval(load, 30000);
    return () => clearInterval(t);
  }, [logged, refreshKey]);

  if (!logged) {
    return (
      <>
        <Ambient />
        <Login onLogged={() => setLogged(true)} />
      </>
    );
  }

  const active = NAV.some((n) => n.id === section) ? section : 'overview';
  const page = {
    overview: <Overview />,
    users: <Users />,
    backups: <Backups />,
  }[active];

  return (
    <>
      <Ambient />
      <div className="shell">
        <aside className="sidebar">
          <div className="brand">
            <img src="/livia.png" alt="" />
            <div>
              <b>LipaLink</b>
              <span>Administration cloud</span>
            </div>
          </div>
          {NAV.map((n) => (
            <button key={n.id} className={`nav-item${active === n.id ? ' active' : ''}`} onClick={() => go(n.id)}>
              {active === n.id && <motion.span layoutId="nav-pill" className="pill" transition={{ type: 'spring', bounce: 0.2, duration: 0.5 }} />}
              <n.icon size={20} />
              <span className="label">{n.label}</span>
              {n.id === 'users' && attention > 0 && <span className="count">{attention}</span>}
            </button>
          ))}
          <div className="spacer" />
          <div className="theme-wrap segmented" style={{ justifyContent: 'space-between' }}>
            {[
              ['system', Monitor, 'Auto'],
              ['light', Sun, 'Clair'],
              ['dark', Moon, 'Sombre'],
            ].map(([m, Icon, label]) => (
              <button key={m} className={theme === m ? 'on' : ''} onClick={() => setTheme(m)} title={label}>
                {theme === m && <motion.span layoutId="theme-pill" className="seg-bg" />}
                <span><Icon size={16} /></span>
              </button>
            ))}
          </div>
          <button className="nav-item" onClick={logout}>
            <LogOut size={20} />
            <span className="label">Déconnexion</span>
          </button>
        </aside>

        <main className="main">
          <AnimatePresence mode="wait">
            <motion.div
              key={active + refreshKey}
              initial={{ opacity: 0, scale: 0.985 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.985 }}
              transition={{ duration: 0.3, ease: [0.2, 0.8, 0.2, 1] }}
            >
              {page}
            </motion.div>
          </AnimatePresence>
        </main>
      </div>

      <AnimatePresence>
        {userId && active === 'users' && (
          <UserDetail
            key={userId}
            id={userId}
            onClose={() => go('users')}
            onChanged={() => setRefreshKey((k) => k + 1)}
          />
        )}
      </AnimatePresence>
    </>
  );
}
