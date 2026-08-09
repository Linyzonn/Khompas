import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'dialogs.dart';

/// Editeur d'emploi du temps en TABLEAU : 6 colonnes (lundi -> samedi),
/// on tape une case pour poser un bloc depuis une palette pre-remplie
/// (matieres selon la filiere + vie quotidienne), avec option semaine A/B.
/// Les blocs "semaine A" occupent la moitie gauche de la colonne, les "B"
/// la moitie droite : l'alternance se voit d'un coup d'oeil.
class EdtScreen extends StatefulWidget {
  const EdtScreen({super.key});

  @override
  State<EdtScreen> createState() => _EdtScreenState();
}

class _EdtScreenState extends State<EdtScreen> {
  static const _jours = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'];
  static const _hDebut = 7; // 7h
  static const _hFin = 24; // minuit (les journees de prepa finissent tard)
  static const _cellH = 34.0;

  static const _vie = ['Repas', 'Douche', 'Sport', 'Trajet', 'Pause'];

  List<String> get _matieresPalette {
    final m = AppModel.instance;
    final base = <String>{};
    switch (m.filiere) {
      case 'MPSI':
      case 'MP':
      case 'MP2I':
      case 'MPI':
        base.addAll(
            ['Maths', 'Physique', 'Info', 'Français', 'Anglais', 'TIPE']);
        break;
      case 'PCSI':
      case 'PC':
        base.addAll([
          'Maths', 'Physique', 'Chimie', 'Info', 'Français', 'Anglais', 'TIPE'
        ]);
        break;
      case 'PSI':
      case 'PTSI':
      case 'PT':
        // En PSI, la matiere s'appelle bien Physique-Chimie.
        base.addAll([
          'Maths', 'Physique-Chimie', 'SII', 'Info', 'Français', 'Anglais',
          'TIPE'
        ]);
        break;
      case 'BCPST':
        base.addAll(
            ['Maths', 'Physique', 'SVT', 'Info', 'Français', 'Anglais']);
        break;
      case 'ECG':
        base.addAll(['Maths', 'ESH', 'Culture G', 'Anglais', 'LV2']);
        break;
      default:
        base.addAll(['Maths', 'Physique', 'Info', 'Français', 'Anglais']);
    }
    base.addAll(AppModel.instance.matieres);
    return base.toList();
  }

  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon emploi du temps'),
        actions: [
          IconButton(
            tooltip: 'Aide',
            icon: const Icon(Icons.help_outline),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                duration: Duration(seconds: 6),
                content: Text(
                    'Tape une case vide pour poser un bloc (palette pré-remplie). '
                    'Tape un bloc pour le modifier. Semaine A = moitié gauche, B = moitié droite. '
                    'Le roulement A/B se règle dans Réglages → Calendrier.'),
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, contraintes) {
          final colW =
              ((contraintes.maxWidth - 34) / 6).clamp(70.0, 200.0);
          final gridW = 34 + colW * 6;
          const gridH = (_hFin - _hDebut) * _cellH;
          return SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: gridW,
                child: Column(
                  children: [
                    // En-tete des jours
                    Row(
                      children: [
                        const SizedBox(width: 34),
                        for (final j in _jours)
                          SizedBox(
                            width: colW,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(j,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                      ],
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Colonne des heures
                        SizedBox(
                          width: 34,
                          height: gridH,
                          child: Column(
                            children: [
                              for (var h = _hDebut; h < _hFin; h++)
                                SizedBox(
                                  height: _cellH,
                                  child: Text('${h}h',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: couleurSecondaire(context))),
                                ),
                            ],
                          ),
                        ),
                        for (var jour = 1; jour <= 6; jour++)
                          SizedBox(
                            width: colW,
                            height: gridH,
                            child: Stack(
                              children: [
                                // Cases cliquables + quadrillage
                                Column(
                                  children: [
                                    for (var h = _hDebut; h < _hFin; h++)
                                      InkWell(
                                        onTap: () => _creer(jour, h),
                                        child: Container(
                                          height: _cellH,
                                          decoration: BoxDecoration(
                                            border: Border(
                                              left: BorderSide(
                                                  color: Colors.grey.shade200),
                                              bottom: BorderSide(
                                                  color: Colors.grey.shade200),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                // Blocs poses
                                for (final r in m.routinesJourBrut(jour))
                                  _bloc(r, colW),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _bloc(Routine r, double colW) {
    final top = (r.debutMin / 60 - _hDebut) * _cellH;
    if (top < 0) return const SizedBox.shrink();
    final h = (r.dureeMin / 60 * _cellH).clamp(18.0, 600.0);
    final demi = r.semaines != 0;
    final couleur = r.matiere.isEmpty
        ? Colors.blueGrey
        : Color(subjectColor(r.matiere));
    return Positioned(
      top: top,
      left: r.semaines == 2 ? (colW - 4) / 2 + 2 : 2,
      width: demi ? (colW - 4) / 2 - 1 : colW - 4,
      height: h,
      child: InkWell(
        onTap: () => _editer(r),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: couleur.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${r.titre}${r.semaines == 1 ? ' (A)' : r.semaines == 2 ? ' (B)' : ''}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 9.5,
                fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  // ---------- Creation depuis la palette ----------

  Future<void> _creer(int jour, int heure) async {
    final choix = await feuilleAdaptative<(String, bool)>(
      context,
      (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '${['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'][jour - 1]} ${heure}h — quoi ?',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Text('Cours',
                  style: TextStyle(fontSize: 12, color: couleurSecondaire(context))),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final mat in _matieresPalette)
                    ActionChip(
                      avatar: CircleAvatar(
                          backgroundColor: Color(subjectColor(mat)), radius: 6),
                      label: Text(mat, style: const TextStyle(fontSize: 12)),
                      onPressed: () => Navigator.pop(context, (mat, true)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text('Vie quotidienne',
                  style: TextStyle(fontSize: 12, color: couleurSecondaire(context))),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final v in _vie)
                    ActionChip(
                      label: Text(v, style: const TextStyle(fontSize: 12)),
                      onPressed: () => Navigator.pop(context, (v, false)),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 14),
                    label:
                        const Text('Autre…', style: TextStyle(fontSize: 12)),
                    onPressed: () => Navigator.pop(context, ('', false)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (choix == null || !mounted) return;
    var (titre, estMatiere) = choix;
    if (titre.isEmpty) {
      final ctl = TextEditingController();
      final saisi = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Autre activité'),
          content: TextField(
              controller: ctl,
              autofocus: true,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), hintText: 'ex. Solfège')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(context, ctl.text.trim()),
                child: const Text('OK')),
          ],
        ),
      );
      if (saisi == null || saisi.isEmpty || !mounted) return;
      titre = saisi;
    }
    final params = await _parametres(
        titreInitial: titre, dureeInitiale: estMatiere ? 60 : 30);
    if (params == null) return;
    AppModel.instance.addRoutine(Routine(
      titre: titre,
      jour: jour,
      debutMin: heure * 60,
      dureeMin: params.$1,
      matiere: estMatiere ? titre : '',
      semaines: params.$2,
    ));
    setState(() {});
  }

  /// (duree, semaines) ou null si annule.
  Future<(int, int)?> _parametres(
      {required String titreInitial, required int dureeInitiale}) {
    var duree = dureeInitiale;
    var semaines = 0;
    return showDialog<(int, int)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(titreInitial),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Durée : '),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: duree,
                    items: [
                      for (final d in const [30, 60, 90, 120, 150, 180, 240])
                        DropdownMenuItem(
                            value: d,
                            child: Text(d < 60
                                ? '$d min'
                                : '${d ~/ 60} h${d % 60 == 0 ? '' : ' 30'}')),
                    ],
                    onChanged: (v) => setLocal(() => duree = v ?? 60),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (var s = 0; s < kSemainesLabels.length; s++)
                    ChoiceChip(
                      label: Text(kSemainesLabels[s],
                          style: const TextStyle(fontSize: 12)),
                      selected: semaines == s,
                      onSelected: (_) => setLocal(() => semaines = s),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(context, (duree, semaines)),
                child: const Text('Poser le bloc')),
          ],
        ),
      ),
    );
  }

  // ---------- Edition d'un bloc ----------

  Future<void> _editer(Routine r) async {
    var time = TimeOfDay(hour: r.debutMin ~/ 60, minute: r.debutMin % 60);
    var duree = r.dureeMin;
    var semaines = r.semaines;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(r.titre),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(time.format(context)),
                    onPressed: () async {
                      final t = await showTimePicker(
                          context: context, initialTime: time);
                      if (t != null) setLocal(() => time = t);
                    },
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: duree,
                    items: [
                      for (final d in ({30, 60, 90, 120, 150, 180, 240, duree}
                            .toList()
                          ..sort()))
                        DropdownMenuItem(
                            value: d,
                            child: Text(d < 60
                                ? '$d min'
                                : '${d ~/ 60} h${d % 60 == 0 ? '' : ' ${(d % 60).toString().padLeft(2, '0')}'}')),
                    ],
                    onChanged: (v) => setLocal(() => duree = v ?? 60),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (var s = 0; s < kSemainesLabels.length; s++)
                    ChoiceChip(
                      label: Text(kSemainesLabels[s],
                          style: const TextStyle(fontSize: 12)),
                      selected: semaines == s,
                      onSelected: (_) => setLocal(() => semaines = s),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'suppr'),
              child:
                  const Text('Supprimer', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(context, 'ok'),
                child: const Text('OK')),
          ],
        ),
      ),
    );
    final m = AppModel.instance;
    if (action == 'suppr') {
      m.deleteRoutine(r.id);
    } else if (action == 'ok') {
      r
        ..debutMin = time.hour * 60 + time.minute
        ..dureeMin = duree
        ..semaines = semaines;
      m.updateRoutine(r);
    }
    if (mounted) setState(() {});
  }
}
