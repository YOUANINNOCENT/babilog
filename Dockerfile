# BabiLogis : site web (Flutter Web) + API (serveur Dart) dans une seule image.
# Déploiement Railway : service « api », dossier racine = babilog/, volume monté sur /data.
# Versions identiques à celles du Mac de développement (Flutter 3.47.7, Dart 3.13.5).

# ── 1. Site web ─────────────────────────────────────────────────────────────
FROM ghcr.io/cirruslabs/flutter:3.47.7 AS site
WORKDIR /src/babilogi
COPY babilogi/pubspec.yaml babilogi/pubspec.lock ./
RUN flutter pub get
COPY babilogi/ ./
RUN flutter build web --release

# ── 2. Serveur Dart compilé en exécutable natif ─────────────────────────────
FROM dart:3.13.5 AS serveur
WORKDIR /src/serveur
COPY serveur/pubspec.yaml serveur/pubspec.lock ./
RUN dart pub get
COPY serveur/ ./
RUN dart pub get --offline && mkdir -p /out && dart compile exe bin/serveur.dart -o /out/serveur

# ── 3. Image finale (légère) ────────────────────────────────────────────────
FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends libsqlite3-0 libsqlite3-dev ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=serveur /out/serveur /app/serveur
COPY --from=site /src/babilogi/build/web /app/site
# Graines copiées dans le volume au premier démarrage : vraies annonces + illustrations
COPY serveur/donnees/annonces_reelles.json /app/graines/annonces_reelles.json
COPY serveur/donnees/images /app/graines/images
COPY deploiement/demarrer.sh /app/demarrer.sh
ENV DONNEES=/data \
    BABILOGIS_PRODUCTION=1 \
    CONFIANCE_PROXY=1
CMD ["sh", "/app/demarrer.sh"]
