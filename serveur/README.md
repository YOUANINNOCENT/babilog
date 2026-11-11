# Serveur BabiLogis (Dart)

API JSON + base de données SQLite + service du site web, **entièrement en Dart**
(paquets `shelf`, `shelf_router`, `shelf_static`, `sqlite3`). Il remplace l'ancien projet Laravel :
mêmes adresses `/api/...` et même format JSON, donc le site, l'app mobile et l'app desktop fonctionnent sans changement.

## Lancer

```bash
cd ~/Desktop/babilog/serveur
dart pub get                     # une seule fois
dart run bin/serveur.dart        # http://127.0.0.1:8000
```

Au premier lancement, la base `donnees/babilogis.sqlite` est créée avec les **vraies annonces**
(voir « Vraies données » plus bas).

- Repartir de zéro : `dart run bin/serveur.dart --reinitialiser` (efface aussi les comptes : faites d'abord une copie de la base)
- Autre port : `dart run bin/serveur.dart --port 9000`
- Nommer un administrateur : `dart run bin/serveur.dart --admin votre@adresse.com`
- Tests : `dart test`

## Comptes

**Vrais comptes uniquement.** Les anciens comptes de démonstration (`…@babilogis.ci`, mot de passe `password`)
sont supprimés automatiquement au démarrage quand les vraies données sont chargées, et ne sont plus recréés.
Une copie de la base d'avant la suppression est gardée dans `donnees/babilogis-sauvegarde-avant-suppression-demo.sqlite`.

- Les comptes se créent depuis le site ou l'app mobile (« Créer un compte »), avec un code envoyé par e-mail.
- Rôles : `locataire`, `annonceur` (propriétaire ou agence), `admin` (option `--admin`, une seule fois).
- Contacter un annonceur et demander une visite sont réservés aux locataires (refus 403 pour un annonceur).
- Au démarrage, la console affiche le nombre de comptes et d'administrateurs.

Les tests (`dart test`) utilisent une base en mémoire, avec leurs propres comptes fictifs : ils ne touchent pas à la vraie base.

## Adresses de l'API

| Méthode | Adresse | Rôle |
|---|---|---|
| GET | `/api/annonces` | Recherche : `commune`, `quartier`, `type`, `pieces`, `budget_max`, `juste`, `meuble`, `equipements[]`, `q`, `tri`, `page`, `per_page` |
| GET | `/api/annonces/{ref}` | Détail d'une annonce |
| GET | `/api/communes`, `/api/referentiel`, `/api/marche` | Listes et baromètre |
| POST | `/api/estimation` | Loyer juste estimé (+ verdict si `loyer`) |
| POST | `/api/visites`, `/api/signalements` | Demandes des locataires |
| POST | `/api/connexion`, `/api/inscription`, `/api/deconnexion` · GET `/api/moi` | Comptes (jeton « Bearer ») |
| POST | `/api/verification` (`email`, `code`), `/api/verification/renvoyer` (`email`) | Code à 6 chiffres envoyé par e-mail à l'inscription |
| POST | `/api/mot-de-passe/oublie` (`email`), `/api/mot-de-passe/reinitialiser` (`email`, `code`, `password`) | Mot de passe oublié |
| GET/POST | `/api/conversations`, `/api/conversations/{id}/messages` · GET `/api/notifications` · POST `/api/notifications/lues` | Messagerie locataire ↔ annonceur, notifications |
| POST/DELETE | `/api/espace/annonces/{ref}/photos[/{id}]` · GET `/api/illustrations` | Photos des annonces |
| GET/POST/PUT/DELETE | `/api/espace`, `/api/espace/annonces/{ref}` · PATCH `/api/espace/visites/{id}` | Espace annonceur |
| GET/PATCH | `/api/admin/signalements[/{id}]` · PATCH `/api/admin/annonces/{ref}/republier` | Administration |

## Base de données (MERISE → SQLite)

`communes` 1,n `quartiers` 1,n `annonces` n,1 `utilisateurs` ; `annonces` n,n `equipements` (`annonce_equipement`) ;
`annonces` 1,n `visites`, `signalements`, `photos`, `conversations` (1,n `messages`) ; `utilisateurs` 1,n `notifications`.
Les mots de passe sont hachés (PBKDF2-SHA256) ; seules les empreintes des jetons et des codes e-mail
(`codes_email`, `codes_mot_de_passe`) sont stockées.

## E-mails (vérification, mot de passe oublié, notifications)

À l'inscription, un code à 6 chiffres (valable 10 minutes, 5 essais) est envoyé par e-mail ; la connexion
est refusée tant qu'il n'a pas été saisi. Les comptes créés avant cette vérification restent actifs.

**Mot de passe oublié** : même principe (code à 6 chiffres, 10 minutes, 5 essais, un envoi par minute au plus).
La réponse est identique que l'adresse existe ou non ; après le changement, les sessions ouvertes sont fermées.
La console indique « ✉ E-mail envoyé à … », ou pourquoi rien n'est parti (aucun compte, demande trop rapprochée).
Pensez aux courriers indésirables.
Les e-mails partent par Gmail SMTP. Renseignez `serveur/.env` (non partagé) :

```
SMTP_UTILISATEUR=votre.adresse@gmail.com
SMTP_MOT_DE_PASSE=xxxx xxxx xxxx xxxx
```

Le mot de passe est un « mot de passe d'application » Google (validation en 2 étapes activée, puis
https://myaccount.google.com/apppasswords), pas le mot de passe du compte Gmail.
Sans identifiants, l'e-mail s'affiche dans la console du serveur. Autre fournisseur : `SMTP_HOTE`, `SMTP_PORT`, `SMTP_SSL=1`.
Les adresses `…@babilogis.ci` (fictives) ne sont jamais envoyées : le message s'affiche dans la console.

## IA

Les estimations sont demandées au service FastAPI `../ia_service` (Blocs 2, 4 et 5) sur `http://127.0.0.1:8001`
(variable `IA_SERVICE_URL` ; `IA_SERVICE_URL=aucun` pour le désactiver). S'il ne répond pas, des règles simples prennent le relais.

## Vraies données (Blocs 1 et 2)

Au premier démarrage, si `donnees/annonces_reelles.json` existe, le serveur charge les **875 vraies annonces** collectées et nettoyées (Bloc 1). Chacune porte l'estimation du modèle (Bloc 2), calculée hors échantillon. Sinon, il charge les annonces de démonstration.

- Les annonces appartiennent au compte technique **collecte@babilogis.ci**, qui ne peut pas se connecter (mot de passe désactivé). Chacune garde le lien vers son annonce d'origine.
- Sans ce fichier, le serveur charge les 60 annonces et les comptes de démonstration (utile seulement hors soutenance).
- Pour regénérer le fichier après avoir relancé les notebooks : `python3 outils/exporter_annonces_reelles.py ~/Desktop/"donnees 1"`.
- `GET /api/sante` indique `"donnees": "reelles"` ou `"demonstration"`.

## Photos (dossier `donnees/images`)

- **Illustrations libres de droits** : `python3 outils/collecter_images.py` télécharge des photos d'intérieurs (studio, appartement, villa) depuis Openverse, avec les licences CC0, CC BY et CC BY-SA. Pour chaque photo, l'auteur, la licence et le lien d'origine sont gardés dans `donnees/images/illustrations/manifeste.json`. Au démarrage, le serveur les importe dans la table `photos`.
- **Annonces sans photo** : elles affichent automatiquement 3 illustrations de leur type de logement, marquées « Photo d'illustration » avec leurs crédits.
- **Annonceurs (propriétaires et agences)** : ils ajoutent leurs vraies photos (depuis le stockage de l'ordinateur ou du téléphone) ou choisissent des illustrations, depuis l'espace annonceur du site, l'app mobile (Profil → Mes annonces et photos) ou l'app desktop. 8 photos maximum par annonce, 5 Mo chacune (JPEG, PNG, WebP).
  - `POST /api/espace/annonces/<ref>/photos` avec `{"nom", "donnees" (base64)}` ou `{"illustration_id"}` ;
  - `DELETE /api/espace/annonces/<ref>/photos/<id>` ;
  - `GET /api/illustrations?type=Villa`.
- Les fichiers envoyés sont rangés dans `donnees/images/annonces/<référence>/`, et servis sur `/images/...`.
