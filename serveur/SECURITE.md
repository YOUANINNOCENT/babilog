# Audit de sécurité BabiLogis (avant la mise en ligne)

Périmètre : serveur Dart (API + site), service IA (FastAPI), site Flutter Web, application mobile,
application desktop. Méthode : relecture du code (OWASP Top 10 / API Security Top 10).

## Déjà en place (vérifié)

| Point | État |
|---|---|
| Injection SQL | Toutes les requêtes sont paramétrées (`?`) ; le tri vient d'une liste fermée. |
| Mots de passe | PBKDF2-SHA256, sel aléatoire de 16 octets, comparaison en temps constant ; 8 caractères minimum. |
| Jetons de session | 40 octets aléatoires (`Random.secure`) ; seule l'empreinte SHA-256 est stockée. |
| Codes e-mail | 6 chiffres aléatoires, empreinte seule, 10 min, 5 essais, 1 envoi/minute ; réponse identique que le compte existe ou non (mot de passe oublié). |
| Contrôle d'accès | Rôles locataire / annonceur / admin ; chaque annonce, photo, visite et conversation est vérifiée côté serveur (propriétaire ou participant). |
| Fichiers envoyés | Type vérifié par les premiers octets (JPEG, PNG, WebP), 5 Mo, 8 par annonce, nom de fichier généré par le serveur. |
| Erreurs | Message générique « Erreur interne » ; la pile d'appels reste dans la console. |
| Secrets | `.env` hors du code (permissions 600), exclus de Git et des images Docker. |
| XSS (site, mobile) | Flutter affiche du texte, pas de HTML. |

## Failles corrigées

| # | Faille | Gravité | Correction |
|---|---|---|---|
| 1 | Aucune limite de tentatives : force brute des mots de passe et des codes, spam d'inscriptions, de visites, de messages, et de l'assistant (LLM payant) | Élevée | Limitation par adresse IP (`securite_http.dart`) : connexion 10/5 min, comptes et codes 10/15 min, assistant 20/10 min, visites/messages/signalements 30/10 min, API 300/min. Blocage d'un compte 15 min après 8 mots de passe erronés. |
| 2 | Service IA ouvert à tous (CORS `*`, aucun contrôle) : n'importe qui pouvait consommer l'agent | Élevée | Secret partagé `IA_CLE_INTERNE` (en-tête `X-Cle-Interne`, comparaison en temps constant) ; CORS fermé ; `/docs` désactivé en production ; historique limité. |
| 3 | Comptes de démonstration avec le mot de passe « password » recréés si la base est vide | Élevée | Mot de passe « password » seulement pour les tests en mémoire ou avec `BABILOGIS_DEMO=1` ; sinon mot de passe aléatoire inutilisable. |
| 4 | Jetons de session sans expiration | Moyenne | Expiration après 30 jours (colonne `jeton_expire_le`). |
| 5 | Taille des requêtes illimitée (saturation mémoire) | Moyenne | 8 Mo maximum (en-tête Content-Length **et** lecture bornée du corps). |
| 6 | CORS `*` pour toutes les origines | Moyenne | `CORS_ORIGINES` : liste des sites autorisés en production. |
| 7 | Pas d'en-têtes de sécurité | Moyenne | `X-Content-Type-Options`, `X-Frame-Options: DENY`, `Referrer-Policy`, `Permissions-Policy`, `Cross-Origin-Opener-Policy`, HSTS en production. |
| 8 | Indice sur les comptes existants par le temps de réponse à la connexion | Faible | Calcul de hachage identique si le compte n'existe pas. |
| 9 | Champs libres sans longueur maximale (nom de visite, détails de signalement, recherche, historique de l'assistant, nombre de filtres) | Faible | Longueurs bornées. |
| 10 | Journal des requêtes avec les paramètres d'adresse (e-mail dans `?email=`) | Faible | Journal sans paramètres. |
| 11 | Mobile Android : HTTP en clair autorisé partout | Moyenne | `network_security_config.xml` : HTTPS obligatoire, HTTP seulement vers l'ordinateur de développement. |
| 12 | Desktop : noms saisis interprétés comme du HTML dans certaines étiquettes et notifications | Faible | Échappement HTML et texte brut pour les notifications. |
| 13 | Desktop : connexions HTTPS impossibles sur le Python de macOS (certificats) | Fonctionnel | Contexte SSL avec certifi ou le magasin du système ; vérification toujours active. |

## Variables de production

```
BABILOGIS_PRODUCTION=1     # HSTS, /docs du service IA désactivé (déjà dans les Dockerfile)
CONFIANCE_PROXY=1          # IP du client lue dans X-Forwarded-For (derrière Railway / Alwaysdata)
CORS_ORIGINES=https://votre-domaine
IA_CLE_INTERNE=…           # même valeur sur le serveur et le service IA (openssl rand -hex 32)
```

## Limites connues

- La limitation est en mémoire : elle repart à zéro au redémarrage et ne convient qu'à **un seul** serveur.
- Pas de Content-Security-Policy : le site Flutter charge son moteur graphique (CanvasKit) ; à ajouter après essai en ligne.
- Une seule session active par compte : se connecter sur un appareil déconnecte les autres.
- Sauvegardes : celles de l'hébergeur (volume Railway / disque Alwaysdata) ; prévoir une copie régulière de `babilogis.sqlite`.
