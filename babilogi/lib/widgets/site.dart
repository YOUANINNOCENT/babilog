import 'package:flutter/material.dart';

import '../notifications/centre.dart';
import '../notifications/navigateur.dart';
import '../session.dart';
import '../theme.dart';

/// Ouvre une page du site (l'adresse du navigateur suit).
void aller(BuildContext context, String route, {bool remplacer = false}) {
  final nav = Navigator.of(context);
  if (remplacer) {
    nav.pushReplacementNamed(route);
  } else {
    nav.pushNamed(route);
  }
}

void message(BuildContext context, String texte, {bool erreur = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(texte),
      backgroundColor: erreur ? Couleurs.danger : Couleurs.texte,
    ));
}

/// Largeur maximale du contenu, centré, avec marges latérales.
class Contenu extends StatelessWidget {
  const Contenu({super.key, required this.child, this.maxWidth = 1200, this.vertical = 0});

  final Widget child;
  final double maxWidth;
  final double vertical;

  @override
  Widget build(BuildContext context) {
    final etroit = MediaQuery.sizeOf(context).width < 700;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: etroit ? 16 : 24, vertical: vertical),
          child: child,
        ),
      ),
    );
  }
}

/// Gabarit commun : en-tête, contenu défilant, pied de page.
class SiteScaffold extends StatelessWidget {
  const SiteScaffold({super.key, required this.child, this.actif = '', this.piedDePage = true});

  final Widget child;
  final String actif; // rechercher | barometre | assistant | messages | publier | espace | admin
  final bool piedDePage;

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= 960;
    return Scaffold(
      endDrawer: large ? null : _Tiroir(actif: actif),
      body: Column(
        children: [
          EnTete(actif: actif, large: large),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [child, if (piedDePage) const PiedDePage()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Logo extends StatelessWidget {
  const Logo({super.key, this.taille = 34});

  final double taille;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'BabiLogis, accueil',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: taille,
                height: taille,
                decoration: BoxDecoration(color: Couleurs.brand, borderRadius: BorderRadius.circular(taille * .28)),
                child: Icon(Icons.home_outlined, color: Colors.white, size: taille * .62),
              ),
              const SizedBox(width: 10),
              const Text('BabiLogis', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.3)),
            ],
          ),
        ),
      ),
    );
  }
}

class EnTete extends StatelessWidget {
  const EnTete({super.key, required this.actif, required this.large});

