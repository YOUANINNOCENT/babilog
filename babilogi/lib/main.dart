import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'pages/accueil.dart';
import 'pages/admin.dart';
import 'pages/annonce.dart';
import 'pages/assistant.dart';
import 'pages/barometre.dart';
import 'pages/compte.dart';
import 'pages/mot_de_passe.dart';
import 'pages/espace.dart';
import 'pages/formulaire.dart';
import 'pages/introuvable.dart';
import 'pages/messages.dart';
import 'pages/recherche.dart';
import 'notifications/centre.dart';
import 'session.dart';
import 'theme.dart';

/// BabiLogis — site web en Flutter (Dart). L'API et la base de données
/// sont dans le serveur Dart (dossier ../serveur).
void main() {
  usePathUrlStrategy(); // adresses propres : /annonces/BL-1001 (sans #)
  final session = Session()..charger();
  CentreNotifications.instance.suivre(session); // notifications : visites, réponses, messages
  runApp(BabiLogisWeb(session: session));
}

class BabiLogisWeb extends StatelessWidget {
  const BabiLogisWeb({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      session: session,
      child: MaterialApp(
        title: 'BabiLogis — Le bon logement, au juste prix',
        debugShowCheckedModeBanner: false,
        theme: themeBabiLogis(),
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        initialRoute: '/',
        onGenerateRoute: (settings) => MaterialPageRoute(
          settings: settings,
          builder: (_) => _Routeur(nom: settings.name ?? '/'),
        ),
      ),
    );
  }
}

/// Associe une adresse à une page, et protège l'espace annonceur et l'administration.
class _Routeur extends StatelessWidget {
  const _Routeur({required this.nom});

  final String nom;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final uri = Uri.parse(nom);
    final s = uri.pathSegments.where((e) => e.isNotEmpty).toList();
    final q = uri.queryParameters;

    Widget protege(bool autorise, Widget page) {
      if (!session.pret) {
        return const Scaffold(body: Center(child: CircularProgressIndicator(color: Couleurs.primary)));
      }
      if (!session.connecte) return PageConnexion(suite: nom);
      if (!autorise) return const PageIntrouvable(texte: 'Cette page est réservée à un autre type de compte.');
      return page;
    }

    final u = session.utilisateur;
    return switch (s) {
      [] => const PageAccueil(),
      ['annonces'] => PageRecherche(uri: uri),
      ['annonces', final ref] => PageAnnonce(reference: ref),
      ['assistant'] => const PageAssistant(),
      ['barometre'] => PageBarometre(pieces: int.tryParse(q['pieces'] ?? '')),
      ['connexion'] => PageConnexion(suite: q['suite']),
      ['inscription'] => PageInscription(profil: q['profil']),
      ['mot-de-passe-oublie'] => PageMotDePasseOublie(email: q['email']),
      ['verification'] => PageVerification(email: q['email'] ?? '', suite: q['suite']),
      ['espace'] => protege(u?.estAnnonceur == true, const PageEspace()),
      ['espace', 'annonces', 'nouvelle'] => protege(u?.estAnnonceur == true, const PageFormulaire()),
      ['espace', 'annonces', final ref, 'modifier'] => protege(u?.estAnnonceur == true, PageFormulaire(reference: ref)),
      ['messages'] => protege(true, const PageMessages()),
      ['messages', final id] => protege(true, PageMessages(conversationId: int.tryParse(id))),
      ['admin', 'signalements'] => protege(u?.estAdmin == true, PageAdmin(vue: q['vue'] ?? 'a_traiter')),
      _ => const PageIntrouvable(),
    };
  }
}
