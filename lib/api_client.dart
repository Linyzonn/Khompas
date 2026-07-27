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

  /// Cree une classe vide sur le serveur. Retourne (code a partager,
  /// code de GESTION a garder pour soi — il permet la suppression).
  Future<(String, String)> creerClasse() async {
    final r = await http
        .post(Uri.parse('$base/api/classes'))
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) _lance(r);
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return (j['code'] as String, (j['gestion'] ?? '') as String);
  }

  /// Supprime une classe et tout son contenu (createur uniquement).
  Future<void> supprimerClasse(String code, String gestion) async {
    final r = await http.delete(
      Uri.parse('$base/api/classes/$code'),
      headers: {'x-khompas-gestion': gestion},
    ).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) _lance(r);
  }

  /// Partage le programme de colle d'une matiere pour la semaine du lundi
  /// [semaineIso] (AAAA-MM-JJ) avec toute la classe.
  Future<void> envoyerProgramme(
      String code, String semaineIso, String matiere, String texte) async {
    final r = await http
        .put(
          Uri.parse('$base/api/classes/$code/programmes'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode(
              {'semaine': semaineIso, 'matiere': matiere, 'texte': texte}),
        )
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) _lance(r);
  }

  /// Programmes de colle de la classe pour une semaine :
  /// {matiere (minuscules) -> texte}.
  Future<Map<String, String>> lireProgrammes(
      String code, String semaineIso) async {
    final r = await http
        .get(Uri.parse(
            '$base/api/classes/$code/programmes?semaine=$semaineIso'))
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) _lance(r);
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return ((j['programmes'] ?? {}) as Map)
        .map((k, v) => MapEntry(k.toString(), v.toString()));
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

  // ---------- Comptes anonymes ----------

  /// Cree un compte anonyme, retourne sa CLE (18 caracteres) — a garder
  /// precieusement : c'est elle qui permet de retrouver ses donnees.
  Future<String> creerCompte(
      {required String filiere, required bool cinqDemi}) async {
    final r = await http
        .post(
          Uri.parse('$base/api/comptes'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'filiere': filiere, 'cinqDemi': cinqDemi}),
        )
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) _lance(r);
    return (jsonDecode(utf8.decode(r.bodyBytes))
        as Map<String, dynamic>)['cle'] as String;
  }

  /// Envoie la sauvegarde complete du compte (remplace la precedente).
  /// Retourne la VERSION serveur resultante (memorisee par l'app pour
  /// detecter plus tard qu'un autre appareil a pousse entre temps).
  Future<int> envoyerCompte(String cle, String data) async {
    final r = await http
        .put(
          Uri.parse('$base/api/compte/data'),
          headers: {'content-type': 'text/plain', 'x-khompas-cle': cle},
          body: data,
        )
        .timeout(const Duration(seconds: 45));
    if (r.statusCode != 200) _lance(r);
    return ((jsonDecode(utf8.decode(r.bodyBytes))
                as Map<String, dynamic>)['version'] as num?)
            ?.toInt() ??
        0;
  }

  /// (version, donnees) du compte, ou null si le compte n'a rien envoye.
  Future<(int, String)?> recupererCompte(String cle) async {
    final r = await http.get(
      Uri.parse('$base/api/compte/data'),
      headers: {'x-khompas-cle': cle},
    ).timeout(const Duration(seconds: 45));
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) _lance(r);
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return (((j['version'] as num?) ?? 0).toInt(), j['data'] as String);
  }

  /// Version serveur du compte, sans telecharger les donnees (0 = vide).
  Future<int> versionCompte(String cle) async {
    final r = await http.get(
      Uri.parse('$base/api/compte/version'),
      headers: {'x-khompas-cle': cle},
    ).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) _lance(r);
    return ((jsonDecode(utf8.decode(r.bodyBytes))
                as Map<String, dynamic>)['version'] as num?)
            ?.toInt() ??
        0;
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
