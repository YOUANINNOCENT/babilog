#!/bin/sh
# Démarrage du serveur BabiLogis dans le conteneur (Railway).
# Les données vivantes (base SQLite, photos envoyées) sont dans le volume $DONNEES (/data) :
# elles survivent aux redéploiements.
set -e
D="${DONNEES:-/data}"
mkdir -p "$D/images"

# Premier démarrage : vraies annonces et illustrations libres de droits (sans rien écraser)
[ -f "$D/annonces_reelles.json" ] || cp /app/graines/annonces_reelles.json "$D/"
cp -Rn /app/graines/images/. "$D/images/" 2>/dev/null || true

set -- --base "$D/babilogis.sqlite" --site /app/site --port "${PORT:-8000}"
# Variable ADMIN_EMAIL (facultative) : ce compte devient administrateur
[ -n "$ADMIN_EMAIL" ] && set -- "$@" --admin "$ADMIN_EMAIL"

echo "BabiLogis : base $D/babilogis.sqlite · port ${PORT:-8000} · service IA ${IA_SERVICE_URL:-non configuré}"
exec /app/serveur "$@"
