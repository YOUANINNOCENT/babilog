#!/usr/bin/env bash
# Lance toutes les applications BabiLogis, chacune dans sa fenêtre du Terminal macOS.
#
#   bash ~/Desktop/babilog/lancer_tout.sh            → tout : serveur, service IA, site, app mobile, app desktop
#   bash ~/Desktop/babilog/lancer_tout.sh site       → serveur + service IA + site web
#   bash ~/Desktop/babilog/lancer_tout.sh mobile     → serveur + service IA + app mobile
#   bash ~/Desktop/babilog/lancer_tout.sh desktop    → serveur + service IA + app desktop
#
# Pour tout arrêter : Ctrl + C dans chaque fenêtre (ou relancez ce script : il libère les ports).
RACINE="$HOME/Desktop/babilog"
MOBILE="$HOME/Desktop/logibabi/babilogi"
DESKTOP="$HOME/Desktop/babilogi_desk"
CHOIX="${1:-tout}"

# Libère les ports si une ancienne version tourne encore (serveur 8000, service IA 8001)
lsof -ti :8000 | xargs kill 2>/dev/null
lsof -ti :8001 | xargs kill 2>/dev/null

ouvrir() {
  osascript -e "tell application \"Terminal\" to do script \"cd '$1' && $2\"" >/dev/null
}

ouvrir "$RACINE/serveur" "dart run bin/serveur.dart"
ouvrir "$RACINE/ia_service" "bash lancer.sh"
sleep 6   # le temps que le serveur démarre

case "$CHOIX" in
  site)    ouvrir "$RACINE/babilogi" "flutter run -d chrome --web-port 5000" ;;
  mobile)  ouvrir "$MOBILE" "flutter run -d chrome --web-port 5001" ;;
  desktop) ouvrir "$DESKTOP" "bash lancer.sh" ;;
  *)
    ouvrir "$RACINE/babilogi" "flutter run -d chrome --web-port 5000"
    ouvrir "$MOBILE" "flutter run -d chrome --web-port 5001"
    ouvrir "$DESKTOP" "bash lancer.sh"
    ;;
esac
osascript -e 'tell application "Terminal" to activate' >/dev/null

echo "✓ BabiLogis lancé ($CHOIX)"
echo "  Serveur + API : http://127.0.0.1:8000      Service IA : http://127.0.0.1:8001/docs"
[ "$CHOIX" = tout ] || [ "$CHOIX" = site ]    && echo "  Site web      : Chrome (port 5000)"
[ "$CHOIX" = tout ] || [ "$CHOIX" = mobile ]  && echo "  App mobile    : Chrome (port 5001) — Cmd+Option+I puis icône téléphone"
[ "$CHOIX" = tout ] || [ "$CHOIX" = desktop ] && echo "  App desktop   : fenêtre BabiLogis Agence"
echo "  Pour tout arrêter : Ctrl + C dans chaque fenêtre du Terminal."
