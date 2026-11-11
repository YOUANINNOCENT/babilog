#!/bin/sh
# Prépare le dossier à envoyer sur alwaysdata (à lancer sur votre Mac) :
#   site Flutter Web compilé + serveur Dart compilé pour Linux + annonces et illustrations.
# Résultat : babilog/deploiement/alwaysdata/envoi/
set -e
ICI="$(cd "$(dirname "$0")" && pwd)"
RACINE="$(cd "$ICI/../.." && pwd)"
SORTIE="$ICI/envoi"
rm -rf "$SORTIE" && mkdir -p "$SORTIE/graines"

echo "1/3 Site web (Flutter Web)…"
(cd "$RACINE/babilogi" && flutter build web --release)
cp -R "$RACINE/babilogi/build/web" "$SORTIE/site"
# Le site charge son moteur graphique (CanvasKit) depuis le CDN de Google (gstatic.com) :
# la copie locale (~36 Mo) n'est jamais téléchargée par les navigateurs. On la retire pour tenir dans les 100 Mo.
grep -q "useLocalCanvasKit:\s*true" "$SORTIE/site/index.html" "$SORTIE/site/flutter_bootstrap.js" 2>/dev/null \
  || rm -rf "$SORTIE/site/canvaskit"

echo "2/3 Serveur Dart compilé pour Linux x64 (les serveurs alwaysdata)…"
(cd "$RACINE/serveur" && dart pub get && dart compile exe bin/serveur.dart \
   --target-os=linux --target-arch=x64 -o "$SORTIE/serveur")

echo "3/3 Annonces réelles et illustrations…"
cp "$RACINE/serveur/donnees/annonces_reelles.json" "$SORTIE/graines/"
cp -R "$RACINE/serveur/donnees/images" "$SORTIE/graines/images"
cp "$ICI/demarrer.sh" "$SORTIE/demarrer.sh"
chmod +x "$SORTIE/serveur" "$SORTIE/demarrer.sh"

echo "Prêt : $SORTIE ($(du -sh "$SORTIE" | cut -f1)). Aucun fichier .env n'y est copié."
