#!/bin/sh
# Met à jour le site + l'API sur alwaysdata en une commande (à lancer sur le Mac) :
#   1. reconstruit le dossier d'envoi (site Flutter Web + serveur Dart Linux)
#   2. l'envoie sur alwaysdata (le mot de passe SSH est demandé)
# Ensuite : alwaysdata → Web → Sites → Redémarrer.  La base et les photos (~/babilogis_donnees) ne sont jamais touchées.
set -e
ICI="$(cd "$(dirname "$0")" && pwd)"
sh "$ICI/preparer.sh"
echo "Envoi vers alwaysdata…"
rsync -avz --delete "$ICI/envoi/" youan@ssh-youan.alwaysdata.net:babilogis/
echo "✓ Envoyé. Dernière étape : alwaysdata → Web → Sites → Redémarrer (flèche circulaire)."
