#!/bin/sh
# Démarrage de BabiLogis sur alwaysdata (site de type « Programme utilisateur »).
# Les données vivantes (base SQLite, photos envoyées) sont rangées HORS du dossier envoyé,
# dans ~/babilogis_donnees : un nouvel envoi du code ne les écrase jamais.
set -e
ICI="$(cd "$(dirname "$0")" && pwd)"
D="${DONNEES:-$HOME/babilogis_donnees}"
mkdir -p "$D/images"
[ -f "$D/annonces_reelles.json" ] || cp "$ICI/graines/annonces_reelles.json" "$D/"
# Photos de départ (25 Mo) : liens « durs » (cp -l) plutôt qu'une 2e copie, pour tenir dans les 100 Mo
# gratuits ; le serveur les voit comme de vrais fichiers. Rien n'est écrasé (-n).
cp -Rln "$ICI/graines/images/." "$D/images/" 2>/dev/null || cp -Rn "$ICI/graines/images/." "$D/images/" 2>/dev/null || true

# Le paquet Dart sqlite3 cherche « libsqlite3.so » : si le serveur n'a que « libsqlite3.so.0 »,
# on crée un lien dans ~/babilogis/lib (aucun droit administrateur nécessaire).
if ! ls /usr/lib/x86_64-linux-gnu/libsqlite3.so /usr/lib/libsqlite3.so >/dev/null 2>&1; then
  for so in /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 /usr/lib/libsqlite3.so.0; do
    if [ -f "$so" ]; then
      mkdir -p "$ICI/lib" && ln -sf "$so" "$ICI/lib/libsqlite3.so"
      export LD_LIBRARY_PATH="$ICI/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      break
    fi
  done
fi

set -- --base "$D/babilogis.sqlite" --site "$ICI/site" --port "${PORT:-8000}"
[ -n "$ADMIN_EMAIL" ] && set -- "$@" --admin "$ADMIN_EMAIL"
exec "$ICI/serveur" "$@"
