import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../notifications/centre.dart';
import '../theme.dart';
import '../widgets/composants.dart';
import '../widgets/site.dart';

/// Conversation entre un locataire et l'annonceur (propriétaire ou agence) d'une annonce.
class Conversation {
  Conversation.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        jeSuis = '${j['je_suis']}',
        interlocuteur = '${j['interlocuteur']}',
        reference = '${(j['annonce'] as Map)['reference']}',
        titreAnnonce = '${(j['annonce'] as Map)['titre']}',
        lieu = '${(j['annonce'] as Map)['lieu']}',
        loyer = ((j['annonce'] as Map)['loyer'] as num?)?.toInt() ?? 0,
        photo = _premiere((j['annonce'] as Map)['photos']),
        dernierMessage = j['dernier_message'] as String?,
        dernierDeMoi = j['dernier_de_moi'] == true,
        quand = '${j['quand'] ?? ''}',
        nonLus = (j['non_lus'] as num?)?.toInt() ?? 0;

  final int id, loyer, nonLus;
  final String jeSuis, interlocuteur, reference, titreAnnonce, lieu, quand;
  final String? dernierMessage;
  final bool dernierDeMoi;
  final PhotoAnnonce? photo;

  static PhotoAnnonce? _premiere(dynamic v) {
    final l = PhotoAnnonce.liste(v);
    return l.isEmpty ? null : l.first;
  }
}

class MessageChat {
  MessageChat.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        texte = '${j['texte']}',
        moi = j['moi'] == true,
        lu = j['lu'] == true,
        heure = '${j['heure'] ?? ''}';

  final int id;
  final String texte, heure;
  final bool moi, lu;
}

/// Ouvre (ou retrouve) la conversation avec l'annonceur d'une annonce, puis affiche la messagerie.
Future<void> contacterAnnonceur(BuildContext context, String reference, String texte) async {
  try {
    final r = await Api.instance.post('/conversations', {'annonce': reference, 'message': texte}) as Map<String, dynamic>;
    final id = ((r['conversation'] as Map)['id'] as num).toInt();
    if (context.mounted) aller(context, '/messages/$id');
  } on ApiException catch (e) {
    if (context.mounted) message(context, e.message, erreur: true);
  }
}

/// Messagerie : liste des conversations à gauche, échanges à droite (rafraîchis toutes les 4 secondes).
class PageMessages extends StatefulWidget {
  const PageMessages({super.key, this.conversationId});

  final int? conversationId;

  @override
  State<PageMessages> createState() => _PageMessagesState();
}

class _PageMessagesState extends State<PageMessages> {
  List<Conversation>? _conversations;
  String? _erreur;
  late int? _choisie = widget.conversationId;
  Timer? _minuterie;

