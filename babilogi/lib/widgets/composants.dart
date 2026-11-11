import 'package:flutter/material.dart';

import '../api.dart';
import '../config.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import 'site.dart';

/// Badge de verdict : ✓ Prix juste, ↑ Au-dessus du marché, ↓ Bonne affaire.
class VerdictBadge extends StatelessWidget {
  const VerdictBadge(this.verdict, this.libelle, {super.key, this.petit = false});

  final String? verdict;
  final String libelle;
  final bool petit;

  @override
  Widget build(BuildContext context) {
    final (fg, bg, icone) = switch (verdict) {
      'juste' => (Couleurs.justeFg, Couleurs.justeBg, Icons.check),
      'au_dessus' => (Couleurs.hautFg, Couleurs.hautBg, Icons.arrow_upward),
      'bonne_affaire' => (Couleurs.basFg, Couleurs.basBg, Icons.arrow_downward),
      _ => (Couleurs.texte2, Couleurs.surfaceMuted, Icons.hourglass_empty),
    };
    return Semantics(
      label: 'Analyse du prix : ${libelle.isEmpty ? 'en cours' : libelle}',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: petit ? 9 : 11, vertical: petit ? 3 : 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: petit ? 13 : 15, color: fg),
            const SizedBox(width: 5),
            Text(libelle.isEmpty ? 'En cours d\'analyse' : libelle,
                style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: petit ? 12.5 : 13.5)),
          ],
        ),
      ),
    );
  }
}

class Pastille extends StatelessWidget {
  const Pastille(this.texte, {super.key, this.fg = Colors.white, this.bg = Couleurs.primary});

  final String texte;
  final Color fg, bg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(texte, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12.5)),
      );
}

/// Photo de démonstration (maison au trait sur fond gris).
class PhotoVide extends StatelessWidget {
  const PhotoVide({super.key, this.hauteur = 182, this.rayon = 0, this.taille = 42});

  final double hauteur, rayon, taille;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          height: hauteur,
          decoration: BoxDecoration(color: Couleurs.placeholder, borderRadius: BorderRadius.circular(rayon)),
          alignment: Alignment.center,
          child: Icon(Icons.home_outlined, size: taille, color: const Color(0xFF6F6F6F)),
        ),
      );
}

/// Photo d'annonce (réseau), avec repli sur [PhotoVide] et mention « Illustration ».
class Photo extends StatelessWidget {
  const Photo(this.photo, {super.key, this.hauteur = 182, this.rayon = 0, this.taille = 42, this.mention = true});

  final PhotoAnnonce? photo;
  final double hauteur, rayon, taille;
  final bool mention;

  @override
  Widget build(BuildContext context) {
    final p = photo;
    if (p == null) return PhotoVide(hauteur: hauteur, rayon: rayon, taille: taille);
    return ClipRRect(
      borderRadius: BorderRadius.circular(rayon),
      child: SizedBox(
        height: hauteur,
        width: double.infinity,
        child: Stack(fit: StackFit.expand, children: [
          Image.network(
            urlImage(p.url),
            fit: BoxFit.cover,
            semanticLabel: p.illustration ? 'Photo d\'illustration' : 'Photo du logement',
            errorBuilder: (_, _, _) => PhotoVide(hauteur: hauteur, taille: taille),
            loadingBuilder: (context, enfant, progression) =>
                progression == null ? enfant : Container(color: Couleurs.placeholder),
          ),
          if (p.illustration && mention)
            Positioned(
              left: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: .62), borderRadius: BorderRadius.circular(6)),
                child: const Text('Photo d\'illustration', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
        ]),
      ),
    );
  }
}

class Prix extends StatelessWidget {
  const Prix(this.montant, {super.key, this.taille = 21});

  final int montant;
  final double taille;

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(children: [
          TextSpan(text: fcfa(montant), style: TextStyle(fontSize: taille, fontWeight: FontWeight.w800)),
          const TextSpan(text: ' / mois', style: TextStyle(fontSize: 14, color: Couleurs.texte2)),
        ]),
      );
}

/// Carte d'annonce (même dessin que la maquette de l'accueil).
class CarteAnnonce extends StatelessWidget {
  const CarteAnnonce(this.a, {super.key});

