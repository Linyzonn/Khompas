import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'models.dart';

/// Serveur Khompas par defaut (celui de la beta) : les camarades n'ont
/// aucune URL a configurer. Modifiable dans Reglages.
const String kServeurDefaut = 'https://khompas.linyzonn.deno.net';

/// Etat global de l'app, persiste dans un fichier JSON local.
/// (La cle API, plus sensible, vit dans SharedPreferences.)
class AppModel extends ChangeNotifier {
  static final AppModel instance = AppModel._();
  AppModel._();

  List<Colle> colles = [];
  List<Ds> ds = [];
  List<Chapitre> chapitres = [];
  List<Routine> routines = [];
  List<Devoir> devoirs = [];
  List<Seance> seances = [];
  List<Bilan> bilans = [];
  List<Evenement> evenements = [];
  // Calendrier interne : periodes sans cours (vacances, semaines de
  // revisions) + lundi de reference d'une "semaine A" pour le roulement A/B.
  List<PlageSansCours> sansCours = [];
  // Cahier d'erreurs, tracker d'annales, planning des epreuves orales.
  List<Erreur> erreurs = [];
  List<Annale> annales = [];
  List<EpreuveOrale> oraux = [];
  // Bilan de concours (5/2) : notes/barres des epreuves de l'an dernier.
  List<ResultatConcours> resultatsConcours = [];
  // Zone de vacances scolaires (A/B/C) pour l'import officiel.
  String zoneVacances = '';
  // Oeuvres de francais de l'annee (lecture d'ete + rattrapage de rentree).
  List<Oeuvre> oeuvres = [];
  // Jours OFF (trajet, famille...) : le plan du soir se tait, l'etalement
  // d'ete les evite. Dates a minuit.
  List<DateTime> joursOff = [];
  // true = le plan du soir bascule en preparation des ORAUX (post-ecrits).
  bool modeOraux = false;
  DateTime? refSemaineA;
  // Methode de travail du soir : 'checklist' | 'pomo25' | 'pomo50' | 'pomoAuto'.
  String methodeTravail = 'checklist';
  // Heure limite du soir (minutes depuis minuit, null = pas de limite) :
  // le plan du soir se raccourcit tout seul — le sommeil consolide.
  int? heureLimiteMin;
  // Drapeaux d'alerte (non persistes) affiches sur le tableau de bord.
  bool chargementEchoue = false;
  bool syncConflit = false;
  // Objectif de moyenne par matiere (facultatif, toujours formule en positif).
  Map<String, double> objectifs = {};
  // Date des ecrits : non nulle = MODE REVISIONS CONCOURS actif.
  DateTime? dateConcours;
  String filiere = 'PCSI';
  int groupe = 1;
  // Code de partage du colloscope de ma classe (serveur Khompas).
  String codeClasse = '';
  // Code de GESTION de la classe (seulement chez son createur) : permet de
  // la supprimer du serveur.
  String gestionClasse = '';
  // Priorite par matiere (1 a 3) : ponderation du plan de travail.
  Map<String, int> prios = {};

  String apiKey = '';
  // URL du serveur Khompas (beta) — vide = fonctions serveur masquees.
  String serverUrl = '';
  // Cle du compte anonyme (18 caracteres) — vide = pas de compte.
  String compteCle = '';
  // 5/2 : refait sa 2e annee -> adapte l'import du programme (chapitres
  // deja vus) et, plus tard, le plan de travail.
  bool cinqDemi = false;
  // Premier lancement termine (ecran de bienvenue passe) ?
  bool onboarded = false;
  bool loaded = false;

  Timer? _pushTimer;

  // ---------- Persistance ----------

