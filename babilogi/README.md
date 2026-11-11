# BabiLogis — site web (Flutter Web)

Site de location de logements à Abidjan, relié au serveur Dart (`../serveur`) : mêmes annonces,
mêmes comptes et mêmes photos que l'app mobile et l'app desktop.

## Lancer

```bash
# 1. Serveur (autre terminal)
cd ~/Desktop/babilog/serveur && dart run bin/serveur.dart
# 2. Site
cd ~/Desktop/babilog/babilogi && flutter pub get && flutter run -d chrome --web-port 5000
```

Version à servir par le serveur (une seule adresse, http://127.0.0.1:8000) : `flutter build web`.

## Fonctions

- **Recherche** des annonces (commune, quartier, type, budget, équipements) avec le verdict du modèle :
  prix juste, au-dessus du marché, bonne affaire.
- **Comptes réels** : « Créer un compte » (code par e-mail), connexion, **« Mot de passe oublié ? »**
  (`/mot-de-passe-oublie` : code à 6 chiffres puis nouveau mot de passe).
- **Locataires** : demande de visite, messagerie avec le propriétaire ou l'agence (`/messages`), notifications.
- **Propriétaires et agences** (`/espace`) :
  - publier ou modifier une annonce, avec l'estimation du loyer juste pendant la saisie ;
  - **Prévisualiser** l'annonce telle que les locataires la verront, puis Modifier ou Publier ;
  - photos depuis l'ordinateur ou la bibliothèque d'illustrations libres de droits (8 max, 5 Mo) ;
  - pas de bouton « Contacter » ni « Demander une visite » sur les annonces.
- **Assistant IA** (`/assistant`) et **baromètre** des loyers.
- **Administration** (`/admin`) pour le compte nommé avec `dart run bin/serveur.dart --admin …`.
