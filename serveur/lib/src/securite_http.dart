/// Protections HTTP du serveur BabiLogis (avant la mise en ligne) :
/// en-têtes de sécurité, CORS limité, limitation du nombre de requêtes par adresse IP,
/// taille maximale des requêtes et journal sans données personnelles.
library;

import 'dart:io';

import 'package:shelf/shelf.dart';

/// Taille maximale d'une requête : une photo de 5 Mo encodée en base64 (≈ 6,7 Mo) + marge.
const tailleMaxRequete = 8 * 1024 * 1024;

/// Configuration lue dans l'environnement (variables Railway / Alwaysdata ou serveur/.env).
class ConfigSecurite {
  ConfigSecurite.depuis(Map<String, String> env)
      : originesAutorisees = (env['CORS_ORIGINES'] ?? '')
            .split(',')
            .map((o) => o.trim().replaceAll(RegExp(r'/$'), ''))
            .where((o) => o.isNotEmpty)
            .toSet(),
        confianceProxy = env['CONFIANCE_PROXY'] == '1',
        production = env['BABILOGIS_PRODUCTION'] == '1';

  /// Sites autorisés à appeler l'API depuis un navigateur (vide = tous : développement).
  final Set<String> originesAutorisees;

  /// Derrière l'hébergeur (Railway, Alwaysdata) : l'IP du client est dans X-Forwarded-For.
  final bool confianceProxy;

  /// En ligne : HSTS, et l'origine « * » n'est jamais renvoyée si une liste est fournie.
  final bool production;
}

/// En-têtes de sécurité ajoutés à toutes les réponses.
Middleware entetesSecurite(ConfigSecurite c) => (Handler suivant) => (Request q) async {
      final r = await suivant(q);
      return r.change(headers: {
        'x-content-type-options': 'nosniff',
        'x-frame-options': 'DENY',
        'referrer-policy': 'strict-origin-when-cross-origin',
        'permissions-policy': 'camera=(), geolocation=(), microphone=(self)',
        'cross-origin-opener-policy': 'same-origin',
        if (c.production) 'strict-transport-security': 'max-age=31536000; includeSubDomains',
      });
    };

/// CORS : le site servi par le serveur n'en a pas besoin (même adresse) ; les autres origines
/// (site lancé avec « flutter run », mobile dans Chrome) doivent être dans CORS_ORIGINES.
Middleware cors(ConfigSecurite c) {
  const base = {
    'access-control-allow-methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    'access-control-allow-headers': 'Origin, Content-Type, Accept, Authorization',
    'access-control-max-age': '86400',
  };
  Map<String, String> pour(Request q) {
    final origine = q.headers['origin'];
    if (c.originesAutorisees.isEmpty) return {...base, 'access-control-allow-origin': '*'};
    if (origine != null && c.originesAutorisees.contains(origine)) {
      return {...base, 'access-control-allow-origin': origine, 'vary': 'Origin'};
    }
    return const {'vary': 'Origin'};
  }

  return (Handler suivant) => (Request q) async {
        if (q.method == 'OPTIONS') return Response.ok('', headers: pour(q));
        final r = await suivant(q);
        return r.change(headers: pour(q));
      };
}

/// Adresse IP du client (celle transmise par l'hébergeur si CONFIANCE_PROXY=1).
String ipClient(Request q, ConfigSecurite c) {
  if (c.confianceProxy) {
    final transmise = q.headers['x-forwarded-for'];
    if (transmise != null && transmise.trim().isNotEmpty) return transmise.split(',').first.trim();
  }
  final info = q.context['shelf.io.connection_info'];
  return info is HttpConnectionInfo ? info.remoteAddress.address : 'inconnue';
}

/// Règle de limitation : au plus [maximum] requêtes par [fenetre] et par IP.
class _Regle {
  const _Regle(this.nom, this.maximum, this.fenetre, this.correspond);
  final String nom;
  final int maximum;
  final Duration fenetre;
  final bool Function(String methode, String chemin) correspond;
}

final _regles = <_Regle>[
  _Regle('connexion', 10, const Duration(minutes: 5), (m, p) => m == 'POST' && p == 'api/connexion'),
  _Regle('comptes', 10, const Duration(minutes: 15),
      (m, p) => m == 'POST' && (p == 'api/inscription' || p.startsWith('api/verification') || p.startsWith('api/mot-de-passe'))),
  _Regle('assistant', 20, const Duration(minutes: 10), (m, p) => m == 'POST' && p == 'api/assistant'),
  _Regle('demandes', 30, const Duration(minutes: 10),
      (m, p) => m == 'POST' && (p == 'api/visites' || p == 'api/signalements' || p.startsWith('api/conversations'))),
  _Regle('photos', 40, const Duration(minutes: 10), (m, p) => m == 'POST' && p.endsWith('/photos')),
  _Regle('api', 300, const Duration(minutes: 1), (m, p) => p.startsWith('api/')),
];

/// Limitation simple en mémoire (un seul serveur) : 429 « Trop de requêtes » au-delà.
Middleware limiteur(ConfigSecurite c, {DateTime Function()? horloge}) {
  final maintenant = horloge ?? DateTime.now;
  final compteurs = <String, List<DateTime>>{};
  var derniereVidange = maintenant();
  return (Handler suivant) => (Request q) async {
        final chemin = q.url.path;
        final t = maintenant();
        // Nettoyage périodique (mémoire bornée)
        if (t.difference(derniereVidange) > const Duration(minutes: 10)) {
          compteurs.removeWhere((_, v) => v.isEmpty || t.difference(v.last) > const Duration(minutes: 30));
          derniereVidange = t;
        }
        final ip = ipClient(q, c);
        for (final r in _regles) {
          if (!r.correspond(q.method, chemin)) continue;
          final cle = '${r.nom}|$ip';
          final liste = compteurs.putIfAbsent(cle, () => []);
          liste.removeWhere((d) => t.difference(d) > r.fenetre);
          if (liste.length >= r.maximum) {
            final attente = r.fenetre - t.difference(liste.first);
            return Response(429,
                body: '{"message":"Trop de tentatives. Réessayez dans ${(attente.inSeconds / 60).ceil()} minute(s)."}',
                headers: {
                  'content-type': 'application/json; charset=utf-8',
                  'retry-after': '${attente.inSeconds.clamp(1, 3600)}',
                });
          }
          liste.add(t);
        }
        return suivant(q);
      };
}

/// Refuse les requêtes trop lourdes annoncées par Content-Length (413).
Middleware tailleMax() => (Handler suivant) => (Request q) async {
      final n = q.contentLength;
      if (n != null && n > tailleMaxRequete) {
        return Response(413,
            body: '{"message":"Requête trop volumineuse (8 Mo maximum)."}',
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return suivant(q);
    };

/// Journal des requêtes sans paramètres d'adresse (ils peuvent contenir un e-mail).
Middleware journal() => (Handler suivant) => (Request q) async {
      final debut = DateTime.now();
      final r = await suivant(q);
      final ms = DateTime.now().difference(debut).inMilliseconds;
      stdout.writeln('${debut.toIso8601String().substring(11, 19)}  ${r.statusCode}  ${q.method.padRight(6)} /${q.url.path}  ${ms}ms');
      return r;
    };
