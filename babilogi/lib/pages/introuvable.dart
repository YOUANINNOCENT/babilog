import 'package:flutter/material.dart';

import '../widgets/composants.dart';
import '../widgets/site.dart';

class PageIntrouvable extends StatelessWidget {
  const PageIntrouvable({super.key, this.texte = 'Cette page n\'existe pas ou a été déplacée.'});

  final String texte;

  @override
  Widget build(BuildContext context) => SiteScaffold(
        child: Contenu(
          vertical: 40,
          child: Vide(
            icone: Icons.search_off,
            titre: 'Page introuvable',
            texte: texte,
            action: FilledButton(onPressed: () => aller(context, '/'), child: const Text('Retour à l\'accueil')),
          ),
        ),
      );
}
