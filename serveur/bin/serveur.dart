import 'dart:async';
import 'dart:io';

import 'package:babilogis_serveur/babilogis_serveur.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';

/// Lance le serveur BabiLogis.
///
///   dart run bin/serveur.dart                 → http://127.0.0.1:8000
///   dart run bin/serveur.dart --port 9000
///   dart run bin/serveur.dart --reinitialiser  (efface la base et recharge la démo)
///   dart run bin/serveur.dart --admin votre@adresse.com  (ce compte devient administrateur)
///
/// Il sert l'API (/api/...) et, si le site a été construit
/// (flutter build web dans ../babilogi), le site web lui-même.
Future<void> main(List<String> args) async {
  String? option(String nom) {
    final i = args.indexOf(nom);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final dossier = File.fromUri(Platform.script).parent.parent.path;
  final port = int.tryParse(option('--port') ?? Platform.environment['PORT'] ?? '') ?? 8000;
  final chemin = option('--base') ?? '$dossier/donnees/babilogis.sqlite';
  final site = option('--site') ?? '$dossier/../babilogi/build/web';

  if (args.contains('--reinitialiser') && File(chemin).existsSync()) {
    File(chemin).deleteSync();
    stdout.writeln('Base effacée : les annonces vont être rechargées (vraies annonces si donnees/annonces_reelles.json existe).');
  }

  final base = Base.ouvrir(chemin);
  final admin = option('--admin');
  if (admin != null) {
    stdout.writeln(base.nommerAdministrateur(admin)
        ? 'Administrateur : $admin a maintenant accès à la page Administration.'
        : 'Administrateur : aucun compte pour $admin (créez-le d\'abord depuis le site ou l\'application).');
  }
  // Identifiants SMTP : variables d'environnement, sinon fichier serveur/.env (non partagé).
  final env = {...lireFichierEnv('$dossier/.env'), ...Platform.environment};
  final api = Api(base, courriel: courrielDepuisEnvironnement(env)).routeur;

  // Site web : fichiers construits par Flutter, et index.html pour toutes les
  // autres adresses (/annonces/BL-1001, /espace…) : c'est le site qui choisit la page.
  Handler? siteWeb;
  if (File('$site/index.html').existsSync()) {
    final fichiers = createStaticHandler(site, defaultDocument: 'index.html');
    final index = File('$site/index.html');
    siteWeb = (Request q) async {
      final r = await fichiers(q);
      if (r.statusCode != 404) return r;
      return Response.ok(index.openRead(), headers: {'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-cache'});
    };
  }

  // Images (illustrations libres de droits et photos des annonceurs) : donnees/images
  final dossierImages = base.dossierImages ?? '$dossier/donnees/images';
  Directory(dossierImages).createSync(recursive: true);
  final images = createStaticHandler(dossierImages);

  Future<Response> routeur(Request q) async {
    if (q.url.path == 'api' || q.url.path.startsWith('api/')) return api.call(q);
    if (q.url.path.startsWith('images/')) {
      final r = await images(q.change(path: 'images'));
      return r.statusCode == 200 ? r.change(headers: {'cache-control': 'public, max-age=86400'}) : r;
    }
    if (siteWeb != null) return siteWeb(q);
    return Response.ok(
      '<!DOCTYPE html><meta charset="utf-8"><title>BabiLogis</title>'
      '<body style="font-family:system-ui;max-width:640px;margin:60px auto;padding:0 16px">'
      '<h1 style="color:#CC0000">BabiLogis</h1><p>L\'API fonctionne : <a href="/api/annonces">/api/annonces</a>.</p>'
      '<p>Pour le site : <code>cd ../babilogi &amp;&amp; flutter run -d chrome</code>, '
      'ou <code>flutter build web</code> puis relancez ce serveur.</p></body>',
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
  }

  // Sécurité : en-têtes, CORS limité (CORS_ORIGINES), limitation par IP, taille des requêtes,
  // journal sans paramètres d'adresse (ils peuvent contenir un e-mail).
  final securite = ConfigSecurite.depuis(env);
  final handler = const Pipeline()
      .addMiddleware(journal())
      .addMiddleware(entetesSecurite(securite))
      .addMiddleware(cors(securite))
      .addMiddleware(tailleMax())
      .addMiddleware(limiteur(securite))
      .addHandler(routeur);
  // IPv4 et IPv6 (réseau privé Railway) : anyIPv6 accepte aussi l'IPv4 (v6Only à false).
  final serveur = await io.serve(handler, InternetAddress.anyIPv6, port);
  serveur.autoCompress = true;

  stdout.writeln('');
  stdout.writeln('✓ BabiLogis est lancé : http://127.0.0.1:$port');
  stdout.writeln('  API    : http://127.0.0.1:$port/api/annonces');
  stdout.writeln('  Site   : ${siteWeb != null ? 'http://127.0.0.1:$port' : 'pas encore construit (flutter build web dans ../babilogi)'}');
  stdout.writeln('  Base   : $chemin');
  final nbReelles = base.nbAnnoncesReelles;
  stdout.writeln(nbReelles > 0
      ? '  Données : $nbReelles vraies annonces (Blocs 1 et 2) · vrais comptes uniquement (comptes de démo supprimés)\n'
          '  Comptes : ${base.valeur("SELECT COUNT(*) FROM utilisateurs WHERE email <> 'collecte@babilogis.ci'")} · '
          'administrateurs : ${base.valeur("SELECT COUNT(*) FROM utilisateurs WHERE role = 'admin'")}'
          '${base.valeur("SELECT COUNT(*) FROM utilisateurs WHERE role = 'admin'") == 0 ? ' (ajoutez --admin votre@adresse.com)' : ''}'
      : '  Données : démonstration (relancez avec --reinitialiser pour charger donnees/annonces_reelles.json)');
  stdout.writeln('  E-mails : ${(env['SMTP_UTILISATEUR'] ?? '').isEmpty ? 'affichés dans cette console (SMTP_UTILISATEUR absent de .env)' : 'envoyés par SMTP (${env['SMTP_UTILISATEUR']}) · comptes de démo @babilogis.ci : affichés ici'}');
  stdout.writeln('  Service IA : ${Api.urlIa.isEmpty ? 'désactivé' : Api.urlIa}');
  final nbIllus = base.nbIllustrations;
  stdout.writeln(nbIllus > 0
      ? '  Photos : $nbIllus illustrations libres de droits (donnees/images)'
      : '  Photos : aucune illustration (lancez : python3 outils/collecter_images.py)');
  stdout.writeln('  Sécurité : ${securite.production ? 'production (HSTS)' : 'développement'} · CORS '
      '${securite.originesAutorisees.isEmpty ? 'toutes origines' : securite.originesAutorisees.join(', ')}'
      '${securite.confianceProxy ? ' · IP client via le proxy' : ''}');
  stdout.writeln('  Ctrl + C pour arrêter.');

  // Déploiement : quand un nouveau programme compilé remplace celui-ci, le serveur s'arrête de lui-même
  // et l'hébergeur (alwaysdata) le relance à la requête suivante avec la nouvelle version.
  final executable = File(Platform.resolvedExecutable);
  if (!executable.path.endsWith('dart') && executable.existsSync()) {
    final date = executable.lastModifiedSync();
    Timer.periodic(const Duration(seconds: 15), (_) async {
      try {
        if (executable.existsSync() && executable.lastModifiedSync() != date) {
          stdout.writeln('Nouvelle version du serveur détectée : redémarrage.');
          await serveur.close();
          base.fermer();
          exit(0);
        }
      } on FileSystemException {
        // Fichier en cours de remplacement : on réessaiera au prochain tour.
      }
    });
  }

  ProcessSignal.sigint.watch().listen((_) async {
    await serveur.close(force: true);
    base.fermer();
    exit(0);
  });
}
