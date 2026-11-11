# Mettre BabiLogis en ligne sur Railway

Deux services dans un même projet Railway :

| Service | Dossier envoyé | Rôle | Accès |
|---|---|---|---|
| `api` | `babilog/` (Dockerfile à la racine) | site web + API Dart + base SQLite | public (https://….up.railway.app) |
| `ia`  | `babilog/ia_service/` (son Dockerfile) | modèle Random Forest + agent « Babi » (Groq, DeepSeek ou Gemini) | privé (`ia.railway.internal`) |

La base SQLite et les photos envoyées vivent dans un **volume** monté sur `/data` (service `api`) :
elles survivent aux redéploiements. Au premier démarrage, le serveur y copie les 875 vraies annonces
et les illustrations.

Formule conseillée : **Hobby** (5 $/mois, 5 $ d'utilisation inclus, volume jusqu'à 5 Go).

## 1. Préparer (une seule fois)

```bash
brew install railway          # ou : npm i -g @railway/cli
railway login                 # ouvre le navigateur
cd ~/Desktop/babilog
railway init                  # nom du projet : babilogis
```

## 2. Créer les services (tableau de bord Railway)

1. Dans le projet : **+ Create → Empty Service**, nommez-le `api`. Recommencez pour `ia`.
2. Service `api` → clic droit → **Attach volume** → chemin de montage : `/data`.
3. Service `api` → **Settings → Networking → Generate Domain** (adresse publique du site).

## 3. Variables (onglet *Variables* de chaque service)

Commencez par créer un **secret interne** (une longue chaîne aléatoire) sur votre Mac :
`openssl rand -hex 32`. Il sert aux deux services : seul le serveur BabiLogis peut alors appeler
l'agent IA (dont le LLM est payant).

Service `ia` :
```
PORT=8001
IA_CLE_INTERNE=…              # le secret interne
IA_FOURNISSEUR=groq           # ou deepseek, gemini (comme dans ia_service/.env)
GROQ_API_KEY=…                # la clé du fournisseur choisi, à coller ici, jamais dans le code
BABILOGIS_API_URL=http://${{api.RAILWAY_PRIVATE_DOMAIN}}:8000/api
BABILOGIS_SITE_URL=https://${{api.RAILWAY_PUBLIC_DOMAIN}}
```

Service `api` :
```
PORT=8000
IA_CLE_INTERNE=…              # le même secret interne
IA_SERVICE_URL=http://${{ia.RAILWAY_PRIVATE_DOMAIN}}:8001
CORS_ORIGINES=https://${{RAILWAY_PUBLIC_DOMAIN}}   # facultatif : seules ces origines peuvent appeler l'API depuis un navigateur
SMTP_UTILISATEUR=votre.adresse@gmail.com
SMTP_MOT_DE_PASSE=…           # mot de passe d'application Google
ADMIN_EMAIL=votre@adresse.com # facultatif : ce compte devient administrateur
```

Les fichiers `.env` locaux ne sont **jamais** envoyés (ils sont exclus par `.gitignore` et `.dockerignore`).

## 4. Déployer

```bash
cd ~/Desktop/babilog
railway up --service api           # site + API (la 1re fois : ~5-10 min, Flutter compile le site)

cd ~/Desktop/babilog/ia_service
railway up --service ia
```

Ouvrez l'adresse générée à l'étape 2 : le site s'affiche, l'API répond sur `/api/sante`.
À chaque modification du code, relancez la même commande `railway up`.

## 5. Brancher les applications

- **Site web** : rien à faire, il utilise automatiquement l'adresse où il est servi.
- **Mobile** :
  ```bash
  cd ~/Desktop/logibabi/babilogi
  flutter run -d chrome --dart-define=API_URL=https://VOTRE-ADRESSE.up.railway.app/api
  flutter build apk --dart-define=API_URL=https://VOTRE-ADRESSE.up.railway.app/api   # APK Android
  ```
- **Desktop** :
  ```bash
  cd ~/Desktop/babilogi_desk
  BABILOGIS_API=https://VOTRE-ADRESSE.up.railway.app/api bash lancer.sh
  ```

## Sécurité (déjà en place)

- HTTPS fourni par Railway ; en-têtes de sécurité et HSTS (`BABILOGIS_PRODUCTION=1`, défini dans le Dockerfile).
- Limitation des tentatives par adresse IP (connexion, inscription, codes, assistant, messages, visites)
  et blocage d'un compte pendant 15 minutes après 8 mots de passe erronés.
- Sessions valables 30 jours ; requêtes limitées à 8 Mo ; journaux sans adresse e-mail.
- Service IA privé, protégé par `IA_CLE_INTERNE`, documentation `/docs` désactivée en ligne.
- Détail : `serveur/SECURITE.md`.

## Bon à savoir

- La base en ligne est **neuve** : les comptes créés sur votre Mac n'y sont pas. Recréez-les sur le site en ligne
  (ou demandez à transférer la base locale).
- Journaux : `railway logs --service api`. Les codes e-mail des adresses fictives `@babilogis.ci` s'y affichent.
- Si le service `ia` ne répond pas, l'API continue avec ses règles d'estimation (rien n'est bloqué).