  final Annonce a;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${a.titre}, ${a.lieu}, ${fcfa(a.loyer)} par mois, ${a.verdictLibelle}',
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Couleurs.bordure),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => aller(context, '/annonces/${a.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  Photo(a.photos.isEmpty ? null : a.photos.first),
                  if (a.ageJours <= 1) const Positioned(top: 12, left: 12, child: Pastille('Nouveau')),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    VerdictBadge(a.verdict, a.verdictLibelle, petit: true),
                    const SizedBox(height: 10),
                    Text(a.titre, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(a.details, style: const TextStyle(color: Couleurs.texte2), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 12),
                    Prix(a.loyer),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grille responsive : 1 à [max] colonnes selon la largeur disponible.
class Grille extends StatelessWidget {
  const Grille({super.key, required this.enfants, this.largeurMin = 250, this.max = 4, this.espace = 22});

  final List<Widget> enfants;
  final double largeurMin, espace;
  final int max;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final n = ((c.maxWidth + espace) / (largeurMin + espace)).floor().clamp(1, max).toInt();
      final largeur = (c.maxWidth - espace * (n - 1)) / n;
      return Wrap(
        spacing: espace,
        runSpacing: espace,
        children: [for (final e in enfants) SizedBox(width: largeur, child: e)],
      );
    });
  }
}

/// Jauge : zones bonne affaire / juste / au-dessus et repère du loyer.
class JaugePrix extends StatelessWidget {
  const JaugePrix({super.key, required this.loyer, required this.minimum, required this.maximum});

  final int loyer, minimum, maximum;

  @override
  Widget build(BuildContext context) {
    final bas = (minimum < loyer ? minimum : loyer) * 0.88;
    final haut = (maximum > loyer ? maximum : loyer) * 1.12;
    double p(num v) => ((v - bas) / (haut - bas)).clamp(0.0, 1.0).toDouble();
    return Semantics(
      label: 'Loyer demandé ${fcfa(loyer)}, fourchette estimée de ${fcfa(minimum)} à ${fcfa(maximum)}',
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        final x = p(loyer) * w;
        return SizedBox(
          height: 66,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 26,
                left: 0,
                right: 0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: Row(children: [
                    Expanded(flex: (p(minimum) * 1000).round().clamp(1, 1000), child: Container(height: 10, color: Couleurs.basBg)),
                    Expanded(
                        flex: ((p(maximum) - p(minimum)) * 1000).round().clamp(1, 1000),
                        child: Container(height: 10, color: Couleurs.justeBg)),
                    Expanded(flex: ((1 - p(maximum)) * 1000).round().clamp(1, 1000), child: Container(height: 10, color: Couleurs.hautBg)),
                  ]),
                ),
              ),
              Positioned(
                left: (x - 30).clamp(0.0, w > 60 ? w - 60 : 0.0),
                top: 0,
                child: SizedBox(
                  width: 60,
                  child: Column(children: [
                    Text('${(loyer / 1000).round()} k', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    Container(width: 4, height: 24, decoration: BoxDecoration(color: Couleurs.texte, borderRadius: BorderRadius.circular(2))),
                  ]),
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Bonne affaire', style: TextStyle(fontSize: 12, color: Couleurs.texte2)),
                    Text('Prix juste', style: TextStyle(fontSize: 12, color: Couleurs.texte2)),
                    Text('Au-dessus', style: TextStyle(fontSize: 12, color: Couleurs.texte2)),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

/// Encadré blanc à bordure grise.
class Carte extends StatelessWidget {
  const Carte({super.key, required this.child, this.padding = const EdgeInsets.all(22), this.alerte = false});

  final Widget child;
  final EdgeInsets padding;
  final bool alerte;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: alerte ? Couleurs.primarySoft : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: alerte ? Couleurs.primarySoftBorder : Couleurs.bordure),
        ),
        child: child,
      );
}

class Titre extends StatelessWidget {
  const Titre(this.texte, {super.key, this.taille = 28, this.niveau = 1});

  final String texte;
  final double taille;
  final int niveau;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Text(texte, style: TextStyle(fontSize: taille, fontWeight: FontWeight.w800, letterSpacing: -.4, height: 1.15)),
      );
}

class Kpi extends StatelessWidget {
  const Kpi(this.libelle, this.valeur, {super.key, this.detail, this.alerte = false});

