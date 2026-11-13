import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/composants.dart';
import '../widgets/site.dart';

/// Assistant logement : agent IA (Gemini + outils) du service FastAPI, via le serveur Dart.
class PageAssistant extends StatefulWidget {
  const PageAssistant({super.key});

  @override
  State<PageAssistant> createState() => _PageAssistantState();
}

class _MessageChat {
  _MessageChat(this.role, this.texte, {this.annonces = const [], this.outils = const [], this.moteur, this.erreur = false});

  final String role; // utilisateur | assistant
  final String texte;
  final List<Map<String, dynamic>> annonces;
  final List<String> outils;
  final String? moteur;
  final bool erreur;
}

const _exemples = [
  'Je cherche un 3 pièces à Cocody sous 300 000',
  'Combien coûte un studio meublé à Yopougon ?',
  '450 000 pour une villa 4 pièces à Bingerville, c\'est cher ?',
  'Quelle commune est la moins chère pour un 2 pièces ?',
];

class _PageAssistantState extends State<PageAssistant> {
  final _champ = TextEditingController();
  final _defilement = ScrollController();
  final _focus = FocusNode();
  final List<_MessageChat> _messages = [];
  bool _enCours = false;

  @override
  void dispose() {
    _champ.dispose();
    _defilement.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _envoyer([String? texte]) async {
    final message = (texte ?? _champ.text).trim();
    if (message.isEmpty || _enCours) return;
    final historique = [
      for (final m in _messages.where((m) => !m.erreur)) {'role': m.role, 'texte': m.texte},
    ];
    setState(() {
      _messages.add(_MessageChat('utilisateur', message));
      _enCours = true;
      _champ.clear();
    });
    _descendre();
    try {
      final r = await Api.instance.post('/assistant', {'message': message, 'historique': historique}) as Map<String, dynamic>;
      final annonces = [for (final a in (r['annonces'] as List? ?? const [])) Map<String, dynamic>.from(a as Map)];
      final outils = [for (final o in (r['outils'] as List? ?? const [])) '${(o as Map)['outil']}'];
      if (!mounted) return;
      setState(() => _messages.add(_MessageChat('assistant', '${r['reponse'] ?? ''}',
          annonces: annonces, outils: outils, moteur: r['moteur'] as String?)));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(_MessageChat('assistant', e.message, erreur: true)));
    } finally {
      if (mounted) setState(() => _enCours = false);
      _descendre();
      _focus.requestFocus();
    }
  }

  void _descendre() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_defilement.hasClients) {
        _defilement.animateTo(_defilement.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hauteur = MediaQuery.sizeOf(context).height - 76;
    return SiteScaffold(
      actif: 'assistant',
      piedDePage: false,
      child: SizedBox(
        height: hauteur < 520 ? 520 : hauteur,
        child: Contenu(
          maxWidth: 860,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              const Titre('Assistant logement', taille: 26),
              const SizedBox(height: 4),
              const Text(
                'Posez votre question : je cherche dans les annonces et j\'estime les loyers avec le modèle BabiLogis.',
                style: TextStyle(color: Couleurs.texte2),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: _messages.isEmpty
                    ? _Accueil(onChoix: _envoyer)
                    : ListView.builder(
                        controller: _defilement,
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: _messages.length + (_enCours ? 1 : 0),
                        itemBuilder: (_, i) => i == _messages.length ? const _Reflexion() : _Bulle(_messages[i]),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16, top: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _champ,
                        focusNode: _focus,
                        enabled: !_enCours,
                        maxLength: 1000,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _envoyer(),
                        decoration: deco(hint: 'Ex. : un 2 pièces à Marcory sous 200 000').copyWith(counterText: ''),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _enCours ? null : () => _envoyer(),
                        icon: const Icon(Icons.send, size: 18),
                        label: const Text('Envoyer'),
                      ),
                    ),
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

class _Accueil extends StatelessWidget {
  const _Accueil({required this.onChoix});

  final void Function(String) onChoix;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Carte(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  CircleAvatar(backgroundColor: Couleurs.primarySoft, child: Icon(Icons.smart_toy_outlined, color: Couleurs.primary)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('Bonjour, je suis Babi. Essayez une de ces questions :',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final e in _exemples) Puce(e, choisi: false, onTap: () => onChoix(e))],
              ),
            ],
          ),
        ),
      );
}

class _Reflexion extends StatelessWidget {
  const _Reflexion();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Couleurs.primary)),
            SizedBox(width: 10),
            Text('Babi réfléchit…', style: TextStyle(color: Couleurs.texte2)),
          ],
        ),
      );
}

/// Retire le markdown simple (gras, italique, puces) renvoyé par le modèle.
String _nettoyer(String t) => t
    .replaceAll('**', '')
    .replaceAllMapped(RegExp(r'(^|\s)_([^_\n]+)_'), (m) => '${m[1]}${m[2]}')
    .replaceAll(RegExp(r'^\s*[*-]\s+', multiLine: true), '• ');

class _Bulle extends StatelessWidget {
  const _Bulle(this.m);

  final _MessageChat m;

  @override
  Widget build(BuildContext context) {
    final moi = m.role == 'utilisateur';
    final largeurMax = MediaQuery.sizeOf(context).width * (moi ? .7 : .9);
    return Align(
      alignment: moi ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        constraints: BoxConstraints(maxWidth: largeurMax > 720 ? 720 : largeurMax),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: moi ? Couleurs.primary : (m.erreur ? Couleurs.primarySoft : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: moi ? null : Border.all(color: m.erreur ? Couleurs.primarySoftBorder : Couleurs.bordure),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              moi ? m.texte : _nettoyer(m.texte),
              style: TextStyle(color: moi ? Colors.white : Couleurs.texte, height: 1.45, fontSize: 15.5),
            ),
            if (m.annonces.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final a in m.annonces.take(5)) _MiniAnnonce(a),
            ],
            if (!moi && !m.erreur && (m.outils.isNotEmpty || m.moteur != null)) ...[
              const SizedBox(height: 8),
              Text(
                [
                  if (m.outils.isNotEmpty) 'Outils : ${m.outils.toSet().join(', ')}',
                  if (m.moteur != null) 'Moteur : ${m.moteur}',
                ].join('  ·  '),
                style: const TextStyle(color: Couleurs.texte2, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniAnnonce extends StatelessWidget {
  const _MiniAnnonce(this.a);

  final Map<String, dynamic> a;

  @override
  Widget build(BuildContext context) {
    final ref = '${a['reference'] ?? ''}';
    final interne = ref.isNotEmpty && !ref.startsWith('WEB-');
    final lieu = [a['quartier'], a['commune']].where((e) => e != null && '$e'.isNotEmpty).join(', ');
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: Couleurs.fond,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: interne ? () => aller(context, '/annonces/$ref') : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${a['titre'] ?? 'Logement'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(interne ? lieu : '$lieu · annonce collectée sur le web',
                          style: const TextStyle(color: Couleurs.texte2, fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(fcfa((a['loyer'] as num?)?.toInt()), style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    VerdictBadge(a['verdict'] as String?, '${a['verdict_libelle'] ?? ''}', petit: true),
                  ],
                ),
                if (interne) const Icon(Icons.chevron_right, color: Couleurs.texte2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
