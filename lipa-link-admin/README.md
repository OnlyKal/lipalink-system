# LipaLink Cloud — Administration

Serveur de sauvegarde / synchronisation pour l'app mobile LipaLink, et dashboard d'administration.

```
server/   Node.js + Express + SQLite (better-sqlite3)  → API + stockage des sauvegardes
web/      React + Vite (framer-motion, lucide)         → dashboard admin (même design que l'app)
```

## Démarrer

```bash
# 1. Serveur (port 4100)
cd server
npm install
ADMIN_PASSWORD="un-mot-de-passe-solide" npm start

# 2. Dashboard en développement (http://localhost:5173, /api est relayé vers :4100)
cd web
npm install
npm run dev
```

En production : `cd web && npm run build`, puis le serveur sert directement le dashboard
compilé sur http://localhost:4100.

Données de démo (serveur démarré) : `cd server && npm run seed`.

### Variables d'environnement (serveur)

| Variable         | Défaut          | Rôle                                         |
| ---------------- | --------------- | -------------------------------------------- |
| `PORT`           | `4100`          | Port HTTP                                    |
| `ADMIN_PASSWORD` | `admin`         | Mot de passe du dashboard — **à changer**    |
| `DATA_DIR`       | `server/data`   | Base SQLite + fichiers de sauvegarde (.gz)   |
| `ADMIN_SECRET`   | généré          | Clé de signature des sessions admin          |

## Fonctionnement

**Côté téléphone** (Réglages → Sauvegarde en ligne) :

- **Activation** : à la première activation, le serveur attribue un identifiant
  `XXXXX` + `LIVIA` (ex. `7KQ2MLIVIA`, sans caractères ambigus 0/O/1/I) et une
  **clé de récupération** `XXXX-XXXX`.
- **Connexion** : sur un autre téléphone, « J'ai déjà un identifiant » → ID + clé,
  puis proposition de restaurer la dernière sauvegarde.
- **Synchronisation** (auto ou manuelle) : le serveur garde une copie à jour des
  clients, dettes et paiements. En mode auto : au démarrage, quand l'app passe en
  arrière-plan et en tâche de fond (Workmanager).
- **Sauvegarde** (auto ou manuelle) : instantané daté et compressé, restaurable.
  En mode auto : au plus une par jour, seulement si les données ont changé.
  Les 30 dernières sont conservées par utilisateur.
- **Gestion de connexion** : état Connecté / Hors ligne / Session expirée /
  Suspendu, adresse du serveur modifiable, déconnexion.

**Côté administration** :

- Vue d'ensemble : utilisateurs, % de données à jour, sauvegardes, stockage,
  activité sur 14 jours, utilisateurs à surveiller, dernière activité.
- Utilisateurs : recherche, filtres par état. Détail : infos entreprise, appareil,
  mode auto/manuel, **comparaison téléphone ↔ serveur**, soldes, clients, dettes,
  sauvegardes (téléchargement JSON), historique, note interne, suspension.

### « Les données sont-elles à jour ? »

À chaque contact, le téléphone envoie une empreinte de ses données. Le serveur la
compare à l'empreinte de la dernière synchronisation :

| État                       | Signification                                            |
| -------------------------- | -------------------------------------------------------- |
| À jour                     | le serveur a exactement les données du téléphone         |
| Modifs non synchronisées   | le téléphone a changé depuis la dernière synchro         |
| Inactif                    | aucun contact depuis 7 jours                             |
| Jamais synchronisé         | activé mais rien reçu                                    |
| Suspendu                   | bloqué par l'admin (le téléphone ne peut plus envoyer)   |

## API appareil (`/api/device`)

`POST /activate` · `POST /login` · `GET /me` · `POST /heartbeat` · `PUT /settings` ·
`POST /sync` · `POST /backups` · `GET /backups` · `GET /backups/:id` · `POST /disconnect`
— authentifiées par `Authorization: Bearer <jeton>` (sauf activate/login).

## Mise en production

L'app mobile pointe par défaut sur `http://10.0.2.2:4100` (émulateur Android) —
voir `kDefaultCloudUrl` dans `lib/cloud/cloud_service.dart`. Pour un vrai déploiement,
placer le serveur derrière HTTPS (nginx/Caddy) et mettre cette URL par défaut ;
`usesCleartextTraffic` (Android) ne sert qu'aux tests en HTTP local.