  final String libelle, valeur;
  final String? detail;
  final bool alerte;

  @override
  Widget build(BuildContext context) => Carte(
        alerte: alerte,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(libelle, style: const TextStyle(color: Couleurs.texte2, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(valeur, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            if (detail != null) Text(detail!, style: const TextStyle(color: Couleurs.texte2, fontSize: 14)),
          ],
        ),
      );
}

/// Puce sélectionnable (filtres, choix).
class Puce extends StatelessWidget {
  const Puce(this.texte, {super.key, required this.choisi, required this.onTap});

  final String texte;
  final bool choisi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: choisi,
        child: Material(
          color: choisi ? Couleurs.primarySoft : Colors.white,
          shape: StadiumBorder(side: BorderSide(color: choisi ? Couleurs.primary : Couleurs.bordureForte)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            // Taille = largeur du texte : les puces se placent côte à côte
            // dans un Wrap au lieu d'occuper chacune toute la ligne.
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40, minWidth: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(texte,
                        style: TextStyle(fontWeight: FontWeight.w600, color: choisi ? Couleurs.primary : Couleurs.texte)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

/// Chargement d'une donnée avec gestion du « en cours » et de l'erreur.
class Chargeur<T> extends StatefulWidget {
  const Chargeur({super.key, required this.charger, required this.builder, this.hauteur = 260});

  final Future<T> Function() charger;
  final Widget Function(BuildContext context, T donnees, VoidCallback recharger) builder;
  final double hauteur;

  @override
  State<Chargeur<T>> createState() => _ChargeurState<T>();
}

class _ChargeurState<T> extends State<Chargeur<T>> {
  late Future<T> _f = widget.charger();

  void _recharger() => setState(() => _f = widget.charger());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _f,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return SizedBox(
            height: widget.hauteur,
            child: Center(
              child: Semantics(label: 'Chargement', child: const CircularProgressIndicator(color: Couleurs.primary)),
            ),
          );
        }
        if (s.hasError) {
          return Erreur(s.error is ApiException ? '${s.error}' : 'Une erreur est survenue.', onReessayer: _recharger);
        }
        return widget.builder(context, s.data as T, _recharger);
      },
    );
  }
}

class Erreur extends StatelessWidget {
  const Erreur(this.texte, {super.key, this.onReessayer});

  final String texte;
  final VoidCallback? onReessayer;

  @override
  Widget build(BuildContext context) => Vide(
        icone: Icons.wifi_off_rounded,
        titre: 'Impossible de charger la page',
        texte: texte,
        action: onReessayer == null
            ? null
            : FilledButton.icon(onPressed: onReessayer, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
      );
}

class Vide extends StatelessWidget {
  const Vide({super.key, required this.icone, required this.titre, required this.texte, this.action});

  final IconData icone;
  final String titre, texte;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: Couleurs.primarySoft, shape: BoxShape.circle),
              child: Icon(icone, color: Couleurs.primary, size: 34),
            ),
            const SizedBox(height: 16),
            Text(titre, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(texte, textAlign: TextAlign.center, style: const TextStyle(color: Couleurs.texte2)),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      );
}

/// Libellé de champ au-dessus d'un contrôle.
class Champ extends StatelessWidget {
  const Champ(this.libelle, this.child, {super.key});

  final String libelle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(libelle, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 6),
          child,
        ],
      );
}

/// Liste déroulante simple (valeur nulle = « Tous / Toutes »).
class Liste<T> extends StatelessWidget {
  const Liste({
    super.key,
    required this.valeur,
    required this.options,
    required this.onChanged,
    this.libelleVide,
    this.libelle,
  });

  final T? valeur;
  final List<(T, String)> options;
  final ValueChanged<T?> onChanged;
  final String? libelleVide;
  final String Function(T)? libelle;

  @override
  Widget build(BuildContext context) {
    final valide = valeur == null || options.any((o) => o.$1 == valeur);
    return DropdownButtonFormField<T?>(
      key: ValueKey('$valeur-${options.length}'),
      initialValue: valide ? valeur : null,
      isExpanded: true,
      decoration: deco(),
      items: [
        if (libelleVide != null) DropdownMenuItem<T?>(value: null, child: Text(libelleVide!)),
        for (final o in options) DropdownMenuItem<T?>(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );
  }
}
