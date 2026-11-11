/// Envoi des e-mails (codes de vérification) par Gmail SMTP.
///
/// Configuration (variables d'environnement ou fichier serveur/.env) :
///   SMTP_UTILISATEUR    adresse Gmail qui envoie (ex. babilogis@gmail.com)
///   SMTP_MOT_DE_PASSE   « mot de passe d'application » Google (16 lettres), pas le mot de passe du compte
///   SMTP_HOTE, SMTP_PORT, SMTP_SSL=1   facultatifs (smtp.gmail.com, 587 par défaut)
/// Sans identifiants (développement), l'e-mail est affiché dans la console du serveur.
library;

import 'dart:io';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

typedef EnvoiCourriel = Future<void> Function(String destinataire, String sujet, String texte);

/// Domaine des comptes de démonstration (adresses fictives : aucune boîte ne peut recevoir le message).
const domaineDemo = '@babilogis.ci';

void _afficher(String raison, String destinataire, String sujet, String texte) =>
    stdout.writeln('\n✉  E-mail ($raison) pour $destinataire\n   $sujet\n   ${texte.replaceAll('\n', '\n   ')}\n');

EnvoiCourriel courrielDepuisEnvironnement([Map<String, String>? env]) {
  env ??= Platform.environment;
  final utilisateur = env['SMTP_UTILISATEUR'] ?? '';
  final motDePasse = (env['SMTP_MOT_DE_PASSE'] ?? '').replaceAll(' ', '');
  if (utilisateur.isEmpty || motDePasse.isEmpty) {
    return (destinataire, sujet, texte) async => _afficher('SMTP non configuré', destinataire, sujet, texte);
  }
  final serveur = SmtpServer(
    env['SMTP_HOTE'] ?? 'smtp.gmail.com',
    port: int.tryParse(env['SMTP_PORT'] ?? '') ?? 587,
    ssl: env['SMTP_SSL'] == '1',
    username: utilisateur,
    password: motDePasse,
  );
  return (destinataire, sujet, texte) async {
    // Comptes de démonstration (…@babilogis.ci) : adresse fictive, le message est affiché ici.
    if (destinataire.toLowerCase().endsWith(domaineDemo)) {
      _afficher('compte de démonstration, adresse fictive', destinataire, sujet, texte);
      return;
    }
    final m = Message()
      ..from = Address(utilisateur, 'BabiLogis')
      ..recipients.add(destinataire)
      ..subject = sujet
      ..text = texte;
    await send(m, serveur, timeout: const Duration(seconds: 20));
    stdout.writeln('✉  E-mail envoyé à $destinataire (pensez aux courriers indésirables).');
  };
}

/// Lit un fichier KEY=valeur (lignes vides et # ignorées) : sert pour serveur/.env.
Map<String, String> lireFichierEnv(String chemin) {
  final f = File(chemin);
  if (!f.existsSync()) return {};
  return {
    for (final l in f.readAsLinesSync().map((l) => l.trim()).where((l) => l.isNotEmpty && !l.startsWith('#') && l.contains('=')))
      l.substring(0, l.indexOf('=')).trim(): l.substring(l.indexOf('=') + 1).trim().replaceAll(RegExp(r'''^["']|["']$'''), ''),
  };
}
