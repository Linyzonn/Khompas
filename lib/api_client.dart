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
  /// Premiere demande d'un groupe : le serveur lance l'extraction (jusqu'a
  /// ~2 min). Ensuite c'est en cache, quasi instantane.
  /// [force] ignore le cache (si l'extraction precedente etait mauvaise).
  Future<ExtractionResult> groupe(String code, int groupe,
      {bool force = false}) async {
    final r = await http
        .get(Uri.parse(
            '$base/api/classes/$code/groupe/$groupe${force ? '?force=1' : ''}'))
        .timeout(const Duration(minutes: 3));
    if (r.statusCode != 200) _lance(r);
    final text = (jsonDecode(utf8.decode(r.bodyBytes))
        as Map<String, dynamic>)['text'] as String;
    return parseExtraction(text);
  }
}
