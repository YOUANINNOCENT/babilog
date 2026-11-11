# BabiLogis — tout en Dart

```
babilog/
├── serveur/      API + base SQLite + service du site (Dart, shelf)
├── babilogi/     site web (Flutter Web)
└── ia_service/   modèle d'estimation + agent IA (Python, FastAPI)
```

Applications reliées au même serveur (même base, mêmes comptes) :
- mobile : `~/Desktop/logibabi/babilogi` (Flutter) ;
- desktop agence : `~/Desktop/babilogi_desk` (Python, PySide6).

Tout lancer d'un coup : `bash ~/Desktop/babilog/lancer_tout.sh` (ou `site`, `mobile`, `desktop`).

## Développement (deux terminaux)

```bash
cd ~/Desktop/babilog/serveur && dart pub get && dart run bin/serveur.dart
```
```bash
cd ~/Desktop/babilog/babilogi && flutter pub get && flutter run -d chrome
```

## Démo (une seule adresse)

```bash
cd ~/Desktop/babilog/babilogi && flutter build web
cd ../serveur && dart run bin/serveur.dart     # site + API sur http://127.0.0.1:8000
```

## Comptes

Il n'y a plus de comptes de démonstration : on utilise de **vrais comptes**, créés avec « Créer un compte »
sur le site ou dans l'app mobile (code de vérification envoyé par e-mail).

- **Locataire** : recherche, favoris, demandes de visite, messagerie avec l'annonceur.
- **Propriétaire ou agence** : publication et modification d'annonces (site, mobile, desktop), photos
  depuis le stockage de l'appareil ou la bibliothèque d'illustrations, aperçu avant publication.
  Ces comptes ne voient pas « Contacter l'annonceur » ni « Demander une visite ».
- **Administrateur** : à donner à un compte existant, une seule fois :
  `cd serveur && dart run bin/serveur.dart --admin votre@adresse.com`
- **Mot de passe oublié** : lien sur la page de connexion (site et mobile), code à 6 chiffres par e-mail.


## Service IA (Blocs 4 et 5) — dossier `ia_service`

Service Python FastAPI qui fournit le modèle d'estimation des loyers et l'agent « Babi » (DeepSeek et outils).

```bash
cd ia_service && ./lancer.sh        # http://127.0.0.1:8001/docs
```

- Le serveur Dart l'utilise automatiquement s'il tourne sur le port 8001. Pour le désactiver : `IA_SERVICE_URL=aucun`.
- La page **Assistant IA** du site (`/assistant`) passe par `POST /api/assistant`.
- Pour activer DeepSeek : `cd ia_service && bash configurer_cle.sh` (la clé est saisie masquée et rangée dans `ia_service/.env`, non partagé). Sans clé, l'agent fonctionne par règles.