  @override
  void initState() {
    super.initState();
    _charger();
    _minuterie = Timer.periodic(const Duration(seconds: 10), (_) => _charger());
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final r = await Api.instance.get('/conversations') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _conversations = [for (final c in (r['data'] as List? ?? const [])) Conversation.fromJson(c as Map<String, dynamic>)];
        _erreur = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    }
  }

  void _choisir(int id) {
    setState(() => _choisie = id);
    Navigator.of(context).pushReplacementNamed('/messages/$id');
  }

  @override
  Widget build(BuildContext context) {
    final hauteur = MediaQuery.sizeOf(context).height - 76;
    final large = MediaQuery.sizeOf(context).width >= 900;
    final liste = _ListeConversations(
      conversations: _conversations,
      erreur: _erreur,
      choisie: _choisie,
      onChoisir: _choisir,
    );
    final fil = _choisie == null
        ? const Center(
            child: Text('Choisissez une conversation, ou cliquez sur « Contacter l\'annonceur » depuis une annonce.',
                textAlign: TextAlign.center, style: TextStyle(color: Couleurs.texte2)))
        : _FilMessages(key: ValueKey(_choisie), conversationId: _choisie!, onEnvoye: _charger);
    return SiteScaffold(
      actif: 'messages',
      piedDePage: false,
      child: SizedBox(
        height: hauteur < 560 ? 560 : hauteur,
        child: Contenu(
          maxWidth: 1180,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                if (!large && _choisie != null)
                  IconButton(
                    tooltip: 'Toutes les conversations',
                    onPressed: () {
                      setState(() => _choisie = null);
                      Navigator.of(context).pushReplacementNamed('/messages');
                    },
                    icon: const Icon(Icons.arrow_back),
                  ),
                const Titre('Messages', taille: 26),
              ]),
              const SizedBox(height: 12),
              Expanded(
                child: large
                    ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SizedBox(width: 340, child: Carte(padding: EdgeInsets.zero, child: liste)),
                        const SizedBox(width: 16),
                        Expanded(child: Carte(padding: EdgeInsets.zero, child: fil)),
                      ])
                    : Carte(padding: EdgeInsets.zero, child: _choisie == null ? liste : fil),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ListeConversations extends StatelessWidget {
  const _ListeConversations({required this.conversations, required this.erreur, required this.choisie, required this.onChoisir});

  final List<Conversation>? conversations;
  final String? erreur;
  final int? choisie;
  final ValueChanged<int> onChoisir;

  @override
  Widget build(BuildContext context) {
    final cs = conversations;
    if (erreur != null && cs == null) return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(erreur!)));
    if (cs == null) return const Center(child: CircularProgressIndicator(color: Couleurs.primary));
    if (cs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aucune conversation pour l\'instant.\nSur une annonce, cliquez sur « Contacter l\'annonceur ».',
              textAlign: TextAlign.center, style: TextStyle(color: Couleurs.texte2)),
        ),
      );
    }
    return ListView.separated(
      itemCount: cs.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final c = cs[i];
        return Material(
          color: c.id == choisie ? Couleurs.primarySoft : Colors.white,
          child: InkWell(
            onTap: () => onChoisir(c.id),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                SizedBox(width: 56, height: 56, child: Photo(c.photo, hauteur: 56, rayon: 10, taille: 22, mention: false)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(c.interlocuteur,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: c.nonLus > 0 ? FontWeight.w800 : FontWeight.w600)),
                      ),
                      Text(c.quand, style: const TextStyle(color: Couleurs.texte2, fontSize: 12)),
                    ]),
                    Text('${c.titreAnnonce} · ${c.reference}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Couleurs.texte2, fontSize: 13)),
                    Row(children: [
                      Expanded(
                        child: Text('${c.dernierDeMoi ? 'Vous : ' : ''}${c.dernierMessage ?? ''}',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, fontWeight: c.nonLus > 0 ? FontWeight.w700 : FontWeight.w400)),
                      ),
                      if (c.nonLus > 0) Pastille('${c.nonLus}'),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _FilMessages extends StatefulWidget {
  const _FilMessages({super.key, required this.conversationId, required this.onEnvoye});

  final int conversationId;
  final VoidCallback onEnvoye;

  @override
  State<_FilMessages> createState() => _FilMessagesState();
}

class _FilMessagesState extends State<_FilMessages> {
  final _champ = TextEditingController();
  final _defilement = ScrollController();
  final List<MessageChat> _messages = [];
  Conversation? _conversation;
  String? _erreur;
  bool _envoi = false;
  Timer? _minuterie;

  @override
  void initState() {
    super.initState();
    _charger();
    _minuterie = Timer.periodic(const Duration(seconds: 4), (_) => _charger());
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    _champ.dispose();
    _defilement.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final apres = _messages.isEmpty ? 0 : _messages.last.id;
    try {
      final r = await Api.instance.get('/conversations/${widget.conversationId}/messages', {'apres': apres}) as Map<String, dynamic>;
      if (!mounted) return;
      final nouveaux = [for (final m in (r['messages'] as List? ?? const [])) MessageChat.fromJson(m as Map<String, dynamic>)];
      setState(() {
        _conversation = Conversation.fromJson(r['conversation'] as Map<String, dynamic>);
        _messages.addAll(nouveaux.where((m) => _messages.every((x) => x.id != m.id)));
        _erreur = null;
      });
      if (nouveaux.isNotEmpty) {
        _descendre();
        unawaited(CentreNotifications.instance.rafraichir());
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    }
  }

  void _descendre() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_defilement.hasClients) {
        _defilement.animateTo(_defilement.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _envoyer() async {
    final texte = _champ.text.trim();
    if (texte.isEmpty || _envoi) return;
    setState(() => _envoi = true);
    try {
      final r = await Api.instance.post('/conversations/${widget.conversationId}/messages', {'texte': texte}) as Map<String, dynamic>;
      _champ.clear();
      if (!mounted) return;
      setState(() => _messages.add(MessageChat.fromJson(r['message'] as Map<String, dynamic>)));
      _descendre();
      widget.onEnvoye();
    } on ApiException catch (e) {
      if (mounted) message(context, e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _conversation;
    if (_erreur != null && c == null) return Center(child: Text(_erreur!));
    if (c == null) return const Center(child: CircularProgressIndicator(color: Couleurs.primary));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.interlocuteur, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              Text('${c.titreAnnonce} · ${c.lieu} · ${fcfa(c.loyer)} / mois',
                  style: const TextStyle(color: Couleurs.texte2, fontSize: 13.5)),
            ]),
          ),
          TextButton(onPressed: () => aller(context, '/annonces/${c.reference}'), child: const Text('Voir l\'annonce')),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: _messages.isEmpty
            ? const Center(child: Text('Écrivez votre premier message.', style: TextStyle(color: Couleurs.texte2)))
            : ListView.builder(
                controller: _defilement,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, i) => _Bulle(_messages[i]),
              ),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _champ,
              maxLength: 2000,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _envoyer(),
              decoration: deco(hint: 'Votre message…').copyWith(counterText: ''),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: _envoi ? null : _envoyer,
              icon: const Icon(Icons.send, size: 18),
              label: const Text('Envoyer'),
            ),
          ),
        ]),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Text('Ne versez jamais d\'argent avant d\'avoir visité le logement.',
            style: TextStyle(color: Couleurs.texte2, fontSize: 12)),
      ),
    ]);
  }
}

class _Bulle extends StatelessWidget {
  const _Bulle(this.m);

  final MessageChat m;

  @override
  Widget build(BuildContext context) {
    final largeurMax = MediaQuery.sizeOf(context).width * .55;
    return Align(
      alignment: m.moi ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: largeurMax < 280 ? 280 : (largeurMax > 560 ? 560 : largeurMax)),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          color: m.moi ? Couleurs.primary : Couleurs.surfaceMuted,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          SelectableText(m.texte, style: TextStyle(color: m.moi ? Colors.white : Couleurs.texte, height: 1.4, fontSize: 15)),
          const SizedBox(height: 2),
          Text('${m.heure}${m.moi ? (m.lu ? ' · lu' : ' · envoyé') : ''}',
              style: TextStyle(color: m.moi ? Colors.white70 : Couleurs.texte2, fontSize: 11)),
        ]),
      ),
    );
  }
}
