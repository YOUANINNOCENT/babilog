#!/usr/bin/env bash
# Lance le service IA BabiLogis sur http://127.0.0.1:8001  (docs : /docs)
set -e
cd "$(dirname "$0")"
if [ ! -d .venv ]; then
  python3 -m venv .venv
  .venv/bin/pip install -q --upgrade pip
  .venv/bin/pip install -q --only-binary=cryptography -r requirements.txt
fi
# Fichier de configuration local (jamais sur GitHub) : on le crée ou on le complète.
umask 077
[ -f .env ] || touch .env
chmod 600 .env
grep -q '^IA_FOURNISSEUR=' .env || echo 'IA_FOURNISSEUR=groq' >> .env
grep -q '^GROQ_API_KEY=' .env || echo 'GROQ_API_KEY=' >> .env
grep -q '^GROQ_MODEL=' .env || echo 'GROQ_MODEL=openai/gpt-oss-120b' >> .env
grep -q '^GEMINI_API_KEY=' .env || echo 'GEMINI_API_KEY=' >> .env
if grep -q '^GROQ_API_KEY=$' .env && grep -q '^IA_FOURNISSEUR=groq' .env; then
  echo "⚠️  Pas de clé Groq : l'agent répondra par règles. Lancez : bash configurer_cle.sh"
fi
exec .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8001 --reload
