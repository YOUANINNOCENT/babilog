#!/usr/bin/env bash
# Enregistre la clé Groq dans ia_service/.env, de façon privée :
#  - la saisie est invisible (rien à l'écran, rien dans l'historique du terminal) ;
#  - le fichier .env est lisible uniquement par votre compte (chmod 600) ;
#  - .env est ignoré par git : il ne part jamais sur GitHub.
set -e
cd "$(dirname "$0")"
umask 077
[ -f .env ] || touch .env
chmod 600 .env

printf "Collez votre clé Groq (la saisie reste invisible), puis Entrée : "
IFS= read -rs CLE
echo
CLE="$(printf '%s' "$CLE" | tr -d '[:space:]')"
case "$CLE" in
  gsk_*) ;;
  *) echo "❌ Ce n'est pas une clé Groq (elle doit commencer par gsk_). Rien n'a été modifié."; exit 1 ;;
esac

# Remplace (ou ajoute) la ligne GROQ_API_KEY sans que la clé apparaisse dans les arguments d'une commande
CLE="$CLE" python3 - <<'PY'
import os, pathlib
p = pathlib.Path(".env")
lignes = [l for l in p.read_text(encoding="utf-8").splitlines()
          if not l.startswith(("GROQ_API_KEY=", "IA_FOURNISSEUR="))]
lignes += ["IA_FOURNISSEUR=groq", "GROQ_API_KEY=" + os.environ["CLE"]]
p.write_text("\n".join(lignes) + "\n", encoding="utf-8")
PY
unset CLE
chmod 600 .env
echo "✅ Clé enregistrée dans ia_service/.env (accès réservé à votre compte). Relancez : bash lancer.sh"
