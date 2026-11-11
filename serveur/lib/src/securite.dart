/// Mots de passe (PBKDF2-HMAC-SHA256) et jetons d'accès à l'API.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

final _aleatoire = Random.secure();

String _base64(List<int> octets) => base64Url.encode(octets).replaceAll('=', '');

List<int> _pbkdf2(List<int> motDePasse, List<int> sel, int iterations) {
  final hmac = Hmac(sha256, motDePasse);
  final bloc = Uint8List.fromList([...sel, 0, 0, 0, 1]);
  var u = hmac.convert(bloc).bytes;
  final resultat = List<int>.from(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < resultat.length; j++) {
      resultat[j] ^= u[j];
    }
  }
  return resultat;
}

/// Format stocké : pbkdf2$<itérations>$<sel>$<empreinte>
String hacherMotDePasse(String motDePasse, {int iterations = 20000}) {
  final sel = List<int>.generate(16, (_) => _aleatoire.nextInt(256));
  final h = _pbkdf2(utf8.encode(motDePasse), sel, iterations);
  return 'pbkdf2\$$iterations\$${_base64(sel)}\$${_base64(h)}';
}

bool verifierMotDePasse(String motDePasse, String stocke) {
  final p = stocke.split('\$');
  if (p.length != 4 || p[0] != 'pbkdf2') return false;
  final iterations = int.tryParse(p[1]) ?? 0;
  List<int> decoder(String s) => base64Url.decode(s.padRight((s.length + 3) ~/ 4 * 4, '='));
  final attendu = decoder(p[3]);
  final h = _pbkdf2(utf8.encode(motDePasse), decoder(p[2]), iterations);
  if (h.length != attendu.length) return false;
  var diff = 0;
  for (var i = 0; i < h.length; i++) {
    diff |= h[i] ^ attendu[i];
  }
  return diff == 0;
}

/// Nouveau jeton (remis au client) ; on ne stocke que son empreinte.
String nouveauJeton() => _base64(List<int>.generate(40, (_) => _aleatoire.nextInt(256)));

String empreinteJeton(String jeton) => sha256.convert(utf8.encode(jeton)).toString();

/// Code de vérification à 6 chiffres envoyé par e-mail.
String nouveauCodeEmail() => List<int>.generate(6, (_) => _aleatoire.nextInt(10)).join();
