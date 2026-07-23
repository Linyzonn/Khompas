import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'ai_extractor.dart';

/// Client du serveur Khompas (beta) : partage de colloscope par code de
/// classe. La cle API vit sur le serveur — les utilisateurs n'en ont pas.
class ApiKhompas {
  final String base; // ex. https://khompas.deno.dev
  ApiKhompas(String url) : base = url.trim().replaceAll(RegExp(r'/+$'), '');

  Never _lance(http.Response r) {
    var msg = 'HTTP ${r.statusCode}';
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (j['erreur'] != null) msg = j['erreur'].toString();
    } catch (_) {}
    throw Exception(msg);
  }

  /// Cree une classe vide sur le serveur, retourne son code (ex. "K7M2PX").
  Future<String> creerClasse() async {
    final r = await http
        .post(Uri.parse('$base/api/classes'))
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) _lance(r);
    return (jsonDecode(utf8.decode(r.bodyBytes))
        as Map<String, dynamic>)['code'] as String;
  }

  /// Envoie une piece du colloscope (photo jpeg, ou PDF si [pdf]) pour la
  /// classe [code].
  Future<void> envoyerPhoto(String code, int index, Uint8List bytes,
      {bool pdf = false}) async {
    final r = await http
        .put(
          Uri.parse(
              '$base/api/classes/$code/photos/$index?mime=${pdf ? 'pdf' : 'jpg'}'),
          headers: {'content-type': 'text/plain'},
          body: base64Encode(bytes),
        )
        .timeout(const Duration(seconds: 90));
    if (r.statusCode != 200) _lance(r);
  }

  /// Recupere les kholles du groupe [groupe] de la classe [code].
  /// Si le groupe est deja en cache : instantane. Sinon le serveur lance
  /// l'extraction EN TACHE DE FOND (reponse 202) et on re-interroge toutes
  /// les 5 s — aucune requete longue, rien que les passerelles puissent
  /// couper. [force] ignore le cache (si l'extraction etait mauvaise).
  Future<ExtractionResult> groupe(String code, int groupe,
      {bool force = false}) async {
    final deadline = DateTime.now().add(const Duration(minutes: 4));
    var premiere = true;
    while (true) {
      final query = (force && premiere) ? '?force=1' : '';
      premiere = false;
      final r = await http
          .get(Uri.parse('$base/api/classes/$code/groupe/$groupe$query'))
          .timeout(const Duration(seconds: 45));
      if (r.statusCode == 202) {
        // Extraction en cours cote serveur : on repasse dans 5 s.
        if (DateTime.now().isAfter(deadline)) {
          throw Exception(
              "l'extraction prend trop de temps — réessaie dans une minute, le serveur continue de travailler.");
        }
        await Future.delayed(const Duration(seconds: 5));
        continue;
      }
      if (r.statusCode != 200) _lance(r);
      final text = (jsonDecode(utf8.decode(r.bodyBytes))
          as Map<String, dynamic>)['text'] as String;
      return parseExtraction(text);
    }
  }
}
