import { motion } from 'framer-motion';
import { ArrowRight, Lock } from 'lucide-react';
import { useState } from 'react';
import { api, auth } from '../api';

export default function Login({ onLogged }) {
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit(e) {
    e.preventDefault();
    setBusy(true);
    setError('');
    try {
      const { token } = await api('/login', { method: 'POST', body: { password } });
      auth.set(token);
      onLogged();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="login">
      <motion.form
        className="glass box"
        onSubmit={submit}
        initial={{ opacity: 0, y: 30, scale: 0.97 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        transition={{ duration: 0.6, ease: [0.2, 0.8, 0.2, 1] }}
      >
        <img src="/livia.png" alt="" width={56} height={56} style={{ borderRadius: 16 }} />
        <div>
          <h1>Administration</h1>
          <p className="muted" style={{ margin: '4px 0 0' }}>Sauvegardes et synchronisations LipaLink</p>
        </div>
        <label className="input">
          <Lock size={18} />
          <input
            type="password"
            placeholder="Mot de passe administrateur"
            value={password}
            autoFocus
            onChange={(e) => setPassword(e.target.value)}
          />
        </label>
        {error && <motion.div className="error-text" initial={{ x: -8 }} animate={{ x: [8, -6, 4, 0] }}>{error}</motion.div>}
        <button className="btn primary" style={{ height: 52 }} disabled={busy || !password}>
          {busy ? 'Connexion…' : 'Se connecter'} <ArrowRight size={18} />
        </button>
      </motion.form>
    </div>
  );
}