  final String actif;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final u = session.utilisateur;
    return Material(
      color: Colors.white,
      child: Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Couleurs.bordure))),
        child: Contenu(
          child: SizedBox(
            height: 76,
            child: Row(
              children: [
                const Logo(),
                if (large) ...[
                  const Spacer(),
                  _LienNav('Rechercher', '/annonces', actif == 'rechercher'),
                  _LienNav('Baromètre des loyers', '/barometre', actif == 'barometre'),
                  _LienNav('Assistant IA', '/assistant', actif == 'assistant'),
                  // Un locataire connecté ne publie pas d'annonce : pas de bouton.
                  if (u == null || u.estAnnonceur)
                    _LienNav('Publier une annonce', u?.estAnnonceur == true ? '/espace/annonces/nouvelle' : '/inscription?profil=agence',
                        actif == 'publier'),
                  const Spacer(),
                  if (u == null) ...[
                    OutlinedButton(onPressed: () => aller(context, '/connexion'), child: const Text('Se connecter')),
                    const SizedBox(width: 10),
                    FilledButton(onPressed: () => aller(context, '/inscription'), child: const Text('Créer un compte')),
                  ] else ...[
                    if (u.estAdmin)
                      TextButton(onPressed: () => aller(context, '/admin/signalements'), child: const Text('Administration')),
                    if (u.estAnnonceur)
                      TextButton(onPressed: () => aller(context, '/espace'), child: const Text('Mon espace')),
                    const SizedBox(width: 4),
                    const BoutonMessages(),
                    const Cloche(),
                    const SizedBox(width: 6),
                    _MenuCompte(),
                  ],
                ] else ...[
                  const Spacer(),
                  if (u != null) ...[const BoutonMessages(), const Cloche()],
                  Builder(
                    builder: (ctx) => IconButton(
                      tooltip: 'Menu',
                      icon: const Icon(Icons.menu),
                      onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LienNav extends StatelessWidget {
  const _LienNav(this.texte, this.route, this.actif);

  final String texte, route;
  final bool actif;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextButton(
        style: TextButton.styleFrom(foregroundColor: actif ? Couleurs.primary : Couleurs.texte),
        onPressed: () => aller(context, route),
        child: Semantics(selected: actif, child: Text(texte, style: const TextStyle(fontWeight: FontWeight.w600))),
      ),
    );
  }
}

class _MenuCompte extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final u = session.utilisateur!;
    return PopupMenuButton<String>(
      tooltip: 'Mon compte',
      onSelected: (v) async {
        if (v == 'sortir') {
          await session.deconnexion();
          if (context.mounted) Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(enabled: false, child: Text('${u.nom}\n${u.email}', style: const TextStyle(color: Couleurs.texte2))),
        const PopupMenuItem(value: 'sortir', child: Text('Se déconnecter')),
      ],
      child: CircleAvatar(
        radius: 20,
        backgroundColor: Couleurs.primary,
        child: Text(u.initiales, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _Tiroir extends StatelessWidget {
  const _Tiroir({required this.actif});

  final String actif;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final u = session.utilisateur;
    Widget lien(String t, String r, bool a) => ListTile(
          title: Text(t, style: TextStyle(fontWeight: FontWeight.w700, color: a ? Couleurs.primary : Couleurs.texte)),
          selected: a,
          onTap: () {
            Navigator.of(context).pop();
            aller(context, r);
          },
        );
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Align(alignment: Alignment.centerLeft, child: Logo()),
            const SizedBox(height: 16),
            lien('Rechercher', '/annonces', actif == 'rechercher'),
            lien('Baromètre des loyers', '/barometre', actif == 'barometre'),
            lien('Assistant IA', '/assistant', actif == 'assistant'),
            if (u == null || u.estAnnonceur)
              lien('Publier une annonce', u?.estAnnonceur == true ? '/espace/annonces/nouvelle' : '/inscription?profil=agence',
                  actif == 'publier'),
            if (u?.estAnnonceur == true) lien('Mon espace', '/espace', actif == 'espace'),
            if (u != null) lien('Messages', '/messages', actif == 'messages'),
            if (u?.estAdmin == true) lien('Administration', '/admin/signalements', actif == 'admin'),
            const Divider(height: 32),
            if (u == null) ...[
              OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    aller(context, '/connexion');
                  },
                  child: const Text('Se connecter')),
              const SizedBox(height: 10),
              FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    aller(context, '/inscription');
                  },
                  child: const Text('Créer un compte')),
            ] else
              OutlinedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await session.deconnexion();
                  if (context.mounted) Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
                },
                child: Text('Se déconnecter (${u.nom})'),
              ),
          ],
        ),
      ),
    );
  }
}

class PiedDePage extends StatelessWidget {
  const PiedDePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Couleurs.bordure))),
      child: const Contenu(
        vertical: 26,
        child: SizedBox(width: double.infinity, child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 8,
          spacing: 24,
          children: [
            Text('BabiLogis — projet de soutenance Développeur Data IA', style: TextStyle(color: Couleurs.texte2, fontSize: 14)),
            Text('Les estimations sont indicatives.', style: TextStyle(color: Couleurs.texte2, fontSize: 14)),
          ],
        )),
      ),
    );
  }
}


/// Icône « Messages » avec le nombre de messages non lus.
class BoutonMessages extends StatelessWidget {
  const BoutonMessages({super.key});

