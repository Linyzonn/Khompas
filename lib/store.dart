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

/// Parse une liste d'enregistrements en TOLERANT les elements abimes : une
/// date illisible dans UNE kholle ne doit pas jeter les 199 autres.
/// Retourne (liste des valides, nombre d'ignores). Publique pour les tests.
(List<T>, int) parseListeTolerante<T>(
    dynamic brut, T Function(Map<String, dynamic>) fromJson) {
  final out = <T>[];
  var ignores = 0;
  for (final e in (brut ?? []) as List) {
    try {
      out.add(fromJson(e as Map<String, dynamic>));
    } catch (_) {
      ignores++;
    }
  }
  return (out, ignores);
}

// repareJsonTronque vit dans models.dart : il sert aussi au plan B des
// extractions IA (ai_extractor), qui ne peut pas importer store.dart
// (cycle via api_client).

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
  // L'ORDRE de la liste est l'ordre de lecture choisi par l'eleve.
  List<Oeuvre> oeuvres = [];
  // Citations de francais et voc d'anglais : les CARTES (revision type Anki,
  // servies pendant le trajet et avant les kholles d'anglais).
  List<Citation> citations = [];
  List<MotVocab> vocab = [];
  // Temps de trajet quotidien (minutes, 0 = pas de trajet) : le tableau de
  // bord y propose le travail « sans table » (citations, voc).
  int trajetMinutes = 0;
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
  // Enregistrements illisibles ignores au chargement (chargement TOLERANT :
  // 199 kholles saines ne disparaissent pas pour une 200e malade).
  int enregistrementsIgnores = 0;
  // Echecs CONSECUTIFS du push automatique (persiste : une synchro qui
  // echoue en silence pendant des semaines est le pire des bugs — au-dela
  // de quelques echecs, le tableau de bord previent).
  int pushEchecs = 0;
  String pushDerniereErreur = '';
  // Objectif de moyenne par matiere (facultatif, toujours formule en positif).
  Map<String, double> objectifs = {};
  // Date des ecrits : non nulle = MODE REVISIONS CONCOURS actif.
  DateTime? dateConcours;
  // ---------- EPL/S (ENAC, pilote de ligne) ----------
  // Concours prepare EN PLUS de la prepa : 3 QCM de 2 h coeff 1 — maths sur
  // le programme de PCSI, physique sur celui de MPSI, anglais (eliminatoire
  // sous 8) — puis selections psychotechniques PSY 1/PSY 2 qui demandent de
  // l'entrainement regulier. Quand le mode est actif, le plan du soir
  // ajoute un bloc quotidien en rotation (engine.suggestionEplS).
  bool eplS = false;
  DateTime? dateEplS;
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

  // Horodatage PAR ENREGISTREMENT (id -> derniere modification locale) et
  // pierres tombales (id supprime -> date) : la fusion de synchro s'en sert
  // pour departager deux versions d'un meme id et pour ne pas RESSUSCITER
  // ce qui a ete efface. Un enregistrement jamais modifie n'a pas de date
  // (epoque 0) : le cote qui l'a modifie gagne alors naturellement.
  Map<String, DateTime> majEnregistrements = {};
  Map<String, DateTime> suppressions = {};

  void _stamp(String id) {
    majEnregistrements[id] = DateTime.now();
  }

  void _tombe(String id) {
    suppressions[id] = DateTime.now();
    majEnregistrements.remove(id);
  }

  /// Menage des maps de fusion : suppressions > 90 j oubliees (les autres
  /// appareils ont eu le temps de les voir), horodatages orphelins purges.
  void _menageFusion() {
    final limite = DateTime.now().subtract(const Duration(days: 90));
    suppressions.removeWhere((_, quand) => quand.isBefore(limite));
    final ids = <String>{
      for (final x in colles) x.id,
      for (final x in ds) x.id,
      for (final x in chapitres) x.id,
      for (final x in routines) x.id,
      for (final x in devoirs) x.id,
      for (final x in seances) x.id,
      for (final x in bilans) x.id,
      for (final x in evenements) x.id,
      for (final x in sansCours) x.id,
      for (final x in erreurs) x.id,
      for (final x in annales) x.id,
      for (final x in oraux) x.id,
      for (final x in resultatsConcours) x.id,
      for (final x in oeuvres) x.id,
      for (final x in citations) x.id,
      for (final x in vocab) x.id,
    };
    majEnregistrements.removeWhere((id, _) => !ids.contains(id));
  }

  Timer? _pushTimer;
  Timer? _saveTimer;

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
      pushEchecs = prefs.getInt('pushEchecs') ?? 0;
      cleCreeLe = DateTime.tryParse(prefs.getString('cleCreeLe') ?? '');
      cleRappelOk = prefs.getBool('cleRappelOk') ?? false;
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
          // Chargement TOLERANT enregistrement par enregistrement : une
          // seule date illisible jetait TOUTE la base (circuit corrompu,
          // app vide) — 199 kholles saines ne doivent pas disparaitre pour
          // une 200e malade. Les malades sont comptees et signalees.
          var ignores = 0;
          List<T> lit<T>(dynamic brut, T Function(Map<String, dynamic>) f) {
            final (liste, rates) = parseListeTolerante(brut, f);
            ignores += rates;
            return liste;
          }

          final newColles = lit(j['colles'], Colle.fromJson);
          final newDs = lit(j['ds'], Ds.fromJson);
          final newChapitres = lit(j['chapitres'], Chapitre.fromJson);
          final newRoutines = lit(j['routines'], Routine.fromJson);
          final newDevoirs = lit(j['devoirs'], Devoir.fromJson);
          final newSeances = lit(j['seances'], Seance.fromJson);
          final newObjectifs = ((j['objectifs'] ?? {}) as Map)
              .map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
          final newDateConcours = j['dateConcours'] == null
              ? null
              : DateTime.tryParse(j['dateConcours'] as String);
          final newEplS = (j['eplS'] ?? false) as bool;
          final newDateEplS = j['dateEplS'] == null
              ? null
              : DateTime.tryParse(j['dateEplS'] as String);
          final newBilans = lit(j['bilans'], Bilan.fromJson);
          final newEvenements = lit(j['evenements'], Evenement.fromJson);
          final newSansCours = lit(j['sansCours'], PlageSansCours.fromJson);
          final newErreurs = lit(j['erreurs'], Erreur.fromJson);
          final newAnnales = lit(j['annales'], Annale.fromJson);
          final newOraux = lit(j['oraux'], EpreuveOrale.fromJson);
          final newResultats =
              lit(j['resultatsConcours'], ResultatConcours.fromJson);
          final newZone = (j['zoneVacances'] ?? '') as String;
          final newOeuvres = lit(j['oeuvres'], Oeuvre.fromJson);
          final newCitations = lit(j['citations'], Citation.fromJson);
          final newVocab = lit(j['vocab'], MotVocab.fromJson);
          final newTrajet = ((j['trajetMinutes'] ?? 0) as num).toInt();
          final newFaits = ((j['faitsDuJour'] ?? []) as List)
              .map((e) => e.toString())
              .toSet();
          final newMajEnr = _litDates(j['majEnregistrements']);
          final newSuppr = _litDates(j['suppressions']);
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
          eplS = newEplS;
          dateEplS = newDateEplS;
          reparerEspacement();
          bilans = newBilans;
          evenements = newEvenements;
          sansCours = newSansCours;
          erreurs = newErreurs;
          annales = newAnnales;
          oraux = newOraux;
          resultatsConcours = newResultats;
          zoneVacances = newZone;
          oeuvres = newOeuvres;
          citations = newCitations;
          vocab = newVocab;
          trajetMinutes = newTrajet;
          faitsDuJour = newFaits;
          majEnregistrements = newMajEnr;
          suppressions = newSuppr;
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
          // Des enregistrements ont ete ignores : copie de secours du brut
          // AVANT le premier save() (qui les perdrait definitivement) +
          // compteur affiche sur le tableau de bord. Le circuit « corrompu »
          // reste reserve au JSON racine illisible.
          enregistrementsIgnores = ignores;
          if (ignores > 0) {
            try {
              if (kIsWeb) {
                await prefs.setString('db_corrompu', raw);
              } else {
                final f = await _dbFile();
                await File('${f.path}.corrompu').writeAsString(raw);
              }
            } catch (_) {
              // la copie a echoue : on garde au moins le compteur
            }
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
    // Repare les revisions ecrasees par l'ancien etaleur (invariant
    // dernierRevu + intervalle). Sauvegarde uniquement si necessaire.
    if (reparerEspacement() > 0 && !chargementEchoue) save();
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
      if (c.matiere == source) {
        c.matiere = cible;
        _stamp(c.id);
      }
    }
    for (final d in ds) {
      if (d.matiere == source) {
        d.matiere = cible;
        _stamp(d.id);
      }
    }
    for (final c in chapitres) {
      if (c.matiere == source) {
        c.matiere = cible;
        _stamp(c.id);
      }
    }
    for (final r in routines) {
      if (r.matiere == source) {
        r.matiere = cible;
        _stamp(r.id);
      }
    }
    for (final d in devoirs) {
      if (d.matiere == source) {
        d.matiere = cible;
        _stamp(d.id);
      }
    }
    for (final s in seances) {
      if (s.matiere == source) {
        s.matiere = cible;
        _stamp(s.id);
      }
    }
    for (final b in bilans) {
      if (b.matiere == source) {
        b.matiere = cible;
        _stamp(b.id);
      }
    }
    for (final e in evenements) {
      if (e.matiere == source) {
        e.matiere = cible;
        _stamp(e.id);
      }
    }
    for (final e in erreurs) {
      if (e.matiere == source) {
        e.matiere = cible;
        _stamp(e.id);
      }
    }
    for (final a in annales) {
      if (a.matiere == source) {
        a.matiere = cible;
        _stamp(a.id);
      }
    }
    for (final r in resultatsConcours) {
      if (r.matiere == source) {
        r.matiere = cible;
        _stamp(r.id);
      }
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
        'eplS': eplS,
        'dateEplS': dateEplS?.toIso8601String(),
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
        'citations': citations.map((c) => c.toJson()).toList(),
        'vocab': vocab.map((v) => v.toJson()).toList(),
        'trajetMinutes': trajetMinutes,
        'faitsDuJour': faitsDuJour.toList(),
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
        'majEnregistrements': majEnregistrements
            .map((k, v) => MapEntry(k, v.toIso8601String())),
        'suppressions':
            suppressions.map((k, v) => MapEntry(k, v.toIso8601String())),
      };

  /// Map {id -> date} depuis le JSON (entrees illisibles ignorees).
  static Map<String, DateTime> _litDates(dynamic brut) {
    final out = <String, DateTime>{};
    ((brut ?? {}) as Map).forEach((k, v) {
      final d = DateTime.tryParse(v.toString());
      if (d != null) out[k.toString()] = d;
    });
    return out;
  }

  Future<void> save() async {
    try {
      _menageFusion();
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
  // Dernier snapshot REELLEMENT envoye au compte : si rien n'a change,
  // on ne repousse pas — chaque push reecrit TOUT le compte sur le KV
  // (~1 unite d'ecriture / Ko sur le quota gratuit de Deno Deploy), la
  // deduplication est le premier poste d'economie.
  String? _dernierPushEnvoye;

  void _programmerPush() {
    if (compteCle.isEmpty || serverUrl.isEmpty) return;
    // Chargement local echoue = on ne sait PAS ce qu'on a en memoire :
    // pousser ecraserait la copie serveur (le seul filet restant) avec du
    // vide. Le push reprend apres restauration/recuperation, qui remettent
    // chargementEchoue a false.
    if (chargementEchoue) return;
    _pushTimer?.cancel();
    // 30 s (et non 3) : une soiree de travail declenche des dizaines de
    // modifications — grouper divise d'autant les ecritures KV, et
    // flushPush() pousse immediatement quand l'app passe en arriere-plan.
    _pushTimer = Timer(const Duration(seconds: 30), _pousserAuto);
  }

  /// Pousse immediatement le push automatique en attente (mise en
  /// arriere-plan de l'app) — les 30 s de debounce ne doivent pas laisser
  /// la derniere soiree hors ligne.
  Future<void> flushPush() async {
    if (_pushTimer?.isActive ?? false) {
      _pushTimer!.cancel();
      await _pousserAuto();
    }
  }

  Future<void> _pousserAuto() async {
    if (chargementEchoue) return; // ceinture ET bretelles (cf. _programmerPush)
    try {
      // JSON COMPACT (l'indente est reserve au fichier de sauvegarde
      // humain) : ~30-40 % plus petit, ca repousse d'autant la limite de
      // taille du serveur ET reduit les ecritures KV.
      final donnees = exportJsonCompact();
      if (donnees == _dernierPushEnvoye) return; // rien de neuf : zero cout
      final v = await ApiKhompas(serverUrl)
          .envoyerCompte(compteCle, donnees, versionConnue: _majConnue);
      _dernierPushEnvoye = donnees;
      await _memoriserVersion(v);
      await _pushReussi();
      if (syncConflit || compteEnAvance) {
        syncConflit = false;
        compteEnAvance = false;
        notifyListeners();
      }
    } catch (e) {
      // Le serveur refuse car un autre appareil a des donnees plus
      // recentes -> bandeau sur le tableau de bord.
      if (e.toString().contains('plus récentes')) {
        syncConflit = true;
        notifyListeners();
      } else {
        // TOUT autre echec est COMPTE : une synchro qui meurt en silence
        // (donnees trop grosses, serveur en panne, hors ligne chronique)
        // est le pire des bugs — au-dela de quelques echecs consecutifs,
        // le tableau de bord previent au lieu de laisser croire que le
        // compte est a jour.
        await _pushEchoue(e);
      }
    }
  }

  Future<void> _pushReussi() async {
    if (pushEchecs == 0) return;
    pushEchecs = 0;
    pushDerniereErreur = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('pushEchecs', 0);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _pushEchoue(Object e) async {
    pushEchecs++;
    pushDerniereErreur = e.toString().replaceFirst('Exception: ', '');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('pushEchecs', pushEchecs);
    } catch (_) {}
    notifyListeners();
  }

  /// [nouvelle] : la cle vient d'etre CREEE (pas connectee) — on memorise
  /// la date pour le rappel « as-tu note ta cle ? » a J+7 (le drame
  /// classique du telephone perdu a Noel, cle jamais notee).
  Future<void> saveCompteCle(String cle, {bool nouvelle = false}) async {
    compteCle = cle.trim().toUpperCase();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('compteCle', compteCle);
    if (nouvelle) {
      cleCreeLe = DateTime.now();
      cleRappelOk = false;
      await prefs.setString('cleCreeLe', cleCreeLe!.toIso8601String());
      await prefs.setBool('cleRappelOk', false);
    }
    notifyListeners();
  }

  // Rappel de cle J+7 : date de creation de la cle sur CET appareil, et
  // « l'utilisateur a confirme l'avoir notee ».
  DateTime? cleCreeLe;
  bool cleRappelOk = false;

  Future<void> marquerCleNotee() async {
    cleRappelOk = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cleRappelOk', true);
    notifyListeners();
  }

  /// Compare LOCAL vs COMPTE avant « Récupérer » : compte les
  /// enregistrements des deux cotes SANS rien importer — le choix binaire
  /// (ecraser ici ou la) devient au moins un choix eclaire.
  /// Retourne (resume local, resume du compte).
  Future<(String, String)> comparerAvecCompte() async {
    final resultat = await ApiKhompas(serverUrl).recupererCompte(compteCle);
    final data = resultat?.$2;
    if (data == null || data.trim().isEmpty) {
      throw Exception('aucune donnée sur ce compte pour le moment.');
    }
    String resume(Map<String, dynamic> j) {
      int n(String cle) => ((j[cle] ?? []) as List).length;
      var notes = 0;
      for (final c in (j['colles'] ?? []) as List) {
        if ((c as Map)['note'] != null) notes++;
      }
      for (final d in (j['ds'] ?? []) as List) {
        if ((d as Map)['note'] != null) notes++;
      }
      return '${n('colles')} khôlles · $notes notes · ${n('chapitres')} chapitres · ${n('vocab')} voc · ${n('citations')} citations';
    }

    final local =
        resume(jsonDecode(exportJsonCompact()) as Map<String, dynamic>);
    String distant;
    try {
      distant = resume(jsonDecode(data) as Map<String, dynamic>);
    } catch (_) {
      distant = 'contenu illisible';
    }
    return (local, distant);
  }

  // ---------- Fusion de synchro (par enregistrement) ----------

  static final DateTime _epoque = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _majDe(Map<String, DateTime> m, String id) => m[id] ?? _epoque;

  /// Fusionne l'etat DISTANT (JSON du compte) dans l'etat local — fini le
  /// choix binaire « ecraser ici ou la » :
  ///  - union par id : ce qui n'existe que d'un cote est garde ;
  ///  - meme id modifie des deux cotes -> la version la plus RECENTE gagne
  ///    (horodatages par enregistrement ; sans horodatage, le local gagne) ;
  ///  - les SUPPRESSIONS sont respectees des deux cotes (pierres tombales :
  ///    rien ne ressuscite) ;
  ///  - reglages scalaires (profil, methode...) : le LOCAL gagne — c'est
  ///    ici qu'on est en train de travailler ; prios/objectifs : union.
  /// Retourne un resume chiffre. Leve une exception si le JSON est illisible.
  String fusionnerDonnees(String brutDistant) {
    dynamic decoded;
    try {
      decoded = jsonDecode(brutDistant);
    } catch (_) {
      throw Exception('données du compte illisibles.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw Exception('données du compte illisibles.');
    }
    final majDistant = _litDates(decoded['majEnregistrements']);
    final supprDistant = _litDates(decoded['suppressions']);
    var ajoutes = 0, remplaces = 0, retires = 0;

    List<T> fusionne<T>(List<T> locaux, dynamic brut,
        T Function(Map<String, dynamic>) fromJson, String Function(T) idDe) {
      final (distants, _) = parseListeTolerante(brut, fromJson);
      final parId = <String, T>{for (final l in locaux) idDe(l): l};
      // Suppressions DISTANTES : retirent le local si elles sont plus
      // recentes que sa derniere modification locale.
      supprDistant.forEach((id, quand) {
        if (parId.containsKey(id) &&
            quand.isAfter(_majDe(majEnregistrements, id))) {
          parId.remove(id);
          retires++;
        }
      });
      for (final d in distants) {
        final id = idDe(d);
        // Supprime LOCALEMENT apres sa derniere modif distante : reste mort.
        final tombeLocal = suppressions[id];
        if (tombeLocal != null && tombeLocal.isAfter(_majDe(majDistant, id))) {
          continue;
        }
        final local = parId[id];
        if (local == null) {
          parId[id] = d;
          ajoutes++;
        } else if (_majDe(majDistant, id)
            .isAfter(_majDe(majEnregistrements, id))) {
          parId[id] = d;
          remplaces++;
        }
      }
      return parId.values.toList();
    }

    colles = fusionne(colles, decoded['colles'], Colle.fromJson, (c) => c.id)
      ..sort((a, b) => a.start.compareTo(b.start));
    ds = fusionne(ds, decoded['ds'], Ds.fromJson, (d) => d.id)
      ..sort((a, b) => a.date.compareTo(b.date));
    chapitres =
        fusionne(chapitres, decoded['chapitres'], Chapitre.fromJson, (c) => c.id);
    routines =
        fusionne(routines, decoded['routines'], Routine.fromJson, (r) => r.id);
    _trierRoutines();
    devoirs = fusionne(devoirs, decoded['devoirs'], Devoir.fromJson, (d) => d.id)
      ..sort((a, b) => a.dateRendu.compareTo(b.dateRendu));
    seances =
        fusionne(seances, decoded['seances'], Seance.fromJson, (s) => s.id);
    bilans = fusionne(bilans, decoded['bilans'], Bilan.fromJson, (b) => b.id);
    evenements = fusionne(
        evenements, decoded['evenements'], Evenement.fromJson, (e) => e.id)
      ..sort((a, b) => a.date != b.date
          ? a.date.compareTo(b.date)
          : a.debutMin.compareTo(b.debutMin));
    sansCours = fusionne(
        sansCours, decoded['sansCours'], PlageSansCours.fromJson, (p) => p.id)
      ..sort((a, b) => a.debut.compareTo(b.debut));
    erreurs = fusionne(erreurs, decoded['erreurs'], Erreur.fromJson, (e) => e.id);
    annales = fusionne(annales, decoded['annales'], Annale.fromJson, (a) => a.id)
      ..sort((x, y) => x.matiere != y.matiere
          ? x.matiere.compareTo(y.matiere)
          : y.annee.compareTo(x.annee));
    oraux = fusionne(oraux, decoded['oraux'], EpreuveOrale.fromJson, (o) => o.id);
    _trierOraux();
    resultatsConcours = fusionne(resultatsConcours, decoded['resultatsConcours'],
        ResultatConcours.fromJson, (r) => r.id)
      ..sort((a, b) => a.concours != b.concours
          ? a.concours.compareTo(b.concours)
          : a.epreuve.compareTo(b.epreuve));
    oeuvres = fusionne(oeuvres, decoded['oeuvres'], Oeuvre.fromJson, (o) => o.id);
    citations =
        fusionne(citations, decoded['citations'], Citation.fromJson, (c) => c.id);
    vocab = fusionne(vocab, decoded['vocab'], MotVocab.fromJson, (v) => v.id);

    // prios / objectifs : union — le LOCAL gagne sur un conflit de cle.
    ((decoded['prios'] ?? {}) as Map).forEach((k, v) {
      if (v is num) prios.putIfAbsent(k.toString(), () => v.toInt());
    });
    ((decoded['objectifs'] ?? {}) as Map).forEach((k, v) {
      if (v is num) objectifs.putIfAbsent(k.toString(), () => v.toDouble());
    });
    // joursOff : union de dates.
    for (final e in (decoded['joursOff'] ?? []) as List) {
      final d = DateTime.tryParse(e.toString());
      if (d != null && !estJourOff(d)) {
        joursOff.add(DateTime(d.year, d.month, d.day));
      }
    }
    joursOff.sort();
    // Horodatages et tombales : union, la date la plus recente est gardee.
    majDistant.forEach((k, v) {
      if (v.isAfter(_majDe(majEnregistrements, k))) majEnregistrements[k] = v;
    });
    supprDistant.forEach((k, v) {
      final l = suppressions[k];
      if (l == null || v.isAfter(l)) suppressions[k] = v;
    });
    _migrerMatieres();
    _touch();
    return '$ajoutes ajouté(s) · $remplaces mis à jour · $retires retiré(s)';
  }

  /// Recupere le compte, FUSIONNE avec l'etat local, et repousse le
  /// resultat — la reponse propre au bandeau « ton autre appareil a aussi
  /// travaille » (rien ne s'ecrase).
  Future<String> fusionnerAvecCompte() async {
    final resultat = await ApiKhompas(serverUrl).recupererCompte(compteCle);
    final data = resultat?.$2;
    if (data == null || data.trim().isEmpty) {
      throw Exception('aucune donnée sur ce compte pour le moment.');
    }
    final resume = fusionnerDonnees(data);
    // L'etat fusionne peut contenir des revisions ecrasees par une vieille
    // version distante : reparer AVANT de re-pousser.
    reparerEspacement();
    await _memoriserVersion(resultat!.$1);
    syncConflit = false;
    compteEnAvance = false;
    await pousserCompte();
    return resume;
  }

  /// Dissocie l'appareil du compte (les donnees restent locales ET sur le
  /// serveur — seule la cle locale est oubliee).
  Future<void> deconnecterCompte() async {
    compteCle = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('compteCle');
    notifyListeners();
  }

  /// Remise a zero COMPLETE — la porte de sortie « je repars propre »,
  /// indispensable en mode invite (aucun compte pour restaurer) et en cas
  /// de donnees corrompues. Ordre CRITIQUE :
  ///  1. annuler le push debounce et oublier la cle de compte AVANT de
  ///     vider quoi que ce soit — sinon un save() pousserait un etat VIDE
  ///     sur le compte serveur (qui est la derniere copie recuperable) ;
  ///  2. remettre tout l'etat memoire aux valeurs d'usine ;
  ///  3. purger le stockage (khompas.json + .tmp en natif, cle 'db' sur
  ///     web, prefs). Les copies .corrompu / 'db_corrompu' sont CONSERVEES :
  ///     si la remise a zero suit un chargement echoue, c'est la seule
  ///     trace restante des donnees.
  ///  4. onboarded=false + notifyListeners() : le Gate raffiche l'ecran de
  ///     bienvenue tout seul. L'APPELANT doit encore popUntil(isFirst) pour
  ///     vider la pile de navigation (le Gate ne remplace que la home).
  /// Les donnees deja envoyees au compte RESTENT sur le serveur (aucun
  /// endpoint de suppression) : recuperables plus tard avec la cle.
  Future<void> reinitialiser() async {
    // 1. Compte : plus AUCUN push ne doit partir — et aucun save() en
    // attente ne doit recreer le fichier apres sa suppression.
    _pushTimer?.cancel();
    _pushTimer = null;
    _saveTimer?.cancel();
    _saveTimer = null;
    pushEchecs = 0;
    pushDerniereErreur = '';
    enregistrementsIgnores = 0;
    _dernierPushEnvoye = null;
    cleCreeLe = null;
    cleRappelOk = false;
    majEnregistrements = {};
    suppressions = {};
    compteCle = '';
    gestionClasse = '';
    apiKey = '';
    _majConnue = 0;
    syncConflit = false;
    compteEnAvance = false;
    chargementEchoue = false;
    // 2. Valeurs d'usine (miroir des declarations de champs).
    colles = [];
    ds = [];
    chapitres = [];
    routines = [];
    devoirs = [];
    seances = [];
    bilans = [];
    evenements = [];
    sansCours = [];
    erreurs = [];
    annales = [];
    oraux = [];
    resultatsConcours = [];
    oeuvres = [];
    citations = [];
    vocab = [];
    trajetMinutes = 0;
    faitsDuJour = {};
    joursOff = [];
    zoneVacances = '';
    modeOraux = false;
    refSemaineA = null;
    methodeTravail = 'checklist';
    heureLimiteMin = null;
    objectifs = {};
    dateConcours = null;
    eplS = false;
    dateEplS = null;
    prios = {};
    filiere = 'PCSI';
    groupe = 1;
    codeClasse = '';
    cinqDemi = false;
    notifsActives = false;
    notifVeilleKholle = true;
    notifVeilleDm = true;
    // PAS '' : serverUrl vide masquerait les boutons compte de l'onboarding.
    serverUrl = kServeurDefaut;
    onboarded = false; // loaded reste true : le Gate bascule directement
    // 3. Stockage (meme tolerance aux pannes que save()).
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in [
        'compteCle',
        'gestionClasse',
        'apiKey',
        'majConnue',
        'serverUrl',
        'notifsActives',
        'notifVeilleKholle',
        'notifVeilleDm',
        'pushEchecs',
        'cleCreeLe',
        'cleRappelOk',
      ]) {
        await prefs.remove(k);
      }
      await prefs.setBool('onboarded', false);
      if (kIsWeb) await prefs.remove('db'); // 'db_corrompu' conservee
    } catch (_) {
      // stockage inaccessible : l'etat memoire est deja vide, tant pis
    }
    if (!kIsWeb) {
      try {
        final f = await _dbFile();
        if (await f.exists()) await f.delete();
        final tmp = File('${f.path}.tmp');
        if (await tmp.exists()) await tmp.delete();
        // khompas.json.corrompu CONSERVE volontairement.
      } catch (_) {
        // idem : jamais bloquant
      }
    }
    // 4. Gate -> OnboardingScreen ; les notifs seront annulees par le
    // listener de main.dart (replanifier avec des donnees vides).
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
    final donnees = exportJsonCompact();
    final v = await ApiKhompas(serverUrl)
        .envoyerCompte(compteCle, donnees, versionConnue: _majConnue);
    _dernierPushEnvoye = donnees;
    await _memoriserVersion(v);
    await _pushReussi();
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
    await _pushReussi(); // re-synchronise : le compteur d'echecs repart a zero
    syncConflit = false;
    compteEnAvance = false;
    return importJson(data);
  }

  /// Suppression du COMPTE sur le serveur (RGPD) : purge les donnees et le
  /// profil cote serveur, puis oublie la cle locale (les donnees de CET
  /// appareil restent intactes).
  Future<void> supprimerCompteServeur() async {
    await ApiKhompas(serverUrl).supprimerCompte(compteCle);
    await deconnecterCompte();
    _majConnue = 0;
    await _pushReussi();
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

  /// Version COMPACTE (pour la synchro de compte) : memes donnees, ~30-40 %
  /// plus petites — l'indentation est reservee au fichier humain.
  String exportJsonCompact() => jsonEncode(_snapshot());

  // ---------- Copie de secours (.corrompu / db_corrompu) ----------

  /// Contenu brut de la copie de secours, ou null s'il n'y en a pas.
  Future<String?> lireCopieSecours() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString('db_corrompu');
      }
      final f = await _dbFile();
      final c = File('${f.path}.corrompu');
      if (await c.exists()) return await c.readAsString();
    } catch (_) {
      // stockage inaccessible
    }
    return null;
  }

  /// Tente de RESTAURER la copie de secours : telle quelle d'abord, puis en
  /// reparant une eventuelle troncature de fin de fichier. Retourne le
  /// resume d'importJson ; leve une exception explicite sinon.
  Future<String> restaurerCopieSecours() async {
    final raw = await lireCopieSecours();
    if (raw == null || raw.trim().isEmpty) {
      throw Exception('aucune copie de secours sur cet appareil.');
    }
    String resume;
    try {
      resume = importJson(raw);
    } catch (_) {
      final repare = repareJsonTronque(raw);
      if (repare == null) {
        throw Exception(
            'copie illisible même réparée — utilise « Exporter la copie brute » pour la récupérer à la main.');
      }
      resume = '${importJson(repare)} — fin de fichier tronquée réparée';
    }
    chargementEchoue = false;
    enregistrementsIgnores = 0;
    notifyListeners();
    return resume;
  }

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
      final newEplS = (decoded['eplS'] ?? false) as bool;
      final newDateEplS = decoded['dateEplS'] == null
          ? null
          : DateTime.tryParse(decoded['dateEplS'] as String);
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
      final newCitations = ((decoded['citations'] ?? []) as List)
          .map((e) => Citation.fromJson(e as Map<String, dynamic>))
          .toList();
      final newVocab = ((decoded['vocab'] ?? []) as List)
          .map((e) => MotVocab.fromJson(e as Map<String, dynamic>))
          .toList();
      final newTrajet = ((decoded['trajetMinutes'] ?? trajetMinutes) as num).toInt();
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
      eplS = newEplS;
      dateEplS = newDateEplS;
      bilans = newBilans;
      evenements = newEvenements;
      sansCours = newSansCours;
      erreurs = newErreurs;
      annales = newAnnales;
      oraux = newOraux;
      resultatsConcours = newResultats;
      zoneVacances = newZone;
      oeuvres = newOeuvres;
      citations = newCitations;
      vocab = newVocab;
      trajetMinutes = newTrajet;
      faitsDuJour = ((decoded['faitsDuJour'] ?? []) as List)
          .map((e) => e.toString())
          .toSet();
      majEnregistrements = _litDates(decoded['majEnregistrements']);
      suppressions = _litDates(decoded['suppressions']);
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
    for (final c in colles.where((c) => c.end.isBefore(now))) {
      _tombe(c.id);
    }
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
        _stamp(c.id);
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
            _stamp(c.id);
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
    _stamp(c.id);
    _touch();
  }

  void _touch() {
    // Ecriture DEBOUNCEE (400 ms) : chaque tap re-encodait toute la base en
    // JSON sur le thread UI — invisible en debut d'annee, micro-gels en fin
    // d'annee (surtout en session de cartes, un verdict toutes les 3 s).
    // La fenetre de perte est negligeable, et flushSave() force l'ecriture
    // quand l'app passe en arriere-plan.
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), save);
    notifyListeners();
  }

  /// Force l'ecriture en attente (appele quand l'app passe en arriere-plan :
  /// les 400 ms de debounce ne doivent pas coûter les derniers gestes).
  Future<void> flushSave() async {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      await save();
    }
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
    _stamp(c.id);
    _touch();
  }

  void deleteColle(String id) {
    _tombe(id);
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
    _stamp(d.id);
    _touch();
  }

  void deleteDs(String id) {
    _tombe(id);
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
    _stamp(c.id);
    _touch();
  }

  void deleteChapitre(String id) {
    _tombe(id);
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
    _stamp(d.id);
    _touch();
  }

  void deleteDevoir(String id) {
    _tombe(id);
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

  /// Minutes travaillees par semaine (lundi, total) sur les [semaines]
  /// dernieres — l'histogramme de l'ecran Progression. C'est pour lui que
  /// les seances sont conservees ~13 mois.
  List<(DateTime, int)> minutesParSemaineHisto(
      {DateTime? maintenant, int semaines = 12}) {
    final now = maintenant ?? DateTime.now();
    final lundiCourant = mondayOf(now);
    final out = <(DateTime, int)>[];
    for (var i = semaines - 1; i >= 0; i--) {
      final lundi = lundiCourant.subtract(Duration(days: 7 * i));
      final fin = lundi.add(const Duration(days: 7));
      var total = 0;
      for (final s in seances) {
        if (!s.date.isBefore(lundi) && s.date.isBefore(fin)) {
          total += s.minutes;
        }
      }
      out.add((lundi, total));
    }
    return out;
  }

  /// Minutes par matiere sur les [jours] derniers jours (tri decroissant).
  List<(String, int)> minutesParMatiere({DateTime? maintenant, int jours = 28}) {
    final now = maintenant ?? DateTime.now();
    final debut = now.subtract(Duration(days: jours));
    final map = <String, int>{};
    for (final s in seances) {
      if (s.date.isBefore(debut) || s.date.isAfter(now)) continue;
      if (s.matiere.trim().isEmpty) continue;
      map[s.matiere] = (map[s.matiere] ?? 0) + s.minutes;
    }
    final l = map.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return l;
  }

  /// Tendance de moyenne d'une matiere : (moyenne des 30 derniers jours,
  /// moyenne des 30 jours PRECEDENTS) — kholles et DS confondus, non
  /// ponderes (on regarde une direction, pas un bulletin).
  (double?, double?) tendanceNotes(String matiere, {DateTime? maintenant}) {
    final now = maintenant ?? DateTime.now();
    final coupure = now.subtract(const Duration(days: 30));
    final debut = now.subtract(const Duration(days: 60));
    final recentes = <double>[];
    final anciennes = <double>[];
    void classe(String mat, DateTime d, double? note) {
      if (mat != matiere || note == null || d.isAfter(now)) return;
      if (d.isAfter(coupure)) {
        recentes.add(note);
      } else if (d.isAfter(debut)) {
        anciennes.add(note);
      }
    }

    for (final c in colles) {
      classe(c.matiere, c.start, c.note);
    }
    for (final d in ds) {
      classe(d.matiere, d.date, d.note);
    }
    double? moy(List<double> l) =>
        l.isEmpty ? null : l.reduce((a, b) => a + b) / l.length;
    return (moy(recentes), moy(anciennes));
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

  /// EPL/S (ENAC) : active/coupe le bloc d'entrainement quotidien du plan
  /// du soir ; [date] = date des ecrits quand elle est connue.
  void setEplS(bool actif, {DateTime? date}) {
    eplS = actif;
    dateEplS = date;
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
    _stamp(r.id);
    _touch();
  }

  void deleteRoutine(String id) {
    _tombe(id);
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

  /// Grandes vacances ? Signal principal : juillet/aout (un tout nouvel
  /// utilisateur n'a encore AUCUNE plage) ; sinon une plage 'ete' en cours
  /// (etes decales, rentrees tardives). [maintenant] injectable pour tests.
  bool estEte({DateTime? maintenant}) {
    final now = maintenant ?? DateTime.now();
    if (now.month == 7 || now.month == 8) return true;
    final p = plageSansCours(now);
    return p != null && p.type == 'ete';
  }

  /// Semaine A ou B ? true = A. Sans reference definie, tout est "A".
  bool semaineEstA(DateTime d) {
    if (refSemaineA == null) return true;
    // Difference en UTC : entre heure d'hiver et heure d'ete, 7n jours
    // locaux font 7n x 24h - 1h, que .inDays tronque a 7n-1 — la parite
    // A/B s'inversait donc pendant SEPT MOIS (fin mars -> fin octobre),
    // pile la periode des revisions. En UTC, les minuits sont exacts.
    final a = mondayOf(d);
    final b = mondayOf(refSemaineA!);
    final diff = DateTime.utc(a.year, a.month, a.day)
        .difference(DateTime.utc(b.year, b.month, b.day))
        .inDays;
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
    _stamp(o.id);
    _touch();
  }

  void deleteOeuvre(String id) {
    _tombe(id);
    oeuvres.removeWhere((o) => o.id == id);
    _touch();
  }

  List<Oeuvre> oeuvresNonFinies() =>
      oeuvres.where((o) => !o.finie).toList();

  /// Reordonne les oeuvres (drag & drop) : l'ordre de la liste EST l'ordre
  /// de lecture choisi — le plan sert toujours la premiere non finie.
  /// [newIndex] est deja ajuste (semantique onReorderItem).
  void reorderOeuvres(int oldIndex, int newIndex) {
    final o = oeuvres.removeAt(oldIndex);
    oeuvres.insert(newIndex, o);
    _touch();
  }

  // ---------- Cartes (citations de francais, voc d'anglais) ----------

  static DateTime _minuitDe(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Espacement commun aux cartes : memes multiplicateurs que les chapitres
  /// (evaluerRevision : x1.7 / x2.5 / x1.5 si echecs repetes), sans la
  /// notion de maitrise ; « difficile » ramene a DEMAIN (une carte ratee se
  /// rejoue vite, contrairement a un chapitre entier). Retourne
  /// (intervalle, echecs, prochaineRevision).
  static (int, int, DateTime) _espacementSuivant(
      int intervalle, int echecs, DateTime? due, String verdict, DateTime now) {
    switch (verdict) {
      case 'difficile':
        intervalle = 1;
        echecs++;
        break;
      case 'facile':
        intervalle = (intervalle * 2.5).round().clamp(1, 45);
        echecs = 0;
        break;
      default: // cava
        intervalle = (intervalle * (echecs >= 2 ? 1.5 : 1.7)).round().clamp(1, 45);
    }
    // Ancre sur la date DUE si le retard est raisonnable (< 7 j), comme les
    // chapitres : reviser en retard ne decale pas toute la suite.
    var base = now;
    if (due != null) {
      final retard = _minuitDe(now).difference(_minuitDe(due)).inDays;
      if (retard > 0 && retard < 7) base = due;
    }
    var prochaine = _minuitDe(base).add(Duration(days: intervalle));
    final demain = _minuitDe(now).add(const Duration(days: 1));
    if (prochaine.isBefore(demain)) prochaine = demain;
    return (intervalle, echecs, prochaine);
  }

  void addCitation(Citation c) {
    // Nouvelle carte : due AUJOURD'HUI (elle entre tout de suite dans la
    // prochaine session de revision).
    c.prochaineRevision ??= _minuitDe(DateTime.now());
    citations.insert(0, c);
    _touch();
  }

  /// Ajout en lot (import IA) en evitant les doublons (meme texte).
  int addCitationsList(List<Citation> nouvelles) {
    var added = 0;
    for (final c in nouvelles) {
      final doublon = citations
          .any((x) => x.texte.trim().toLowerCase() == c.texte.trim().toLowerCase());
      if (!doublon) {
        c.prochaineRevision ??= _minuitDe(DateTime.now());
        citations.add(c);
        added++;
      }
    }
    _touch();
    return added;
  }

  void updateCitation(Citation c) {
    final i = citations.indexWhere((x) => x.id == c.id);
    if (i >= 0) citations[i] = c;
    _stamp(c.id);
    _touch();
  }

  void deleteCitation(String id) {
    _tombe(id);
    citations.removeWhere((c) => c.id == id);
    _touch();
  }

  void addMotVocab(MotVocab v) {
    v.prochaineRevision ??= _minuitDe(DateTime.now());
    vocab.insert(0, v);
    _touch();
  }

  /// Ajout en lot (import IA) en evitant les doublons (meme mot anglais).
  int addVocabList(List<MotVocab> nouveaux) {
    var added = 0;
    for (final v in nouveaux) {
      final doublon = vocab.any(
          (x) => x.anglais.trim().toLowerCase() == v.anglais.trim().toLowerCase());
      if (!doublon) {
        v.prochaineRevision ??= _minuitDe(DateTime.now());
        vocab.add(v);
        added++;
      }
    }
    _touch();
    return added;
  }

  void updateMotVocab(MotVocab v) {
    final i = vocab.indexWhere((x) => x.id == v.id);
    if (i >= 0) vocab[i] = v;
    _stamp(v.id);
    _touch();
  }

  void deleteMotVocab(String id) {
    _tombe(id);
    vocab.removeWhere((v) => v.id == id);
    _touch();
  }

  /// Citations dues aujourd'hui (les plus en retard d'abord).
  List<Citation> citationsDues({DateTime? maintenant}) {
    final jour = _minuitDe(maintenant ?? DateTime.now());
    return citations
        .where((c) =>
            c.prochaineRevision == null || !c.prochaineRevision!.isAfter(jour))
        .toList()
      ..sort((a, b) => (a.prochaineRevision ?? jour)
          .compareTo(b.prochaineRevision ?? jour));
  }

  /// Mots de voc dus aujourd'hui (les plus en retard d'abord).
  List<MotVocab> vocabDus({DateTime? maintenant}) {
    final jour = _minuitDe(maintenant ?? DateTime.now());
    return vocab
        .where((v) =>
            v.prochaineRevision == null || !v.prochaineRevision!.isAfter(jour))
        .toList()
      ..sort((a, b) => (a.prochaineRevision ?? jour)
          .compareTo(b.prochaineRevision ?? jour));
  }

  void evaluerCitation(String id, String verdict, {DateTime? maintenant}) {
    final i = citations.indexWhere((c) => c.id == id);
    if (i < 0) return;
    final c = citations[i];
    final now = maintenant ?? DateTime.now();
    final (intervalle, echecs, prochaine) = _espacementSuivant(
        c.intervalleJours, c.echecs, c.prochaineRevision, verdict, now);
    c.intervalleJours = intervalle;
    c.echecs = echecs;
    c.prochaineRevision = prochaine;
    c.dernierRevu = now;
    _stamp(c.id);
    _touch();
  }

  void evaluerMotVocab(String id, String verdict, {DateTime? maintenant}) {
    final i = vocab.indexWhere((v) => v.id == id);
    if (i < 0) return;
    final v = vocab[i];
    final now = maintenant ?? DateTime.now();
    final (intervalle, echecs, prochaine) = _espacementSuivant(
        v.intervalleJours, v.echecs, v.prochaineRevision, verdict, now);
    v.intervalleJours = intervalle;
    v.echecs = echecs;
    v.prochaineRevision = prochaine;
    v.dernierRevu = now;
    _stamp(v.id);
    _touch();
  }

  // Suggestions cochees AUJOURD'HUI qui ne portent ni chapitre ni oeuvre
  // (« Français — cartes », « prépare ta khôlle ») : sans cette trace,
  // elles revenaient dans le plan aussitot cochees.
  // Cle = 'AAAA-MM-JJ|matiere' : la RAISON affichee change en cours de
  // journee (« demain » -> « AUJOURD'HUI »), pas la matiere.
  Set<String> faitsDuJour = {};

  static String _cleFait(DateTime jour, String matiere) =>
      '${_minuitDe(jour).toIso8601String().substring(0, 10)}|$matiere';

  /// Cette matiere a-t-elle deja eu son bloc coche aujourd'hui ?
  bool estFait(String matiere, {DateTime? maintenant}) =>
      faitsDuJour.contains(_cleFait(maintenant ?? DateTime.now(), matiere));

  void marquerFait(String matiere, {DateTime? maintenant}) {
    final now = maintenant ?? DateTime.now();
    faitsDuJour.add(_cleFait(now, matiere));
    // Menage : on ne garde que les 3 derniers jours.
    final limite = _minuitDe(now).subtract(const Duration(days: 3));
    faitsDuJour.removeWhere((cle) {
      final d = DateTime.tryParse(cle.split('|').first);
      return d == null || d.isBefore(limite);
    });
    _touch();
  }

  void setTrajetMinutes(int minutes) {
    trajetMinutes = minutes.clamp(0, 180);
    _touch();
  }

  /// Noms des listes de voc existantes, triees ('' exclue).
  List<String> get listesVocNoms {
    final s = <String>{};
    for (final v in vocab) {
      if (v.liste.trim().isNotEmpty) s.add(v.liste.trim());
    }
    final l = s.toList()..sort();
    return l;
  }

  /// Mots appartenant a l'une des [listes] (pour la revision de veille de
  /// kholle : « ces listes doivent etre sues »).
  List<MotVocab> vocabDeListes(List<String> listes) =>
      vocab.where((v) => listes.contains(v.liste)).toList();

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
    _tombe(id);
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
    _stamp(e.id);
    _touch();
  }

  void deleteEvenement(String id) {
    _tombe(id);
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
    for (final e in bilans.where((e) =>
        e.routineId == b.routineId &&
        e.jour.year == b.jour.year &&
        e.jour.month == b.jour.month &&
        e.jour.day == b.jour.day)) {
      _tombe(e.id);
    }
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
        _stamp(chapitres[i].id);
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
    // La memoire a TENU pendant tout le retard : reussir un chapitre 30 j
    // apres sa date due prouve un intervalle de 30 j, pas de 2. Sans ce
    // credit, un rappel longtemps en attente repartait au plancher et
    // revenait 2 j plus tard — la file des retards se re-remplissait
    // aussitot videe (l'eleve irregulier restait fige a 93 dus, intervalle
    // moyen 2 j apres 4 mois).
    if (verdict != 'difficile' && c.prochaineRevision != null) {
      final nowV = maintenant ?? DateTime.now();
      final retardTenu = DateTime(nowV.year, nowV.month, nowV.day)
          .difference(DateTime(c.prochaineRevision!.year,
              c.prochaineRevision!.month, c.prochaineRevision!.day))
          .inDays;
      if (retardTenu >= 7 && retardTenu > c.intervalleJours) {
        c.intervalleJours = retardTenu;
      }
    }
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
    _stamp(c.id);
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
      _stamp(c.id);
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
    _stamp(e.id);
    _touch();
  }

  void deleteErreur(String id) {
    _tombe(id);
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
    _stamp(a.id);
    _touch();
  }

  void deleteAnnale(String id) {
    _tombe(id);
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
    _stamp(r.id);
    _touch();
  }

  void deleteResultatConcours(String id) {
    _tombe(id);
    resultatsConcours.removeWhere((r) => r.id == id);
    _touch();
  }

  /// « Où tu perds des points » : deficit par matiere, calcule sur les
  /// resultats de concours saisis, NORMALISE PAR CONCOURS — chaque coeff
  /// est rapporte au total de coeffs saisi pour SON concours (echelle
  /// « points sur 100 »). Sans cette normalisation, Centrale (total ~100 de
  /// coeffs) ecrasait Mines (~30) : un point sous la barre y pesait 3x plus
  /// alors que l'ecart reel etait peut-etre plus grand a Mines.
  ///  - avec barre :   max(0, barre - note) x coeff/totalConcours x 100 ;
  ///  - sans barre :   idem avec la mediane de TES notes — la comparaison
  ///    se fait alors a ton propre niveau, pas a une barre inventee.
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
    // Total de coeffs saisi, par concours (epreuves notees uniquement).
    final totalCoeff = <String, double>{};
    for (final r in resultatsConcours) {
      if (r.note == null) continue;
      totalCoeff[r.concours] = (totalCoeff[r.concours] ?? 0) + r.coeff;
    }
    final out = <String, double>{};
    for (final r in resultatsConcours) {
      if (r.note == null || r.matiere.trim().isEmpty) continue;
      final total = totalCoeff[r.concours] ?? 0;
      if (total <= 0) continue;
      final ref = r.barre ?? mediane;
      final deficit = (ref - r.note!) * (r.coeff / total) * 100;
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
  /// Chapitres qu'une reactivation d'ete PEUT planifier : commences
  /// (etape > 0), NON litteraires (le francais et les langues n'ont rien a
  /// reviser en chapitres — leur ete, ce sont les oeuvres, citations et
  /// voc), et pas encore programmes. Bandeau « Planifier » et etaleur
  /// regardent tous deux CETTE liste : s'ils divergent, le bandeau peut
  /// rester affiche apres une planification reussie.
  List<Chapitre> chapitresSansReactivation() => chapitres
      .where((c) =>
          c.etape > 0 &&
          c.prochaineRevision == null &&
          !matiereLitteraire(c.matiere))
      .toList();

  /// INVARIANT de l'espacement : une revision n'est jamais due avant
  /// dernierRevu + intervalle. L'ancien etaleur le violait (il replanifiait
  /// AUSSI les chapitres deja en cours : un chapitre revu la veille avec un
  /// intervalle de 20 j se retrouvait du le lendemain) — cette reparation
  /// remet d'aplomb les donnees touchees, au chargement et apres un pull.
  /// Retourne le nombre de chapitres repares.
  int reparerEspacement() {
    var n = 0;
    for (final c in chapitres) {
      if (c.dernierRevu == null || c.prochaineRevision == null) continue;
      final plancher = DateTime(
              c.dernierRevu!.year, c.dernierRevu!.month, c.dernierRevu!.day)
          .add(Duration(days: c.intervalleJours));
      if (c.prochaineRevision!.isBefore(plancher)) {
        c.prochaineRevision = plancher;
        _stamp(c.id);
        n++;
      }
    }
    return n;
  }

  int etalerReactivation({DateTime? maintenant}) {
    final now = maintenant ?? DateTime.now();
    final plage = plageSansCours(now);
    final aujourdHui = DateTime(now.year, now.month, now.day);
    // Sans plage saisie : en juillet/aout, fin implicite au 31 aout (meme
    // regle que le mode ete du moteur) — l'etaleur ne doit pas rendre 0 en
    // silence parce qu'un clic sur « Creer la plage » a ete annule.
    final DateTime finPlage;
    if (plage != null && plage.type == 'ete') {
      finPlage = DateTime(plage.fin.year, plage.fin.month, plage.fin.day);
    } else if (now.month == 7 || now.month == 8) {
      finPlage = DateTime(now.year, 8, 31);
    } else {
      return 0;
    }
    var joursRestants = finPlage.difference(aujourdHui).inDays;
    if (joursRestants < 1) joursRestants = 1;
    // Les matieres litteraires (francais, langues) n'ont RIEN a reviser en
    // chapitres : leur ete, ce sont les oeuvres, les citations et le voc.
    // NON DESTRUCTIF : seuls les chapitres HORS de la repetition espacee
    // sont planifies (la meme liste que le bandeau « Planifier »). Un
    // chapitre deja programme garde sa date et son intervalle — replanifier
    // ecrasait des semaines de progression (intervalles regagnes a 7,
    // revisions retassees sur les jours de vacances restants : l'utilisateur
    // a vu ses chapitres deja revus revenir en tete du jour au lendemain).
    final aPlanifier = chapitresSansReactivation()
        .toList()
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
      _stamp(c.id);
      // Intervalle initial de 7 j (et non 1) : ces chapitres sont « deja
      // vus » — a intervalle 1, les 95 chapitres d'un programme importe
      // revenaient TOUS 2-3 jours apres leur premiere revision, et la file
      // explosait en trois semaines (mesure en simulation : 0 -> 83 dus en
      // aout, meme en faisant tout le plan chaque soir). Avec 7, le premier
      // verdict repart vers 12-18 j et la file reste plate.
      c.intervalleJours = 7;
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
    _stamp(o.id);
    _touch();
  }

  void deleteOral(String id) {
    _tombe(id);
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

  /// [maintenant] : horloge injectable — le moteur la fournit, l'UI peut
  /// l'omettre. Sans elle, le simulateur (tests longue duree) voyait des
  /// kholles « EN RETARD » fantomes pendant des mois.
  List<Colle> collesAvenir({DateTime? maintenant}) {
    final now = maintenant ?? DateTime.now();
    return colles.where((c) => c.end.isAfter(now)).toList();
  }

  Colle? prochaineColle({DateTime? maintenant}) {
    final l = collesAvenir(maintenant: maintenant);
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
