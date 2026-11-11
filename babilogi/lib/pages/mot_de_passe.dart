import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/composants.dart';
import '../widgets/site.dart';

/// « Mot de passe oublié » en deux étapes :
///  1. l'adresse e-mail → un code à 6 chiffres est envoyé (valable 10 minutes) ;
///  2. le code + le nouveau mot de passe → retour à la connexion.
class PageMotDePasseOublie extends StatefulWidget {
  const PageMotDePasseOublie({super.key, this.email});

  final String? email;

  @override
  State<PageMotDePasseOublie> createState() => _PageMotDePasseOublieState();
}

class _PageMotDePasseOublieState extends State<PageMotDePasseOublie> {
  late final _email = TextEditingController(text: widget.email ?? '');
  final _code = TextEditingController();
  final _mdp = TextEditingController();
  final _confirmation = TextEditingController();

  bool _codeEnvoye = false;
  bool _envoi = false;
  bool _voir = false;
  Map<String, String> _erreurs = {};
  int _attente = 0;
  Timer? _minuteur;

  @override
  void dispose() {
    _minuteur?.cancel();
    _email.dispose();
    _code.dispose();
    _mdp.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _demarrerMinuteur() {
    _minuteur?.cancel();
    _attente = 60;
    _minuteur = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_attente <= 1) t.cancel();
      if (mounted) setState(() => _attente--);
    });
  }

  Future<void> _demanderCode() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _erreurs = {'email': 'Entrez une adresse e-mail valide.'});
      return;
    }
    setState(() {
      _envoi = true;
      _erreurs = {};
    });
    try {
      final r = await Api.instance.post('/mot-de-passe/oublie', {'email': email}) as Map<String, dynamic>;
      if (!mounted) return;
      message(context, '${r['message']}');
      setState(() => _codeEnvoye = true);
      _demarrerMinuteur();
    } on ApiException catch (e) {
      if (mounted) setState(() => _erreurs = e.erreurs.isEmpty ? {'email': e.message} : e.erreurs);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  Future<void> _reinitialiser() async {
    final err = <String, String>{
      if (_code.text.trim().length != 6) 'code': 'Saisissez les 6 chiffres du code.',
      if (_mdp.text.length < 8) 'password': 'Au moins 8 caractères.',
      if (_confirmation.text != _mdp.text) 'confirmation': 'Les deux mots de passe ne sont pas identiques.',
    };
    if (err.isNotEmpty) {
      setState(() => _erreurs = err);
      return;
    }
    setState(() {
      _envoi = true;
      _erreurs = {};
    });
    try {
      final r = await Api.instance.post('/mot-de-passe/reinitialiser', {
        'email': _email.text.trim(),
        'code': _code.text.trim(),
        'password': _mdp.text,
      }) as Map<String, dynamic>;
      if (!mounted) return;
      message(context, '${r['message']}');
      aller(context, '/connexion', remplacer: true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _erreurs = e.erreurs.isEmpty ? {'code': e.message} : e.erreurs);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  Widget _bouton(String texte, VoidCallback action) => FilledButton(
        onPressed: _envoi ? null : action,
        child: _envoi
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Text(texte),
      );

  @override
  Widget build(BuildContext context) {
    final oeil = IconButton(
      tooltip: _voir ? 'Masquer le mot de passe' : 'Afficher le mot de passe',
      onPressed: () => setState(() => _voir = !_voir),
      icon: Icon(_voir ? Icons.visibility_off_outlined : Icons.visibility_outlined),
    );
    return SiteScaffold(
      child: Contenu(
        maxWidth: 500,
        vertical: 44,
        child: Carte(
          padding: const EdgeInsets.all(28),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(_codeEnvoye ? Icons.mark_email_unread_outlined : Icons.lock_reset, size: 48, color: Couleurs.primary),
                const SizedBox(height: 12),
                Titre(_codeEnvoye ? 'Nouveau mot de passe' : 'Mot de passe oublié', taille: 28),
                const SizedBox(height: 6),
                if (!_codeEnvoye)
                  const Text('Indiquez l\'adresse e-mail de votre compte : nous vous envoyons un code à 6 chiffres '
                      'pour choisir un nouveau mot de passe.', style: TextStyle(color: Couleurs.texte2))
                else
                  Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: 'Saisissez le code reçu à '),
                      TextSpan(text: _email.text.trim(), style: const TextStyle(fontWeight: FontWeight.w700, color: Couleurs.texte)),
                      const TextSpan(text: ' (valable 10 minutes), puis votre nouveau mot de passe.'),
                    ]),
                    style: const TextStyle(color: Couleurs.texte2),
                  ),
                const SizedBox(height: 20),
                if (!_codeEnvoye) ...[
                  Champ(
                    'E-mail',
                    TextField(
                      controller: _email,
                      autofocus: true,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      onSubmitted: (_) => _demanderCode(),
                      decoration: deco(erreur: _erreurs['email']),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _bouton('Recevoir le code', _demanderCode),
                ] else ...[
                  Champ(
                    'Code reçu par e-mail',
                    TextField(
                      controller: _code,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 10),
                      decoration: deco(hint: '••••••', erreur: _erreurs['code']),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Champ(
                    'Nouveau mot de passe',
                    TextField(
                      controller: _mdp,
                      obscureText: !_voir,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: deco(hint: '8 caractères minimum', erreur: _erreurs['password']).copyWith(suffixIcon: oeil),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Champ(
                    'Confirmer le mot de passe',
                    TextField(
                      controller: _confirmation,
                      obscureText: !_voir,
                      autofillHints: const [AutofillHints.newPassword],
                      onSubmitted: (_) => _reinitialiser(),
                      decoration: deco(erreur: _erreurs['confirmation']),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _bouton('Enregistrer le mot de passe', _reinitialiser),
                  const SizedBox(height: 8),
                  Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    TextButton(
                      onPressed: _attente > 0 || _envoi ? null : _demanderCode,
                      child: Text(_attente > 0 ? 'Renvoyer le code (${_attente}s)' : 'Renvoyer le code'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _codeEnvoye = false;
                        _erreurs = {};
                        _code.clear();
                      }),
                      child: const Text('Changer d\'adresse'),
                    ),
                  ]),
                  const Text('Pas reçu ? Pensez aux courriers indésirables.',
                      textAlign: TextAlign.center, style: TextStyle(color: Couleurs.texte2, fontSize: 14)),
                ],
                const SizedBox(height: 8),
                TextButton(onPressed: () => aller(context, '/connexion', remplacer: true), child: const Text('Retour à la connexion')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