  Future<File> _dbFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/khompas.json');
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      apiKey = prefs.getString('apiKey') ?? '';
      serverUrl = prefs.getString('serverUrl') ?? kServeurDefaut;
      compteCle = prefs.getString('compteCle') ?? '';
      gestionClasse = prefs.getString('gestionClasse') ?? '';
      onboarded = prefs.getBool('onboarded') ?? false;
      notifsActives = prefs.getBool('notifsActives') ?? false;
      notifVeilleKholle = prefs.getBool('notifVeilleKholle') ?? true;
      notifVeilleDm = prefs.getBool('notifVeilleDm') ?? true;
      _majConnue = prefs.getInt('majConnue') ?? 0;
      String? raw;
      if (kIsWeb) {
        // Version web (PC) : pas de systeme de fichiers, la base vit dans
        // le stockage local du navigateur (via SharedPreferences).
        raw = prefs.getString('db');
      } else {
        final f = await _dbFile();
        if (await f.exists()) raw = await f.readAsString();
      }
      if (raw != null) {
        try {
          final j = jsonDecode(raw) as Map<String, dynamic>;
          // TOUT est parse dans des variables locales avant d'affecter quoi
          // que ce soit : avant, un JSON casse a mi-parcours laissait un
          // etat partiel (colles chargees, chapitres vides) qui pouvait
          // ensuite etre re-sauvegarde tel quel.
          final newColles = ((j['colles'] ?? []) as List)
              .map((e) => Colle.fromJson(e as Map<String, dynamic>))
              .toList();
          final newDs = ((j['ds'] ?? []) as List)
              .map((e) => Ds.fromJson(e as Map<String, dynamic>))
              .toList();
          final newChapitres = ((j['chapitres'] ?? []) as List)
              .map((e) => Chapitre.fromJson(e as Map<String, dynamic>))
              .toList();
          final newRoutines = ((j['routines'] ?? []) as List)
              .map((e) => Routine.fromJson(e as Map<String, dynamic>))
              .toList();
          final newDevoirs = ((j['devoirs'] ?? []) as List)
              .map((e) => Devoir.fromJson(e as Map<String, dynamic>))
              .toList();
          final newSeances = ((j['seances'] ?? []) as List)
              .map((e) => Seance.fromJson(e as Map<String, dynamic>))
              .toList();
          final newObjectifs = ((j['objectifs'] ?? {}) as Map)
              .map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
          final newDateConcours = j['dateConcours'] == null
              ? null
              : DateTime.tryParse(j['dateConcours'] as String);
          final newBilans = ((j['bilans'] ?? []) as List)
              .map((e) => Bilan.fromJson(e as Map<String, dynamic>))
              .toList();
          final newEvenements = ((j['evenements'] ?? []) as List)
              .map((e) => Evenement.fromJson(e as Map<String, dynamic>))
              .toList();
          final newSansCours = ((j['sansCours'] ?? []) as List)
              .map((e) => PlageSansCours.fromJson(e as Map<String, dynamic>))
              .toList();
          final newErreurs = ((j['erreurs'] ?? []) as List)
              .map((e) => Erreur.fromJson(e as Map<String, dynamic>))
              .toList();
          final newAnnales = ((j['annales'] ?? []) as List)
              .map((e) => Annale.fromJson(e as Map<String, dynamic>))
              .toList();
          final newOraux = ((j['oraux'] ?? []) as List)
              .map((e) => EpreuveOrale.fromJson(e as Map<String, dynamic>))
              .toList();
          final newResultats = ((j['resultatsConcours'] ?? []) as List)
              .map((e) => ResultatConcours.fromJson(e as Map<String, dynamic>))
              .toList();
          final newZone = (j['zoneVacances'] ?? '') as String;
          final newOeuvres = ((j['oeuvres'] ?? []) as List)
              .map((e) => Oeuvre.fromJson(e as Map<String, dynamic>))
              .toList();
          final newJoursOff = ((j['joursOff'] ?? []) as List)
              .map((e) => DateTime.tryParse(e.toString()))
              .whereType<DateTime>()
              .toList();
          final newModeOraux = (j['modeOraux'] ?? false) as bool;
          final newRefSemaineA = j['refSemaineA'] == null
              ? null
              : DateTime.tryParse(j['refSemaineA'] as String);
          final newMethode = (j['methodeTravail'] ?? 'checklist') as String;
          final newHeureLimite = j['heureLimiteMin'] as int?;
          final newFiliere = (j['filiere'] ?? 'PCSI') as String;
          final newGroupe = ((j['groupe'] ?? 1) as num).toInt();
          final newCodeClasse = (j['codeClasse'] ?? '') as String;
          final newCinqDemi = (j['cinqDemi'] ?? false) as bool;
          final newPrios = ((j['prios'] ?? {}) as Map)
              .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
          colles = newColles;
          ds = newDs;
          chapitres = newChapitres;
          routines = newRoutines;
          devoirs = newDevoirs;
          seances = newSeances;
          objectifs = newObjectifs;
          dateConcours = newDateConcours;
          bilans = newBilans;
          evenements = newEvenements;
          sansCours = newSansCours;
          erreurs = newErreurs;
          annales = newAnnales;
          oraux = newOraux;
          resultatsConcours = newResultats;
          zoneVacances = newZone;
          oeuvres = newOeuvres;
          joursOff = newJoursOff;
          modeOraux = newModeOraux;
          refSemaineA = newRefSemaineA;
          methodeTravail = newMethode;
          heureLimiteMin = newHeureLimite;
          filiere = newFiliere;
          groupe = newGroupe;
          codeClasse = newCodeClasse;
          cinqDemi = newCinqDemi;
          prios = newPrios;
          // Migration : le code de gestion vivait dans le JSON (donc dans
          // les sauvegardes PARTAGEES — quiconque recevait le fichier
          // pouvait supprimer la classe du serveur). Il vit desormais dans
          // SharedPreferences, comme la cle API.
          final ancienGestion = (j['gestionClasse'] ?? '') as String;
          if (gestionClasse.isEmpty && ancienGestion.isNotEmpty) {
            gestionClasse = ancienGestion;
            await prefs.setString('gestionClasse', gestionClasse);
          }
        } catch (_) {
          // Donnees illisibles : COPIE DE SECOURS AVANT TOUTE ECRITURE —
          // sans elle, le premier save() ecraserait le fichier corrompu
          // avec un etat vide (= semestre perdu). Un bandeau sur le tableau
          // de bord guide ensuite vers Recuperer/Restaurer.
          chargementEchoue = true;
          try {
            if (kIsWeb) {
              await prefs.setString('db_corrompu', raw);
            } else {
              final f = await _dbFile();
              await File('${f.path}.corrompu').writeAsString(raw);
            }
          } catch (_) {
            // meme la copie a echoue : on n'ecrase rien de plus
          }
        }
      }
    } catch (_) {
      // stockage inaccessible : l'app demarre vide, sans planter
    }
    // Migration : canonise les noms de matieres partout ("Mathématiques" et
    // "Maths" etaient deux matieres differentes -> doublons dans toute l'UI).
    // JAMAIS de re-sauvegarde si le chargement a echoue : on ecraserait le
    // fichier principal avec un etat vide (la copie .corrompu ne suffit pas).
    if (_migrerMatieres() && !chargementEchoue) save();
    loaded = true;
    notifyListeners();
    // Taches d'arriere-plan non bloquantes (silencieuses hors ligne).
    verifierVersionCompte();
    synchroniserProgrammes();
  }

  /// Applique [normaliseMatiere] a toutes les donnees. Retourne true si
  /// quelque chose a change. Idempotent (relance sans effet).
  bool _migrerMatieres() {
    var change = false;
    String n(String s) {
      final v = normaliseMatiere(s);
      if (v != s) change = true;
      return v;
    }

    for (final c in colles) {
      c.matiere = n(c.matiere);
    }
    for (final d in ds) {
      d.matiere = n(d.matiere);
    }
    for (final c in chapitres) {
      c.matiere = n(c.matiere);
    }
    for (final r in routines) {
      if (r.matiere.trim().isNotEmpty) r.matiere = n(r.matiere);
    }
    for (final d in devoirs) {
      d.matiere = n(d.matiere);
    }
    for (final s in seances) {
      s.matiere = n(s.matiere);
    }
    for (final b in bilans) {
      b.matiere = n(b.matiere);
    }
    for (final e in evenements) {
      if (e.matiere.trim().isNotEmpty) e.matiere = n(e.matiere);
    }
    for (final e in erreurs) {
      e.matiere = n(e.matiere);
    }
    for (final a in annales) {
      a.matiere = n(a.matiere);
    }
    for (final r in resultatsConcours) {
      r.matiere = n(r.matiere);
    }
    // Maps par matiere : en cas de collision apres normalisation, on garde
    // la valeur la plus haute (prio) / existante (objectif).
    final nouveauxPrios = <String, int>{};
    prios.forEach((k, v) {
      final ck = n(k);
      final actuel = nouveauxPrios[ck];
      nouveauxPrios[ck] = actuel == null ? v : (v > actuel ? v : actuel);
    });
    prios = nouveauxPrios;
    final nouveauxObj = <String, double>{};
    objectifs.forEach((k, v) {
      nouveauxObj.putIfAbsent(n(k), () => v);
    });
    objectifs = nouveauxObj;
    return change;
  }

  /// Fusion MANUELLE de deux matieres (Reglages) : tout ce qui est en
  /// [source] passe en [cible] — pour les cas qu'on ne peut pas deviner
  /// (LV1 -> Anglais, un khôlleur qui ecrit "Analyse" pour "Maths"...).
  void fusionnerMatieres(String source, String cible) {
    if (source == cible) return;
    for (final c in colles) {
      if (c.matiere == source) c.matiere = cible;
    }
    for (final d in ds) {
      if (d.matiere == source) d.matiere = cible;
    }
    for (final c in chapitres) {
      if (c.matiere == source) c.matiere = cible;
    }
    for (final r in routines) {
      if (r.matiere == source) r.matiere = cible;
    }
    for (final d in devoirs) {
      if (d.matiere == source) d.matiere = cible;
    }
    for (final s in seances) {
      if (s.matiere == source) s.matiere = cible;
    }
    for (final b in bilans) {
      if (b.matiere == source) b.matiere = cible;
    }
    for (final e in evenements) {
      if (e.matiere == source) e.matiere = cible;
    }
    for (final e in erreurs) {
      if (e.matiere == source) e.matiere = cible;
    }
    for (final a in annales) {
      if (a.matiere == source) a.matiere = cible;
    }
    for (final r in resultatsConcours) {
      if (r.matiere == source) r.matiere = cible;
    }
    final pSource = prios.remove(source);
    if (pSource != null) {
      final pCible = prios[cible];
      prios[cible] = pCible == null ? pSource : (pSource > pCible ? pSource : pCible);
    }
    final oSource = objectifs.remove(source);
    if (oSource != null) objectifs.putIfAbsent(cible, () => oSource);
    _touch();
  }

  Map<String, dynamic> _snapshot() => {
        'app': 'khompas',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'colles': colles.map((c) => c.toJson()).toList(),
        'ds': ds.map((d) => d.toJson()).toList(),
        'chapitres': chapitres.map((c) => c.toJson()).toList(),
        'routines': routines.map((r) => r.toJson()).toList(),
        'devoirs': devoirs.map((d) => d.toJson()).toList(),
        'seances': seances.map((s) => s.toJson()).toList(),
        'objectifs': objectifs,
        'dateConcours': dateConcours?.toIso8601String(),
        'bilans': bilans.map((b) => b.toJson()).toList(),
        'evenements': evenements.map((e) => e.toJson()).toList(),
        'sansCours': sansCours.map((p) => p.toJson()).toList(),
        'erreurs': erreurs.map((e) => e.toJson()).toList(),
        'annales': annales.map((a) => a.toJson()).toList(),
        'oraux': oraux.map((o) => o.toJson()).toList(),
        'resultatsConcours':
            resultatsConcours.map((r) => r.toJson()).toList(),
        'zoneVacances': zoneVacances,
        'oeuvres': oeuvres.map((o) => o.toJson()).toList(),
        'joursOff': joursOff.map((d) => d.toIso8601String()).toList(),
        'modeOraux': modeOraux,
        'refSemaineA': refSemaineA?.toIso8601String(),
        'methodeTravail': methodeTravail,
        'heureLimiteMin': heureLimiteMin,
        'filiere': filiere,
        'groupe': groupe,
        'codeClasse': codeClasse,
        // PAS de gestionClasse ici : le snapshot part dans les sauvegardes
        // partagees et sur le compte — le code de gestion (droit de
        // suppression de la classe) reste local, dans SharedPreferences.
        'cinqDemi': cinqDemi,
        'prios': prios,
      };

  Future<void> save() async {
    try {
      final raw = jsonEncode(_snapshot());
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('db', raw);
      } else {
        // Ecriture ATOMIQUE : on ecrit dans un .tmp puis on renomme —
        // une coupure en pleine ecriture ne corrompt jamais le fichier.
        final f = await _dbFile();
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(raw);
        try {
          await tmp.rename(f.path);
        } catch (_) {
          if (await f.exists()) await f.delete();
          await tmp.rename(f.path);
        }
      }
    } catch (_) {
      // Stockage indisponible : l'app reste utilisable, sans persistance.
    }
    _programmerPush();
  }

  // ---------- Compte (synchronisation) ----------

  /// Envoi automatique vers le compte, quelques secondes apres la derniere
  /// modification (debounce). Echec silencieux : hors ligne, la prochaine
  /// modification retentera.
  void _programmerPush() {
    if (compteCle.isEmpty || serverUrl.isEmpty) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(seconds: 3), () async {
      try {
        final v =
            await ApiKhompas(serverUrl).envoyerCompte(compteCle, exportJson());
        await _memoriserVersion(v);
        if (syncConflit || compteEnAvance) {
          syncConflit = false;
          compteEnAvance = false;
          notifyListeners();
        }
      } catch (e) {
        // Le serveur refuse car un autre appareil a des donnees plus
        // recentes -> bandeau sur le tableau de bord (sinon : hors ligne,
        // tant pis pour cette fois).
        if (e.toString().contains('plus récentes')) {
          syncConflit = true;
          notifyListeners();
        }
      }
    });
  }

  Future<void> saveCompteCle(String cle) async {
    compteCle = cle.trim().toUpperCase();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('compteCle', compteCle);
    notifyListeners();
  }

  /// Dissocie l'appareil du compte (les donnees restent locales ET sur le
  /// serveur — seule la cle locale est oubliee).
  Future<void> deconnecterCompte() async {
    compteCle = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('compteCle');
    notifyListeners();
  }

  /// Connecte l'appareil a un compte existant : enregistre la cle et
  /// RESTAURE les donnees du compte (remplace les donnees locales).
  /// Retourne un resume, ou une explication si le compte est encore vide.
  Future<String> connecterCompte(String cle) async {
    final propre = cle.trim().toUpperCase();
    final resultat = await ApiKhompas(serverUrl).recupererCompte(propre);
    await saveCompteCle(propre);
    final data = resultat?.$2;
    if (resultat != null) await _memoriserVersion(resultat.$1);
    if (data == null || data.trim().isEmpty) {
      // Compte vide : on y envoie au contraire les donnees locales.
      _programmerPush();
      return 'compte encore vide — tes données locales vont y être envoyées';
    }
    return importJson(data);
  }

  /// Envoi immediat (bouton Reglages).
  Future<void> pousserCompte() async {
    final v = await ApiKhompas(serverUrl).envoyerCompte(compteCle, exportJson());
    await _memoriserVersion(v);
    syncConflit = false;
    compteEnAvance = false;
    notifyListeners();
  }

  /// Recuperation immediate (bouton Reglages) : remplace les donnees locales.
  Future<String> tirerCompte() async {
    final resultat = await ApiKhompas(serverUrl).recupererCompte(compteCle);
    final data = resultat?.$2;
    if (data == null || data.trim().isEmpty) {
      throw Exception('aucune donnée sur ce compte pour le moment.');
    }
    await _memoriserVersion(resultat!.$1);
    syncConflit = false;
    compteEnAvance = false;
    return importJson(data);
  }

  /// Derniere version serveur que CET appareil connait (prefs locales).
  int _majConnue = 0;
  // true = le serveur detient une version plus recente que ce que cet
  // appareil a vu -> bannière "Récupérer" avant de modifier quoi que ce soit.
  bool compteEnAvance = false;

  Future<void> _memoriserVersion(int v) async {
    if (v == 0) return;
    _majConnue = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('majConnue', v);
  }

  /// Verification legere au demarrage : un autre appareil a-t-il pousse
  /// depuis la derniere fois ? (fire-and-forget, silencieux hors ligne)
  Future<void> verifierVersionCompte() async {
    if (compteCle.isEmpty || serverUrl.isEmpty) return;
    try {
      final v = await ApiKhompas(serverUrl).versionCompte(compteCle);
      if (v != 0 && _majConnue != 0 && v != _majConnue) {
        compteEnAvance = true;
        notifyListeners();
      }
    } catch (_) {
      // hors ligne : tant pis, la garde 409 reste le filet
    }
  }

  void setCinqDemi(bool v) {
    cinqDemi = v;
    _touch();
  }

  Future<void> setOnboarded() async {
    onboarded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded', true);
    notifyListeners();
  }

  // ---------- Sauvegarde / restauration ----------

  /// Contenu du fichier de sauvegarde partageable (meme format que le
  /// stockage interne, indente pour rester lisible).
  String exportJson() => const JsonEncoder.withIndent('  ').convert(_snapshot());

  /// Restaure une sauvegarde : REMPLACE toutes les donnees actuelles
  /// (la cle API n'est pas concernee). Tout est parse AVANT d'ecraser quoi
  /// que ce soit : en cas de fichier invalide, une exception est lancee et
  /// les donnees restent intactes. Retourne un petit resume.
  String importJson(String raw) {
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw Exception("ce fichier n'est pas un JSON valide.");
    }
    if (decoded is! Map<String, dynamic> ||
        (decoded['colles'] == null &&
            decoded['ds'] == null &&
            decoded['chapitres'] == null)) {
      throw Exception('ce fichier ne ressemble pas à une sauvegarde Khompas.');
    }
    try {
      final newColles = ((decoded['colles'] ?? []) as List)
          .map((e) => Colle.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      final newDs = ((decoded['ds'] ?? []) as List)
          .map((e) => Ds.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      final newChapitres = ((decoded['chapitres'] ?? []) as List)
          .map((e) => Chapitre.fromJson(e as Map<String, dynamic>))
          .toList();
      final newRoutines = ((decoded['routines'] ?? []) as List)
          .map((e) => Routine.fromJson(e as Map<String, dynamic>))
          .toList();
      final newDevoirs = ((decoded['devoirs'] ?? []) as List)
          .map((e) => Devoir.fromJson(e as Map<String, dynamic>))
          .toList();
      final newSeances = ((decoded['seances'] ?? []) as List)
          .map((e) => Seance.fromJson(e as Map<String, dynamic>))
          .toList();
      final newObjectifs = ((decoded['objectifs'] ?? {}) as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
      final newDateConcours = decoded['dateConcours'] == null
          ? null
          : DateTime.tryParse(decoded['dateConcours'] as String);
      final newBilans = ((decoded['bilans'] ?? []) as List)
          .map((e) => Bilan.fromJson(e as Map<String, dynamic>))
          .toList();
      final newEvenements = ((decoded['evenements'] ?? []) as List)
          .map((e) => Evenement.fromJson(e as Map<String, dynamic>))
          .toList();
      final newSansCours = ((decoded['sansCours'] ?? []) as List)
          .map((e) => PlageSansCours.fromJson(e as Map<String, dynamic>))
          .toList();
      final newErreurs = ((decoded['erreurs'] ?? []) as List)
          .map((e) => Erreur.fromJson(e as Map<String, dynamic>))
          .toList();
      final newAnnales = ((decoded['annales'] ?? []) as List)
          .map((e) => Annale.fromJson(e as Map<String, dynamic>))
          .toList();
      final newOraux = ((decoded['oraux'] ?? []) as List)
          .map((e) => EpreuveOrale.fromJson(e as Map<String, dynamic>))
          .toList();
      final newResultats = ((decoded['resultatsConcours'] ?? []) as List)
          .map((e) => ResultatConcours.fromJson(e as Map<String, dynamic>))
          .toList();
      final newZone = (decoded['zoneVacances'] ?? zoneVacances) as String;
      final newOeuvres = ((decoded['oeuvres'] ?? []) as List)
          .map((e) => Oeuvre.fromJson(e as Map<String, dynamic>))
          .toList();
      final newJoursOff = ((decoded['joursOff'] ?? []) as List)
          .map((e) => DateTime.tryParse(e.toString()))
          .whereType<DateTime>()
          .toList();
      final newModeOraux = (decoded['modeOraux'] ?? false) as bool;
      final newRefSemaineA = decoded['refSemaineA'] == null
          ? null
          : DateTime.tryParse(decoded['refSemaineA'] as String);
      final newMethode = (decoded['methodeTravail'] ?? methodeTravail) as String;
      final newHeureLimite = decoded['heureLimiteMin'] as int?;
      final newFiliere = (decoded['filiere'] ?? filiere) as String;
      final newGroupe = ((decoded['groupe'] ?? groupe) as num).toInt();
      final newCodeClasse = (decoded['codeClasse'] ?? codeClasse) as String;
      final newCinqDemi = (decoded['cinqDemi'] ?? cinqDemi) as bool;
      final newPrios = ((decoded['prios'] ?? {}) as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
      colles = newColles;
      ds = newDs;
      chapitres = newChapitres;
      routines = newRoutines;
      devoirs = newDevoirs;
      seances = newSeances;
      objectifs = newObjectifs;
      dateConcours = newDateConcours;
      bilans = newBilans;
      evenements = newEvenements;
      sansCours = newSansCours;
      erreurs = newErreurs;
      annales = newAnnales;
      oraux = newOraux;
      resultatsConcours = newResultats;
      zoneVacances = newZone;
      oeuvres = newOeuvres;
      joursOff = newJoursOff;
      modeOraux = newModeOraux;
      refSemaineA = newRefSemaineA;
      methodeTravail = newMethode;
      heureLimiteMin = newHeureLimite;
      filiere = newFiliere;
      groupe = newGroupe;
      codeClasse = newCodeClasse;
      cinqDemi = newCinqDemi;
      prios = newPrios;
    } catch (_) {
      throw Exception('sauvegarde illisible ou incomplète — rien n\'a été modifié.');
    }
    // Vieilles sauvegardes : le code de gestion y figurait. On le recupere
    // s'il nous manque (cast defensif : un champ inattendu ne doit pas
    // laisser l'etat a moitie mute).
    final ancienGestion = decoded['gestionClasse'];
    if (gestionClasse.isEmpty && ancienGestion is String &&
        ancienGestion.isNotEmpty) {
      setGestionClasse(ancienGestion);
    }
    // Une sauvegarde d'avant-0.12 peut reintroduire des doublons de
    // matieres : on re-normalise tout de suite, pas au prochain redemarrage.
    _migrerMatieres();
    _touch();
    return '${colles.length} khôlle(s), ${ds.length} DS, ${chapitres.length} chapitre(s)';
  }

  Future<void> saveApiKey(String key) async {
    apiKey = key.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('apiKey', apiKey);
    notifyListeners();
  }

  Future<void> saveServerUrl(String url) async {
    serverUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('serverUrl', serverUrl);
    notifyListeners();
  }

  void setCodeClasse(String code) {
    codeClasse = code.trim().toUpperCase();
    _touch();
  }

  Future<void> setGestionClasse(String gestion) async {
    gestionClasse = gestion.trim().toUpperCase();
    // Hors snapshot (voir _snapshot) : persiste dans SharedPreferences.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gestionClasse', gestionClasse);
    notifyListeners();
  }

  /// Menage de rentree (passage en 2e annee) : supprime les kholles
  /// terminees. Notes de DS, chapitres et seances sont conserves.
  int nettoyerCollesPassees() {
    final now = DateTime.now();
    final avant = colles.length;
    colles.removeWhere((c) => c.end.isBefore(now));
    _touch();
    return avant - colles.length;
  }

  // ---------- Programmes de colles (la 2e boucle virale) ----------

  static String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Applique un programme de colle a TOUTES les kholles de [matiere] de la
  /// semaine de [date], et le partage avec la classe si demande.
  Future<void> definirProgramme(String matiere, DateTime date, String texte,
      {bool partager = true}) async {
    final lundi = mondayOf(date);
    final fin = lundi.add(const Duration(days: 7));
    for (final c in colles) {
      if (c.matiere == matiere &&
          !c.start.isBefore(lundi) &&
          c.start.isBefore(fin)) {
        c.programme = texte.trim();
      }
    }
    _touch();
    if (partager && codeClasse.isNotEmpty && serverUrl.isNotEmpty) {
      try {
        await ApiKhompas(serverUrl).envoyerProgramme(
            codeClasse, _isoDate(lundi), matiere.toLowerCase(), texte.trim());
      } catch (_) {
        // hors ligne : le programme reste au moins en local
      }
    }
  }

  /// Recupere les programmes partages par la classe (semaine courante et
  /// suivante) et les applique aux kholles SANS programme. Silencieux.
  Future<void> synchroniserProgrammes() async {
    if (codeClasse.isEmpty || serverUrl.isEmpty || colles.isEmpty) return;
    try {
      final api = ApiKhompas(serverUrl);
      var change = false;
      final lundiCourant = mondayOf(DateTime.now());
      for (final lundi in [
        lundiCourant,
        lundiCourant.add(const Duration(days: 7)),
      ]) {
        final progs = await api.lireProgrammes(codeClasse, _isoDate(lundi));
        if (progs.isEmpty) continue;
        final fin = lundi.add(const Duration(days: 7));
        for (final c in colles) {
          if (c.programme.trim().isNotEmpty) continue;
          if (c.start.isBefore(lundi) || !c.start.isBefore(fin)) continue;
          final texte = progs[c.matiere.toLowerCase()];
          if (texte != null && texte.trim().isNotEmpty) {
            c.programme = texte.trim();
            change = true;
          }
        }
      }
      if (change) _touch();
    } catch (_) {
      // hors ligne : on reessaiera au prochain lancement
    }
  }

  /// Entree MANUELLE dans la repetition espacee (fiche chapitre) : "vu
  /// aujourd'hui -> reviser demain" — la porte d'entree sans EDT rempli.
  void demarrerEspacement(String chapitreId, {DateTime? maintenant}) {
    final now = maintenant ?? DateTime.now();
    final i = chapitres.indexWhere((c) => c.id == chapitreId);
    if (i < 0) return;
    final c = chapitres[i];
    if (c.etape < 1) c.etape = 1;
    c.entame = false;
    c.intervalleJours = 1;
    c.dernierRevu = now;
    final demain = now.add(const Duration(days: 1));
    c.prochaineRevision = DateTime(demain.year, demain.month, demain.day);
    _touch();
  }

  void _touch() {
    save();
    notifyListeners();
  }

  // ---------- Khôlles ----------

  /// Ajoute des colles en evitant les doublons exacts (meme matiere + meme debut).
  int addColles(List<Colle> nouvelles) {
    var added = 0;
    for (final c in nouvelles) {
      final doublon = colles.any((e) =>
          e.matiere.toLowerCase() == c.matiere.toLowerCase() &&
          e.start == c.start);
      if (!doublon) {
        colles.add(c);
        added++;
      }
    }
    colles.sort((a, b) => a.start.compareTo(b.start));
    _touch();
    return added;
  }

  void updateColle(Colle c) {
    final i = colles.indexWhere((e) => e.id == c.id);
    if (i >= 0) colles[i] = c;
    colles.sort((a, b) => a.start.compareTo(b.start));
    _touch();
  }

  void deleteColle(String id) {
    colles.removeWhere((e) => e.id == id);
    _touch();
  }

  // ---------- DS ----------

  void addDs(Ds d) {
    ds.add(d);
    ds.sort((a, b) => a.date.compareTo(b.date));
    _touch();
  }

  /// Ajoute un lot de DS (import planning) en evitant les doublons
  /// (meme matiere + meme jour). Retourne le nombre reellement ajoute.
  int addDsList(List<Ds> nouveaux) {
    var added = 0;
    for (final d in nouveaux) {
      final doublon = ds.any((e) =>
          e.matiere.toLowerCase() == d.matiere.toLowerCase() &&
          e.date.year == d.date.year &&
          e.date.month == d.date.month &&
          e.date.day == d.date.day);
      if (!doublon) {
        ds.add(d);
        added++;
      }
    }
    ds.sort((a, b) => a.date.compareTo(b.date));
    _touch();
    return added;
  }

  void updateDs(Ds d) {
    final i = ds.indexWhere((e) => e.id == d.id);
    if (i >= 0) ds[i] = d;
    _touch();
  }

  void deleteDs(String id) {
    ds.removeWhere((e) => e.id == id);
    _touch();
  }

  // ---------- Chapitres ----------

  void addChapitre(Chapitre c) {
    chapitres.add(c);
    _touch();
  }

  /// Ajoute un lot de chapitres (import du programme officiel) en evitant
  /// les doublons (meme matiere + meme nom). Retourne le nombre ajoute.
  int addChapitresList(List<Chapitre> nouveaux) {
    var added = 0;
    for (final c in nouveaux) {
      final doublon = chapitres.any((e) =>
          e.matiere.toLowerCase() == c.matiere.toLowerCase() &&
          e.nom.toLowerCase() == c.nom.toLowerCase());
      if (!doublon) {
        chapitres.add(c);
        added++;
      }
    }
    _touch();
    return added;
  }

  void updateChapitre(Chapitre c) {
    final i = chapitres.indexWhere((e) => e.id == c.id);
    if (i >= 0) chapitres[i] = c;
    _touch();
  }

  void deleteChapitre(String id) {
    chapitres.removeWhere((e) => e.id == id);
    _touch();
  }

  // ---------- Devoirs a rendre (DM / DNS) ----------

  void addDevoir(Devoir d) {
    devoirs.add(d);
    devoirs.sort((a, b) => a.dateRendu.compareTo(b.dateRendu));
    _touch();
  }

  void updateDevoir(Devoir d) {
    final i = devoirs.indexWhere((e) => e.id == d.id);
    if (i >= 0) devoirs[i] = d;
    devoirs.sort((a, b) => a.dateRendu.compareTo(b.dateRendu));
    _touch();
  }

  void deleteDevoir(String id) {
    devoirs.removeWhere((e) => e.id == id);
    _touch();
  }

  /// Devoirs pas encore rendus (les rendus recents restent visibles ailleurs).
  List<Devoir> devoirsARendre() =>
      devoirs.where((d) => !d.rendu).toList()
        ..sort((a, b) => a.dateRendu.compareTo(b.dateRendu));

  // ---------- Seances de travail (plan du soir coche) ----------

  void addSeance(String matiere, int minutes) {
    seances.add(Seance(matiere: matiere, date: DateTime.now(), minutes: minutes));
    // ~13 mois d'historique : les stats de progression sur l'annee (roadmap)
    // en auront besoin — ne pas re-raccourcir sans y penser.
    final limite = DateTime.now().subtract(const Duration(days: 400));
    seances.removeWhere((s) => s.date.isBefore(limite));
    _touch();
  }

  /// Minutes travaillees cette semaine, par matiere (+ cle '' = total).
  Map<String, int> minutesSemaine() {
    final lundi = mondayOf(DateTime.now());
    final out = <String, int>{'': 0};
    for (final s in seances) {
      if (s.date.isBefore(lundi)) continue;
      out[s.matiere] = (out[s.matiere] ?? 0) + s.minutes;
      out[''] = out['']! + s.minutes;
    }
    return out;
  }

  // ---------- Objectifs (facultatifs, jamais culpabilisants) ----------

  void setObjectif(String matiere, double? obj) {
    if (obj == null) {
      objectifs.remove(matiere);
    } else {
      objectifs[matiere] = obj;
    }
    _touch();
  }

  // ---------- Mode revisions concours ----------

  void setDateConcours(DateTime? d) {
    dateConcours = d;
    _touch();
  }

  // ---------- Semaine type (routines) ----------

  void addRoutine(Routine r) {
    routines.add(r);
    _trierRoutines();
    _touch();
  }

  void updateRoutine(Routine r) {
    final i = routines.indexWhere((e) => e.id == r.id);
    if (i >= 0) routines[i] = r;
    _trierRoutines();
    _touch();
  }

  void deleteRoutine(String id) {
    routines.removeWhere((e) => e.id == id);
    _touch();
  }

  void _trierRoutines() {
    routines.sort((a, b) =>
        a.jour != b.jour ? a.jour.compareTo(b.jour) : a.debutMin.compareTo(b.debutMin));
  }

  /// Toutes les routines d'un jour de semaine (pour l'ecran d'edition,
  /// sans tenir compte du calendrier ni du roulement).
  List<Routine> routinesJourBrut(int weekday) =>
      routines.where((r) => r.jour == weekday).toList()
        ..sort((a, b) => a.debutMin.compareTo(b.debutMin));

  // ---------- Calendrier interne ----------

  /// La plage sans cours qui couvre [d], ou null (vacances, revisions...).
  PlageSansCours? plageSansCours(DateTime d) {
    for (final p in sansCours) {
      if (p.contient(d)) return p;
    }
    return null;
  }

  /// Semaine A ou B ? true = A. Sans reference definie, tout est "A".
  bool semaineEstA(DateTime d) {
    if (refSemaineA == null) return true;
    final diff = mondayOf(d).difference(mondayOf(refSemaineA!)).inDays;
    return (diff ~/ 7) % 2 == 0;
  }

  /// L'emploi du temps REEL d'une date : jour de semaine + roulement A/B
  /// + rien pendant les vacances / semaines de revisions.
  List<Routine> routinesLe(DateTime d) {
    if (plageSansCours(d) != null) return [];
    final estA = semaineEstA(d);
    return routines
        .where((r) =>
            r.jour == d.weekday &&
            (r.semaines == 0 ||
                (r.semaines == 1 && estA) ||
                (r.semaines == 2 && !estA)))
        .toList()
      ..sort((a, b) => a.debutMin.compareTo(b.debutMin));
  }

  void setZoneVacances(String zone) {
    zoneVacances = zone.trim().toUpperCase();
    _touch();
  }

  // ---------- Oeuvres de francais ----------

  void addOeuvre(Oeuvre o) {
    oeuvres.add(o);
    _touch();
  }

  void updateOeuvre(Oeuvre o) {
    final i = oeuvres.indexWhere((x) => x.id == o.id);
    if (i >= 0) oeuvres[i] = o;
    _touch();
  }

  void deleteOeuvre(String id) {
    oeuvres.removeWhere((o) => o.id == id);
    _touch();
  }

  List<Oeuvre> oeuvresNonFinies() =>
      oeuvres.where((o) => !o.finie).toList();

  // ---------- Jours off ----------

  bool estJourOff(DateTime d) {
    final jour = DateTime(d.year, d.month, d.day);
    return joursOff.any((o) =>
        o.year == jour.year && o.month == jour.month && o.day == jour.day);
  }

  /// Ajoute ou retire un jour off. Purge au passage les jours off de plus
  /// de 60 jours dans le passe (meme regle que les evenements).
  void toggleJourOff(DateTime d) {
    final jour = DateTime(d.year, d.month, d.day);
    final limite = DateTime.now().subtract(const Duration(days: 60));
    joursOff.removeWhere((o) => o.isBefore(limite));
    if (estJourOff(jour)) {
      joursOff.removeWhere((o) =>
          o.year == jour.year && o.month == jour.month && o.day == jour.day);
    } else {
      joursOff.add(jour);
      joursOff.sort();
    }
    _touch();
  }

  void addPlageSansCours(PlageSansCours p) {
    sansCours.add(p);
    sansCours.sort((a, b) => a.debut.compareTo(b.debut));
    _touch();
  }

  void deletePlageSansCours(String id) {
    sansCours.removeWhere((p) => p.id == id);
    _touch();
  }

  void setRefSemaineA(DateTime? d) {
    refSemaineA = d;
    _touch();
  }

  Future<void> saveMethodeTravail(String methode) async {
    methodeTravail = methode;
    _touch();
  }

  void setHeureLimite(int? minutesDepuisMinuit) {
    heureLimiteMin = minutesDepuisMinuit;
    _touch();
  }

  // ---------- Evenements ponctuels ----------

  void addEvenement(Evenement e) {
    evenements.add(e);
    // Menage : on ne garde pas les evenements passes depuis > 60 jours.
    final limite = DateTime.now().subtract(const Duration(days: 60));
    evenements.removeWhere((x) => x.date.isBefore(limite));
    evenements.sort((a, b) => a.date != b.date
        ? a.date.compareTo(b.date)
        : a.debutMin.compareTo(b.debutMin));
    _touch();
  }

  void updateEvenement(Evenement e) {
    final i = evenements.indexWhere((x) => x.id == e.id);
    if (i >= 0) evenements[i] = e;
    evenements.sort((a, b) => a.date != b.date
        ? a.date.compareTo(b.date)
        : a.debutMin.compareTo(b.debutMin));
    _touch();
  }

  void deleteEvenement(String id) {
    evenements.removeWhere((x) => x.id == id);
    _touch();
  }

  /// Evenements ponctuels d'une date, tries par heure.
  List<Evenement> evenementsLe(DateTime d) => evenements
      .where((e) =>
          e.date.year == d.year &&
          e.date.month == d.month &&
          e.date.day == d.day)
      .toList()
    ..sort((a, b) => a.debutMin.compareTo(b.debutMin));

  // ---------- Bilans de journee ----------

  Bilan? bilanPour(DateTime jour, String routineId) {
    final j = DateTime(jour.year, jour.month, jour.day);
    for (final b in bilans) {
      if (b.routineId == routineId &&
          b.jour.year == j.year &&
          b.jour.month == j.month &&
          b.jour.day == j.day) {
        return b;
      }
    }
    return null;
  }

  /// Enregistre (ou remplace) le bilan d'un creneau. Si c'est un COURS avec
  /// un chapitre :
  /// - [chapitreTermine] (defaut) : le chapitre passe au moins en "vu en
  ///   cours" et la repetition espacee demarre (revision demain) ;
  /// - chapitre PAS termine (le prof est en plein dedans) : on marque
  ///   seulement [Chapitre.entame] — pas d'etape, pas d'espacement. Un
  ///   chapitre a moitie vu n'est pas un chapitre vu.
  void setBilan(Bilan b, {bool chapitreTermine = true}) {
    bilans.removeWhere((e) =>
        e.routineId == b.routineId &&
        e.jour.year == b.jour.year &&
        e.jour.month == b.jour.month &&
        e.jour.day == b.jour.day);
    bilans.add(b);
    // ~13 mois d'historique, ALIGNE sur les seances : les stats annuelles
    // de la roadmap en auront besoin (ne pas re-raccourcir sans y penser).
    final limite = DateTime.now().subtract(const Duration(days: 400));
    bilans.removeWhere((e) => e.jour.isBefore(limite));
    if (b.chapitreId != null) {
      final i = chapitres.indexWhere((c) => c.id == b.chapitreId);
      if (i >= 0) {
        if (chapitreTermine) {
          chapitres[i].entame = false;
          if (chapitres[i].etape < 1) chapitres[i].etape = 1;
          // Repetition espacee : cours vu aujourd'hui -> revision demain
          // (la regle d'or, formalisee — le point de depart de l'espacement).
          final demain = DateTime.now().add(const Duration(days: 1));
          chapitres[i].prochaineRevision =
              DateTime(demain.year, demain.month, demain.day);
          chapitres[i].intervalleJours = 1;
        } else {
          chapitres[i].entame = true;
        }
      }
    }
    _touch();
  }

  /// Creneaux de cours (matiere renseignee) deja TERMINES aujourd'hui et
  /// sans bilan — pour proposer le recap a l'ouverture de l'app.
  List<Routine> creneauxSansBilan(DateTime d) {
    final nowMin = d.hour * 60 + d.minute;
    return routinesLe(d)
        .where((r) =>
            r.matiere.trim().isNotEmpty &&
            r.debutMin + r.dureeMin <= nowMin &&
            bilanPour(d, r.id) == null)
        .toList();
  }

  /// Auto-evaluation en 1 tap apres une revision espacee ('difficile',
  /// 'cava' ou 'facile') : ajuste l'intervalle (et la maitrise aux bords),
  /// programme la prochaine revision. Regles simples et explicables —
  /// pas de SM-2 opaque — mais calibrees sur la litterature :
  ///  - "ca va" = "j'ai eu du mal mais ca passe" -> x1.7 (l'ancien x2
  ///    allongeait aussi vite qu'une reussite franche) ;
  ///  - "facile" -> x2.5 (expansion classique type SM-2) ;
  ///  - un chapitre chroniquement dur (2 "difficile" recents ou plus)
  ///    ralentit a x1.5 : sans cette memoire des echecs, il oscillait
  ///    eternellement entre 2 et 4 jours.
  void evaluerRevision(String chapitreId, String verdict,
      {DateTime? maintenant}) {
    final i = chapitres.indexWhere((c) => c.id == chapitreId);
    if (i < 0) return;
    final c = chapitres[i];
    switch (verdict) {
      case 'difficile':
        c.intervalleJours = 2;
        c.echecs++;
        if (c.maitrise > 0) c.maitrise--;
        break;
      case 'facile':
        c.intervalleJours = (c.intervalleJours * 2.5).round().clamp(1, 45);
        c.echecs = 0;
        if (c.maitrise < 4) c.maitrise++;
        break;
      default: // cava
        final mult = c.echecs >= 2 ? 1.5 : 1.7;
        c.intervalleJours = (c.intervalleJours * mult).round().clamp(1, 45);
    }
    // L'espacement s'ancre sur la date OU LA REVISION ETAIT DUE (si le
    // retard reste raisonnable, < 7 j) plutot que sur aujourd'hui :
    // reviser avec 3 jours de retard ne doit pas decaler toute la suite.
    final now = maintenant ?? DateTime.now();
    var base = now;
    final due = c.prochaineRevision;
    if (due != null) {
      final retard = DateTime(now.year, now.month, now.day)
          .difference(DateTime(due.year, due.month, due.day))
          .inDays;
      if (retard > 0 && retard < 7) base = due;
    }
    var prochaine = DateTime(base.year, base.month, base.day)
        .add(Duration(days: c.intervalleJours));
    // Jamais dans le passe : au pire, demain.
    final demain = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    if (prochaine.isBefore(demain)) prochaine = demain;
    c.prochaineRevision = prochaine;
    c.dernierRevu = now;
    _touch();
  }

  /// Recalibrage apres une mauvaise note : les chapitres designes repassent
  /// fragiles (maitrise plafonnee a 2) et leur revision espacee reprend a
  /// demain avec un intervalle court.
  void recalibrerChapitres(List<String> ids, {DateTime? maintenant}) {
    final demain =
        (maintenant ?? DateTime.now()).add(const Duration(days: 1));
    for (final id in ids) {
      final i = chapitres.indexWhere((c) => c.id == id);
      if (i < 0) continue;
      final c = chapitres[i];
      if (c.maitrise > 2) c.maitrise = 2;
      c.intervalleJours = 1;
      c.prochaineRevision = DateTime(demain.year, demain.month, demain.day);
    }
    _touch();
  }

  // ---------- Cahier d'erreurs ----------

  void addErreur(Erreur e) {
    erreurs.insert(0, e);
    _touch();
  }

  void updateErreur(Erreur e) {
    final i = erreurs.indexWhere((x) => x.id == e.id);
    if (i >= 0) erreurs[i] = e;
    _touch();
  }

  void deleteErreur(String id) {
    erreurs.removeWhere((e) => e.id == id);
    _touch();
  }

  /// Erreurs d'une matiere, les non-refaites d'abord (les plus recentes en
  /// tete dans chaque groupe).
  List<Erreur> erreursDe(String matiere) {
    final l = erreurs.where((e) => e.matiere == matiere).toList();
    l.sort((a, b) => a.refaite != b.refaite
        ? (a.refaite ? 1 : -1)
        : b.date.compareTo(a.date));
    return l;
  }

  /// Repartition des erreurs NON refaites par type ("Calcul" -> 3...).
  Map<String, int> statsErreurs(String matiere) {
    final out = <String, int>{};
    for (final e in erreurs) {
      if (e.matiere == matiere && !e.refaite) {
        out[e.type] = (out[e.type] ?? 0) + 1;
      }
    }
    return out;
  }

  // ---------- Annales ----------

  void addAnnale(Annale a) {
    annales.add(a);
    annales.sort((x, y) => x.matiere != y.matiere
        ? x.matiere.compareTo(y.matiere)
        : y.annee.compareTo(x.annee));
    _touch();
  }

  void updateAnnale(Annale a) {
    final i = annales.indexWhere((x) => x.id == a.id);
    if (i >= 0) annales[i] = a;
    _touch();
  }

  void deleteAnnale(String id) {
    annales.removeWhere((a) => a.id == id);
    _touch();
  }

  // ---------- Bilan de concours (5/2) ----------

  void addResultatConcours(ResultatConcours r) {
    r.matiere = normaliseMatiere(r.matiere);
    resultatsConcours.add(r);
    resultatsConcours.sort((a, b) => a.concours != b.concours
        ? a.concours.compareTo(b.concours)
        : a.epreuve.compareTo(b.epreuve));
    _touch();
  }

  void updateResultatConcours(ResultatConcours r) {
    final i = resultatsConcours.indexWhere((x) => x.id == r.id);
    if (i >= 0) resultatsConcours[i] = r..matiere = normaliseMatiere(r.matiere);
    _touch();
  }

  void deleteResultatConcours(String id) {
    resultatsConcours.removeWhere((r) => r.id == id);
    _touch();
  }

  /// « Où tu perds des points » : deficit PONDERE par matiere, calcule sur
  /// les resultats de concours saisis.
  ///  - avec barre :   coeff x max(0, barre - note) ;
  ///  - sans barre :   coeff x max(0, mediane de TES notes - note) — la
  ///    comparaison se fait alors a ton propre niveau, pas a une barre
  ///    inventee.
  /// Retourne {matiere -> deficit}, trie n'est PAS garanti (trier a
  /// l'affichage). Matieres sans deficit incluses a 0 pour la transparence.
  Map<String, double> deficitsConcours() {
    final notes = resultatsConcours
        .where((r) => r.note != null)
        .map((r) => r.note!)
        .toList()
      ..sort();
    if (notes.isEmpty) return {};
    final mediane = notes[notes.length ~/ 2];
    final out = <String, double>{};
    for (final r in resultatsConcours) {
      if (r.note == null || r.matiere.trim().isEmpty) continue;
      final ref = r.barre ?? mediane;
      final deficit = (ref - r.note!) * r.coeff;
      out[r.matiere] = (out[r.matiere] ?? 0) + (deficit > 0 ? deficit : 0);
    }
    return out;
  }

  /// Applique les deficits aux priorites de matieres (1-3) : tiers haut du
  /// deficit -> 3, tiers moyen -> 2, reste -> 1. Ne touche que les matieres
  /// presentes dans le bilan (les autres prios restent telles quelles).
  /// Toujours declenche par un BOUTON explicite — jamais en silence.
  void appliquerPrioritesDepuisDeficits() {
    final d = deficitsConcours();
    if (d.isEmpty) return;
    final tri = d.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    for (var i = 0; i < tri.length; i++) {
      final tiers = (i * 3) ~/ tri.length; // 0 = haut, 2 = bas
      prios[tri[i].key] = tri[i].value <= 0 ? 1 : (3 - tiers).clamp(1, 3);
    }
    _touch();
  }

  /// Planifie la REACTIVATION D'ETE : repartit la prochaine revision de
  /// tous les chapitres commences (etape > 0) uniformement sur les jours
  /// restants de la plage d'ete (matieres prioritaires d'abord), intervalle
  /// remis a 1. Le flux « rappels du jour » les sert ensuite a cadence
  /// reguliere — au lieu d'un mur de dette le premier jour.
  /// Retourne le nombre de chapitres planifies (0 si pas de plage d'ete).
  int etalerReactivation({DateTime? maintenant}) {
    final now = maintenant ?? DateTime.now();
    final plage = plageSansCours(now);
    if (plage == null || plage.type != 'ete') return 0;
    final aujourdHui = DateTime(now.year, now.month, now.day);
    final finPlage = DateTime(plage.fin.year, plage.fin.month, plage.fin.day);
    var joursRestants = finPlage.difference(aujourdHui).inDays;
    if (joursRestants < 1) joursRestants = 1;
    final aPlanifier = chapitres.where((c) => c.etape > 0).toList()
      ..sort((a, b) {
        final pa = prios[a.matiere] ?? 2;
        final pb = prios[b.matiere] ?? 2;
        if (pa != pb) return pb.compareTo(pa); // prioritaires d'abord
        return a.maitrise.compareTo(b.maitrise); // fragiles d'abord
      });
    if (aPlanifier.isEmpty) return 0;
    // Jours DISPONIBLES de la plage (demain -> fin), jours off exclus :
    // un chapitre ne doit jamais tomber sur un jour marque « impossible
    // de travailler ».
    final joursDispo = <DateTime>[];
    for (var d = 1; d <= joursRestants; d++) {
      final jour = aujourdHui.add(Duration(days: d));
      if (!estJourOff(jour)) joursDispo.add(jour);
    }
    if (joursDispo.isEmpty) joursDispo.add(aujourdHui.add(const Duration(days: 1)));
    for (var i = 0; i < aPlanifier.length; i++) {
      final c = aPlanifier[i];
      // Repartition uniforme sur les jours disponibles.
      c.prochaineRevision =
          joursDispo[(i * joursDispo.length) ~/ aPlanifier.length];
      c.intervalleJours = 1;
    }
    _touch();
    return aPlanifier.length;
  }

  // ---------- Oraux ----------

  void addOral(EpreuveOrale o) {
    oraux.add(o);
    _trierOraux();
    _touch();
  }

  void updateOral(EpreuveOrale o) {
    final i = oraux.indexWhere((x) => x.id == o.id);
    if (i >= 0) oraux[i] = o;
    _trierOraux();
    _touch();
  }

  void deleteOral(String id) {
    oraux.removeWhere((o) => o.id == id);
    _touch();
  }

  void _trierOraux() {
    // Dates connues d'abord (chronologiques), puis les autres par concours.
    oraux.sort((a, b) {
      if (a.date == null && b.date == null) {
        return a.concours.compareTo(b.concours);
      }
      if (a.date == null) return 1;
      if (b.date == null) return -1;
      return a.date!.compareTo(b.date!);
    });
  }

  void setModeOraux(bool v) {
    modeOraux = v;
    _touch();
  }

  /// Prochaine epreuve orale datee a venir (null si aucune date connue).
  EpreuveOrale? prochainOral() {
    final now = DateTime.now();
    final aujourdHui = DateTime(now.year, now.month, now.day);
    EpreuveOrale? best;
    for (final o in oraux) {
      if (o.date == null || o.date!.isBefore(aujourdHui)) continue;
      if (best == null || o.date!.isBefore(best.date!)) best = o;
    }
    return best;
  }

  // ---------- Notifications (preferences LOCALES a l'appareil : pas dans
  // la sauvegarde — chaque appareil decide de ses notifs) ----------

  bool notifsActives = false;
  bool notifVeilleKholle = true;
  bool notifVeilleDm = true;

  Future<void> chargerPrefsNotifs() async {
    final prefs = await SharedPreferences.getInstance();
    notifsActives = prefs.getBool('notifsActives') ?? false;
    notifVeilleKholle = prefs.getBool('notifVeilleKholle') ?? true;
    notifVeilleDm = prefs.getBool('notifVeilleDm') ?? true;
  }

  Future<void> setPrefsNotifs(
      {bool? actives, bool? veilleKholle, bool? veilleDm}) async {
    if (actives != null) notifsActives = actives;
    if (veilleKholle != null) notifVeilleKholle = veilleKholle;
    if (veilleDm != null) notifVeilleDm = veilleDm;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifsActives', notifsActives);
    await prefs.setBool('notifVeilleKholle', notifVeilleKholle);
    await prefs.setBool('notifVeilleDm', notifVeilleDm);
    notifyListeners();
  }

  void setPrio(String matiere, int p) {
    prios[matiere] = p;
    _touch();
  }

  void setProfil({required String filiere, required int groupe}) {
    this.filiere = filiere;
    this.groupe = groupe;
    _touch();
  }

  // ---------- Lectures pratiques ----------

  /// Toutes les matieres connues (colles + ds + chapitres + devoirs +
  /// emploi du temps + evenements), triees. L'EDT compte : en debut d'annee,
  /// avant tout import, c'est souvent la seule source — et sans elle on ne
  /// pouvait pas regler les priorites de matieres que le moteur score.
  List<String> get matieres {
    final s = <String>{};
    for (final c in colles) {
      if (c.matiere.isNotEmpty) s.add(c.matiere);
    }
    for (final d in ds) {
      if (d.matiere.isNotEmpty) s.add(d.matiere);
    }
    for (final c in chapitres) {
      if (c.matiere.isNotEmpty) s.add(c.matiere);
    }
    for (final d in devoirs) {
      if (d.matiere.isNotEmpty) s.add(d.matiere);
    }
    for (final r in routines) {
      if (r.matiere.trim().isNotEmpty) s.add(r.matiere.trim());
    }
    for (final e in evenements) {
      if (e.matiere.trim().isNotEmpty) s.add(e.matiere.trim());
    }
    final l = s.toList()..sort();
    return l;
  }

  List<Colle> collesAvenir() {
    final now = DateTime.now();
    return colles.where((c) => c.end.isAfter(now)).toList();
  }

  Colle? prochaineColle() {
    final l = collesAvenir();
    return l.isEmpty ? null : l.first;
  }

  double? moyenneColles(String matiere) {
    final notes = colles
        .where((c) => c.matiere == matiere && c.note != null)
        .map((c) => c.note!)
        .toList();
    if (notes.isEmpty) return null;
    return notes.reduce((a, b) => a + b) / notes.length;
  }

  /// Moyenne des DS PONDEREE par les coefficients (comme au lycee).
  double? moyenneDs(String matiere) {
    double sommePoints = 0, sommeCoeffs = 0;
    for (final d in ds) {
      if (d.matiere != matiere || d.note == null) continue;
      sommePoints += d.note! * d.coeff;
      sommeCoeffs += d.coeff;
    }
    if (sommeCoeffs == 0) return null;
    return sommePoints / sommeCoeffs;
  }
}