  @override
  Widget build(BuildContext context) {
    final centre = CentreNotifications.instance;
    return ListenableBuilder(
      listenable: centre,
      builder: (context, _) => IconButton(
        tooltip: centre.messagesNonLus > 0 ? 'Messages (${centre.messagesNonLus} non lus)' : 'Messages',
        onPressed: () => aller(context, '/messages'),
        icon: Badge(
          isLabelVisible: centre.messagesNonLus > 0,
          label: Text('${centre.messagesNonLus}'),
          backgroundColor: Couleurs.primary,
          child: const Icon(Icons.chat_bubble_outline),
        ),
      ),
    );
  }
}

/// Cloche des notifications (demandes de visite, réponses, nouveaux messages).
class Cloche extends StatelessWidget {
  const Cloche({super.key});

  @override
  Widget build(BuildContext context) {
    final centre = CentreNotifications.instance;
    return ListenableBuilder(
      listenable: centre,
      builder: (context, _) => IconButton(
        tooltip: centre.nonLues > 0 ? 'Notifications (${centre.nonLues} non lues)' : 'Notifications',
        onPressed: () => showDialog<void>(context: context, builder: (_) => const _PanneauNotifications()),
        icon: Badge(
          isLabelVisible: centre.nonLues > 0,
          label: Text('${centre.nonLues}'),
          backgroundColor: Couleurs.primary,
          child: const Icon(Icons.notifications_none),
        ),
      ),
    );
  }
}

class _PanneauNotifications extends StatefulWidget {
  const _PanneauNotifications();

  @override
  State<_PanneauNotifications> createState() => _PanneauNotificationsState();
}

class _PanneauNotificationsState extends State<_PanneauNotifications> {
  String _permission = permissionNotifications;

  IconData _icone(String type) => switch (type) {
        'visite' => Icons.event_available,
        'visite_reponse' => Icons.event_note,
        'message' => Icons.chat_bubble_outline,
        _ => Icons.notifications_none,
      };

  @override
  Widget build(BuildContext context) {
    final centre = CentreNotifications.instance;
    return ListenableBuilder(
      listenable: centre,
      builder: (context, _) => AlertDialog(
        title: Row(children: [
          const Expanded(child: Text('Notifications')),
          if (centre.nonLues > 0) TextButton(onPressed: centre.toutMarquerLu, child: const Text('Tout marquer comme lu')),
        ]),
        content: SizedBox(
          width: 480,
          height: 440,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (notificationsDisponibles && _permission != 'granted')
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Couleurs.primarySoft, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Expanded(
                    child: Text('Recevez une alerte sur votre ordinateur à chaque demande de visite ou nouveau message.',
                        style: TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _permission == 'denied'
                        ? null
                        : () async {
                            final p = await demanderPermissionNotifications();
                            if (mounted) setState(() => _permission = p);
                          },
                    child: Text(_permission == 'denied' ? 'Bloquées' : 'Activer'),
                  ),
                ]),
              ),
            Expanded(
              child: centre.liste.isEmpty
                  ? const Center(child: Text('Aucune notification pour le moment.', style: TextStyle(color: Couleurs.texte2)))
                  : ListView.separated(
                      itemCount: centre.liste.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final n = centre.liste[i];
                        return ListTile(
                          leading: Icon(_icone(n.type), color: n.lue ? Couleurs.texte2 : Couleurs.primary),
                          title: Text(n.titre, style: TextStyle(fontWeight: n.lue ? FontWeight.w500 : FontWeight.w800)),
                          subtitle: Text('${n.texte}\n${n.quand}'),
                          isThreeLine: true,
                          onTap: () {
                            centre.marquerLue(n);
                            Navigator.of(context).pop();
                            final lien = n.lien;
                            if (lien != null && lien.isNotEmpty) aller(context, lien);
                          },
                        );
                      },
                    ),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fermer'))],
      ),
    );
  }
}
