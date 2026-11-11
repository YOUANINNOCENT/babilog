# Mettre BabiLogis en ligne sur alwaysdata (formule gratuite, sans carte bancaire)

Un seul site alwaysdata de type **Programme utilisateur** sert le site web (Flutter Web) et l'API Dart.
Docker n'existe pas sur alwaysdata : tout est compilé sur le Mac, puis envoyé prêt à tourner.

| Sur alwaysdata | Contenu |
|---|---|
| `~/babilogis/` | code envoyé : `serveur` (Linux x64), `site/`, `graines/`, `demarrer.sh` — remplacé à chaque envoi |
| `~/babilogis_donnees/` | base SQLite, photos envoyées, annonces — **jamais écrasé** par un nouvel envoi |

## 1. Construire le dossier (Mac)

```bash
cd ~/Desktop/babilog
sh deploiement/alwaysdata/preparer.sh
```
Résultat : `deploiement/alwaysdata/envoi/` (taille affichée à la fin ; elle doit rester sous ~70 Mo).

## 2. Activer SSH (tableau de bord alwaysdata)

**Accès distant → SSH** → modifier l'utilisateur → cocher « Activer la connexion par mot de passe ».

## 3. Envoyer (Mac) — remplacez COMPTE par votre nom de compte

```bash
rsync -avz --delete ~/Desktop/babilog/deploiement/alwaysdata/envoi/ COMPTE@ssh-COMPTE.alwaysdata.net:babilogis/
```

Test facultatif en SSH : `PORT=8300 ~/babilogis/demarrer.sh` (Ctrl+C pour arrêter).

## 4. Créer le site (Web → Sites → Ajouter un site)

- Adresses : `COMPTE.alwaysdata.net`
- Type : **Programme utilisateur**
- Commande : `/home/COMPTE/babilogis/demarrer.sh`
- Répertoire de travail : `/home/COMPTE/babilogis`
- Environnement (vous collez vous-même les secrets, jamais dans le code) :
  ```
  BABILOGIS_PRODUCTION=1
  CONFIANCE_PROXY=1
  SMTP_UTILISATEUR=…
  SMTP_MOT_DE_PASSE=…
  ADMIN_EMAIL=…
  ```

Vérifier : `https://COMPTE.alwaysdata.net/api/sante` puis `https://COMPTE.alwaysdata.net`.
Journaux : `~/admin/logs/sites/` (en SSH) ou l'onglet Journaux du site.

## 5. Mettre à jour

Étapes 1 et 3, puis **Redémarrer** le site dans Web → Sites.

## 6. Brancher les applications

- Mobile : `flutter build apk --dart-define=API_URL=https://COMPTE.alwaysdata.net/api`
- Desktop : `BABILOGIS_API=https://COMPTE.alwaysdata.net/api bash lancer.sh`

## Bon à savoir

- La base en ligne est neuve : recréez vos comptes sur le site en ligne ; les 875 annonces se chargent au 1er démarrage.
- Les photos de départ ne sont pas dupliquées (liens durs) : elles ne comptent qu'une fois dans les 100 Mo.
- Sans service IA configuré, l'estimation des loyers utilise ses règles de secours.

## Service IA (assistant Babi + modèle Random Forest) : Render gratuit

Le service Python ne tient pas dans les 100 Mo d'alwaysdata : il est hébergé sur Render (offre Free, Docker).

- Dépôt GitHub : `YOUANINNOCENT/babilogis-ia`, contenu de `deploiement/ia_service_github/`
  (aucun `.env` ; le Dockerfile écoute sur `0.0.0.0`, exigé par Render).
- Adresse : https://babilogis-ia.onrender.com (vérification : `/sante`).
- Variables Render : `BABILOGIS_PRODUCTION=1`, `IA_FOURNISSEUR=groq`, `GROQ_API_KEY`, `IA_CLE_INTERNE`,
  `BABILOGIS_API_URL=https://youan.alwaysdata.net/api`, `BABILOGIS_SITE_URL=https://youan.alwaysdata.net`.
- Variables alwaysdata : `IA_SERVICE_URL=https://babilogis-ia.onrender.com` et le **même** `IA_CLE_INTERNE`.
- Le service s'endort après 15 min sans visite (réveil ~50 s). Avant une démonstration, ouvrez `/sante` pour le réveiller.
- Mise à jour : modifier les fichiers sur GitHub → Render redéploie tout seul.
