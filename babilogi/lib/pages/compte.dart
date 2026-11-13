import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/composants.dart';
import '../widgets/site.dart';
import 'introuvable.dart';

/// Après connexion : vers la page demandée, sinon selon le rôle.
void _apresConnexion(BuildContext context, String? suite) {
  final u = SessionScope.read(context).utilisateur!;
  final cible = suite ?? (u.estAdmin ? '/admin/signalements' : (u.estAnnonceur ? '/espace' : '/'));
  Navigator.of(context).pushNamedAndRemoveUntil(cible, (_) => false);
}

class PageConnexion extends StatefulWidget {
  const PageConnexion({super.key, this.suite});

  final String? suite;

  @override
  State<PageConnexion> createState() => _PageConnexionState();
}

class _PageConnexionState extends State<PageConnexion> {
  final _email = TextEditingController();
  final _mdp = TextEditingController();
  bool _envoi = false;
  String? _erreur;

  @override
  void dispose() {
    _email.dispose();
    _mdp.dispose();
    super.dispose();
  }

  Future<void> _connecter() async {
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      await SessionScope.read(context).connexion(_email.text, _mdp.text);
      if (mounted) _apresConnexion(context, widget.suite);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.erreurs.containsKey('verification')) {
        message(context, e.message);
        aller(context, _routeVerification(_email.text.trim(), widget.suite));
      } else {
        setState(() => _erreur = e.message);
      }
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SiteScaffold(
      child: Contenu(
        maxWidth: 500,
        vertical: 44,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Carte(
              padding: const EdgeInsets.all(28),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Titre('Se connecter', taille: 28),
                    const SizedBox(height: 6),
                    const Text('Accédez à votre espace annonceur ou à l\'administration.', style: TextStyle(color: Couleurs.texte2)),
                    if (widget.suite != null) ...[
                      const SizedBox(height: 12),
                      const Carte(alerte: true, padding: EdgeInsets.all(12), child: Text('Connectez-vous pour accéder à cette page.')),
                    ],
                    const SizedBox(height: 20),
                    Champ(
                      'E-mail',
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        autofocus: true,
                        decoration: deco(erreur: _erreur),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Champ(
                      'Mot de passe',
                      TextField(
                        controller: _mdp,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => _connecter(),
                        decoration: deco(),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => aller(
                            context,
                            Uri(
                              path: '/mot-de-passe-oublie',
                              queryParameters: _email.text.trim().isEmpty ? null : {'email': _email.text.trim()},
                            ).toString()),
                        child: const Text('Mot de passe oublié ?'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _envoi ? null : _connecter,
                      child: _envoi
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : const Text('Se connecter'),
                    ),
                    const SizedBox(height: 12),
                    Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                      const Text('Pas encore de compte ?'),
                      TextButton(onPressed: () => aller(context, '/inscription', remplacer: true), child: const Text('Créer un compte')),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PageInscription extends StatefulWidget {
  const PageInscription({super.key, this.profil});

  final String? profil;

  @override
  State<PageInscription> createState() => _PageInscriptionState();
}

/// Profils proposés à l'inscription : valeur envoyée à l'API, titre, description, icône.
const _profils = [
  ('locataire', 'Locataire', 'Je cherche un logement', Icons.search_rounded),
  ('particulier', 'Propriétaire', 'Je loue mon bien', Icons.home_outlined),
  ('agence', 'Agence', 'Agence immobilière', Icons.apartment_rounded),
];

class _PageInscriptionState extends State<PageInscription> {
  late String _profil = ['locataire', 'particulier', 'agence'].contains(widget.profil) ? widget.profil! : 'locataire';
  final _nom = TextEditingController();
  final _telephone = TextEditingController();
  final _email = TextEditingController();
  final _mdp = TextEditingController();
  final _confirmation = TextEditingController();
  bool _voir = false;
  bool _consentement = false;
  bool _envoi = false;
  Map<String, String> _erreurs = {};

  @override
  void dispose() {
    for (final c in [_nom, _telephone, _email, _mdp, _confirmation]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _creer() async {
    // Vérifications locales d'abord (messages près des champs)
    final locales = <String, String>{
      if (_mdp.text.length >= 8 && _confirmation.text != _mdp.text) 'confirmation': 'Les deux mots de passe ne sont pas identiques.',
    };
    if (locales.isNotEmpty) {
      setState(() => _erreurs = locales);
      return;
    }
    setState(() {
      _envoi = true;
      _erreurs = {};
    });
    try {
      final email = await SessionScope.read(context).inscription({
        'nom': _nom.text.trim(),
        'email': _email.text.trim(),
        'telephone': _telephone.text.trim(),
        'profil': _profil,
        'password': _mdp.text,
        'consentement': _consentement,
      });
      if (!mounted) return;
      message(context, 'Compte créé : un code vous a été envoyé par e-mail.');
      aller(context, _routeVerification(email, null), remplacer: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _erreurs = e.erreurs);
      if (e.erreurs.isEmpty) message(context, e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  /// Deux champs côte à côte (empilés sur un écran étroit).
  Widget _ligne(bool large, Widget a, Widget b) => large
      ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 16), Expanded(child: b)])
      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 14), b]);

  /// Force du mot de passe : 0 à 3 (longueur, chiffres, majuscules / caractères spéciaux).
  int get _force {
    final m = _mdp.text;
    if (m.length < 8) return m.isEmpty ? -1 : 0;
    var f = 1;
    if (RegExp(r'\d').hasMatch(m)) f++;
    if (RegExp(r'[A-Z]').hasMatch(m) || RegExp(r'[^A-Za-z0-9]').hasMatch(m)) f++;
    return f;
  }

  @override
  Widget build(BuildContext context) {
    final agence = _profil == 'agence';
    final oeil = IconButton(
      tooltip: _voir ? 'Masquer le mot de passe' : 'Afficher le mot de passe',
      onPressed: () => setState(() => _voir = !_voir),
      icon: Icon(_voir ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
    );
    return SiteScaffold(
      child: Contenu(
        maxWidth: 760,
        vertical: 44,
        child: LayoutBuilder(builder: (context, c) {
          final large = c.maxWidth >= 600;
          return Carte(
            padding: EdgeInsets.all(large ? 36 : 22),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // En-tête
                  Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: Couleurs.primarySoft, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.person_add_alt_1_outlined, color: Couleurs.primary),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Titre('Créer un compte', taille: 26),
                        SizedBox(height: 2),
                        Text('Gratuit · un code de confirmation vous est envoyé par e-mail.',
                            style: TextStyle(color: Couleurs.texte2)),
                      ]),
                    ),
                  ]),
                  if (_erreurs.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Carte(
                      alerte: true,
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        const Icon(Icons.error_outline, color: Couleurs.danger, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              'Vérifiez ${_erreurs.length > 1 ? 'les ${_erreurs.length} champs signalés' : 'le champ signalé'}.',
                              style: const TextStyle(color: Couleurs.danger, fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 26),

                  // Profil : trois cartes côte à côte
                  const Text('Vous êtes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 10),
                  Row(children: [
                    for (var i = 0; i < _profils.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(
                        child: _CarteProfil(
                          titre: _profils[i].$2,
                          detail: _profils[i].$3,
                          icone: _profils[i].$4,
                          choisi: _profil == _profils[i].$1,
                          compact: !large,
                          onTap: () => setState(() => _profil = _profils[i].$1),
                        ),
                      ),
                    ],
                  ]),
                  if (_erreurs['profil'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(_erreurs['profil']!, style: const TextStyle(color: Couleurs.danger)),
                    ),
                  const SizedBox(height: 26),

                  // Identité
                  const _TitreSection('Vos informations'),
                  _ligne(
                    large,
                    Champ(
                        agence ? 'Nom de l\'agence' : 'Nom complet',
                        TextField(
                            controller: _nom,
                            textCapitalization: TextCapitalization.words,
                            autofillHints: const [AutofillHints.name],
                            decoration: deco(hint: agence ? 'Ex. : Immo Lagune' : 'Ex. : Awa Koné', erreur: _erreurs['nom']))),
                    Champ(
                        'Téléphone (facultatif)',
                        TextField(
                            controller: _telephone,
                            keyboardType: TextInputType.phone,
                            autofillHints: const [AutofillHints.telephoneNumber],
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]'))],
                            decoration: deco(hint: '07 01 02 03 04', erreur: _erreurs['telephone']))),
                  ),
                  const SizedBox(height: 14),
                  Champ(
                      'E-mail',
                      TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: deco(hint: 'vous@exemple.ci', erreur: _erreurs['email']))),
                  const SizedBox(height: 26),

                  // Sécurité
                  const _TitreSection('Sécurité'),
                  _ligne(
                    large,
                    Champ(
                        'Mot de passe',
                        TextField(
                            controller: _mdp,
                            obscureText: !_voir,
                            autofillHints: const [AutofillHints.newPassword],
                            onChanged: (_) => setState(() {}),
                            decoration: deco(erreur: _erreurs['password']).copyWith(suffixIcon: oeil))),
                    Champ(
                        'Confirmer le mot de passe',
                        TextField(
                            controller: _confirmation,
                            obscureText: !_voir,
                            autofillHints: const [AutofillHints.newPassword],
                            onSubmitted: (_) => _consentement && !_envoi ? _creer() : null,
                            decoration: deco(erreur: _erreurs['confirmation']))),
                  ),
                  const SizedBox(height: 10),
                  _JaugeMotDePasse(force: _force),
                  const SizedBox(height: 22),

                  // Consentement
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _consentement = !_consentement),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(6, 6, 14, 10),
                      decoration: BoxDecoration(
                        color: Couleurs.surfaceMuted,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _erreurs['consentement'] != null ? Couleurs.danger : Couleurs.bordure),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Checkbox(
                          value: _consentement,
                          activeColor: Couleurs.primary,
                          onChanged: (v) => setState(() => _consentement = v ?? false),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text(
                                  'J\'accepte que BabiLogis utilise mes données pour gérer mon compte et mes demandes '
                                  '(loi n° 2013-450 relative à la protection des données personnelles).',
                                  style: TextStyle(fontSize: 14, height: 1.4)),
                              if (_erreurs['consentement'] != null) ...[
                                const SizedBox(height: 4),
                                Text(_erreurs['consentement']!, style: const TextStyle(color: Couleurs.danger, fontSize: 13)),
                              ],
                            ]),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: _envoi || !_consentement ? null : _creer,
                      child: _envoi
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : const Text('Créer mon compte', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    const Text('Déjà inscrit ?', style: TextStyle(color: Couleurs.texte2)),
                    TextButton(onPressed: () => aller(context, '/connexion', remplacer: true), child: const Text('Se connecter')),
                  ]),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _TitreSection extends StatelessWidget {
  const _TitreSection(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Text(texte.toUpperCase(),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Couleurs.texte2, letterSpacing: 0.8)),
          const SizedBox(width: 10),
          const Expanded(child: Divider(color: Couleurs.bordure, height: 1)),
        ]),
      );
}

/// Carte de choix du profil (sélection : bordure et fond rouges, coche).
class _CarteProfil extends StatelessWidget {
  const _CarteProfil({
    required this.titre,
    required this.detail,
    required this.icone,
    required this.choisi,
    required this.compact,
    required this.onTap,
  });

  final String titre, detail;
  final IconData icone;
  final bool choisi, compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: choisi,
      label: '$titre : $detail',
      excludeSemantics: true,
      child: Material(
        color: choisi ? Couleurs.primarySoft : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: choisi ? Couleurs.primary : Couleurs.bordure, width: choisi ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(compact ? 10 : 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: choisi ? Couleurs.primary : Couleurs.surfaceMuted,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icone, size: 20, color: choisi ? Colors.white : Couleurs.texte2),
                ),
                const Spacer(),
                Icon(choisi ? Icons.check_circle : Icons.circle_outlined,
                    size: 20, color: choisi ? Couleurs.primary : Couleurs.bordure),
              ]),
              const SizedBox(height: 10),
              Text(titre, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: choisi ? Couleurs.primary : Couleurs.texte)),
              if (!compact) ...[
                const SizedBox(height: 2),
                Text(detail, style: const TextStyle(color: Couleurs.texte2, fontSize: 13)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Jauge de robustesse du mot de passe (3 segments).
class _JaugeMotDePasse extends StatelessWidget {
  const _JaugeMotDePasse({required this.force});

  final int force; // -1 vide, 0 trop court, 1 correct, 2 bon, 3 excellent

  @override
  Widget build(BuildContext context) {
    final (libelle, couleur) = switch (force) {
      -1 => ('8 caractères minimum, avec des chiffres et une majuscule pour plus de sécurité.', Couleurs.texte2),
      0 => ('Trop court : 8 caractères minimum.', Couleurs.danger),
      1 => ('Correct : ajoutez des chiffres ou une majuscule.', Couleurs.hautFg),
      2 => ('Bon mot de passe.', Couleurs.justeFg),
      _ => ('Excellent mot de passe.', Couleurs.justeFg),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 5,
              decoration: BoxDecoration(
                color: force > i || (force == 0 && i == 0) ? couleur : Couleurs.placeholder,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 6),
      Text(libelle, style: TextStyle(fontSize: 13, color: couleur)),
    ]);
  }
}

String _routeVerification(String email, String? suite) =>
    Uri(path: '/verification', queryParameters: {'email': email, 'suite': ?suite}).toString();

/// Saisie du code à 6 chiffres reçu par e-mail après l'inscription.
class PageVerification extends StatefulWidget {
  const PageVerification({super.key, required this.email, this.suite});

  final String email;
  final String? suite;

  @override
  State<PageVerification> createState() => _PageVerificationState();
}

class _PageVerificationState extends State<PageVerification> {
  final _code = TextEditingController();
  bool _envoi = false;
  String? _erreur;
  int _attente = 60; // secondes avant de pouvoir redemander un code
  Timer? _minuteur;

  @override
  void initState() {
    super.initState();
    _demarrerMinuteur();
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _demarrerMinuteur() {
    _minuteur?.cancel();
    _attente = 60;
    _minuteur = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_attente <= 1) t.cancel();
      setState(() => _attente--);
    });
  }

  Future<void> _verifier() async {
    if (_code.text.trim().length != 6) {
      setState(() => _erreur = 'Saisissez les 6 chiffres du code.');
      return;
    }
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      await SessionScope.read(context).verifierEmail(widget.email, _code.text);
      if (!mounted) return;
      message(context, 'Adresse vérifiée. Bienvenue sur BabiLogis !');
      _apresConnexion(context, widget.suite);
    } on ApiException catch (e) {
      if (mounted) setState(() => _erreur = e.erreurs['code'] ?? e.message);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  Future<void> _renvoyer() async {
    try {
      await SessionScope.read(context).renvoyerCode(widget.email);
      if (!mounted) return;
      message(context, 'Nouveau code envoyé à ${widget.email}.');
      _code.clear();
      setState(() => _erreur = null);
      _demarrerMinuteur();
    } on ApiException catch (e) {
      if (mounted) message(context, e.message, erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.email.isEmpty) {
      return const PageIntrouvable(texte: 'Lien de vérification incomplet. Connectez-vous pour recevoir un nouveau code.');
    }
    return SiteScaffold(
      child: Contenu(
        maxWidth: 500,
        vertical: 44,
        child: Carte(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.mark_email_unread_outlined, size: 48, color: Couleurs.primary),
              const SizedBox(height: 12),
              const Titre('Vérifiez votre e-mail', taille: 28),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Nous avons envoyé un code à 6 chiffres à '),
                  TextSpan(text: widget.email, style: const TextStyle(fontWeight: FontWeight.w700, color: Couleurs.texte)),
                  const TextSpan(text: '. Il est valable 10 minutes.'),
                ]),
                style: const TextStyle(color: Couleurs.texte2),
              ),
              const SizedBox(height: 20),
              Champ(
                'Code de vérification',
                TextField(
                  controller: _code,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 10),
                  onChanged: (v) {
                    if (v.length == 6 && !_envoi) _verifier();
                  },
                  onSubmitted: (_) => _verifier(),
                  decoration: deco(hint: '••••••', erreur: _erreur),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _envoi ? null : _verifier,
                child: _envoi
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Text('Vérifier'),
              ),
              const SizedBox(height: 12),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.center, children: [
                const Text('Pas reçu ? Pensez aux courriers indésirables.'),
                TextButton(
                  onPressed: _attente > 0 ? null : _renvoyer,
                  child: Text(_attente > 0 ? 'Renvoyer le code (${_attente}s)' : 'Renvoyer le code'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
