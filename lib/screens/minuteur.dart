import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'dialogs.dart';

/// Un bloc de la session Pomodoro : travail (matiere + contenu) ou pause.
class BlocPomodoro {
  final String label;
  final String matiere;
  final int minutes;
  final bool pause;
  final String? chapitreId;
  BlocPomodoro(this.label, this.matiere, this.minutes,
      {this.pause = false, this.chapitreId});
}

/// Minuteur Pomodoro plein ecran : enchaine les blocs, enregistre chaque
/// bloc de travail termine comme une seance.
///
/// Le decompte est base sur un HORODATAGE de fin (pas sur un compteur
/// decremente a chaque tick) : si l'OS suspend l'app ou gele le Timer,
/// le temps reste juste au reveil. Wakelock actif pour garder l'ecran
/// allume pendant la session.
class MinuteurScreen extends StatefulWidget {
  final List<BlocPomodoro> blocs;
  const MinuteurScreen({super.key, required this.blocs});

  @override
  State<MinuteurScreen> createState() => _MinuteurScreenState();
}

class _MinuteurScreenState extends State<MinuteurScreen> {
  int index = 0;
  DateTime? finBloc; // instant de fin du bloc courant (null = en pause)
  int restantPause = 0; // secondes restantes memorisees pendant la pause
  bool running = true;
  bool termine = false;
  Timer? _tick;
  // Chapitres suivis en repetition espacee travailles pendant la session
  // (id -> matiere) : leur auto-evaluation est demandee EN FIN de session,
  // une seule fois par chapitre — jamais decidee a la place de l'eleve.
  final Map<String, String> _aEvaluer = {};
  bool _evalDemandee = false;

  BlocPomodoro get bloc => widget.blocs[index];

  int get restant {
    if (!running) return restantPause;
    if (finBloc == null) return 0;
    final r = finBloc!.difference(DateTime.now()).inSeconds;
    return r < 0 ? 0 : r;
  }

  @override
  void initState() {
    super.initState();
    finBloc = DateTime.now().add(Duration(minutes: widget.blocs.first.minutes));
    WakelockPlus.enable();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!running || termine) return;
      setState(() {
        if (restant <= 0) _finBloc(complet: true);
      });
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  void _pauseOuReprise() {
    setState(() {
      if (running) {
        restantPause = restant;
        finBloc = null;
        running = false;
      } else {
        finBloc = DateTime.now().add(Duration(seconds: restantPause));
        running = true;
      }
    });
  }

  void _finBloc({required bool complet}) {
    final b = bloc;
    if (!b.pause) {
      // Seance : le temps effectivement passe (bloc entier si complet).
      final faites = complet ? b.minutes : ((b.minutes * 60 - restant) ~/ 60);
      if (faites >= 5) {
        final m = AppModel.instance;
        m.addSeance(b.matiere, faites);
        if (b.chapitreId != null) {
          final i = m.chapitres.indexWhere((c) => c.id == b.chapitreId);
          if (i >= 0) {
            // Le temps passe ne dit RIEN du rappel reel : l'intervalle de
            // repetition espacee ne bouge que sur l'auto-evaluation de
            // l'eleve, demandee en fin de session. (Avant : un "ca va"
            // etait injecte automatiquement a CHAQUE bloc — deux tomates
            // sur le meme chapitre quadruplaient l'intervalle sans que
            // l'eleve se soit teste.)
            m.chapitres[i].dernierRevu = DateTime.now();
            m.updateChapitre(m.chapitres[i]);
            if (m.chapitres[i].prochaineRevision != null) {
              _aEvaluer[b.chapitreId!] = b.matiere;
            }
          }
        }
      }
    }
    if (index + 1 >= widget.blocs.length) {
      termine = true;
      finBloc = null;
      WakelockPlus.disable();
      if (_aEvaluer.isNotEmpty && !_evalDemandee) {
        _evalDemandee = true;
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _demanderEvaluations());
      }
    } else {
      index++;
      running = true;
      finBloc = DateTime.now().add(Duration(minutes: bloc.minutes));
    }
  }

  /// Auto-evaluation en 1 tap, chapitre par chapitre, en fin de session.
  /// Sans reponse (feuille fermee), seul dernierRevu a ete mis a jour :
  /// l'intervalle n'avance pas sur du temps passe.
  Future<void> _demanderEvaluations() async {
    final m = AppModel.instance;
    for (final e in _aEvaluer.entries) {
      if (!mounted) return;
      final nom = m.chapitres
          .firstWhere((c) => c.id == e.key,
              orElse: () => Chapitre(matiere: e.value, nom: e.value))
          .nom;
      final verdict = await demanderAutoEvaluation(
          context, '$nom — comment ça s\'est passé ?');
      if (verdict != null) m.evaluerRevision(e.key, verdict);
    }
    _aEvaluer.clear();
  }

  @override
  Widget build(BuildContext context) {
    final couleur = termine
        ? context.tokens.succes
        : bloc.pause
            ? context.tokens.succes
            : Color(subjectColor(bloc.matiere));
    final total = termine ? 1 : bloc.minutes * 60;
    final r = restant;
    return Scaffold(
      appBar: AppBar(title: const Text('Minuteur')),
      body: Padding(
        padding: const EdgeInsets.all(kEsp24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (termine) ...[
              const Center(child: Text('🎉', style: TextStyle(fontSize: 56))),
              const SizedBox(height: kEsp12),
              const Center(
                child: Text('Session terminée — séances enregistrées !',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: kEsp24),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Retour'),
              ),
            ] else ...[
              Center(
                child: Text(
                  bloc.pause ? '☕ Pause' : '🍅 ${index + 1}/${widget.blocs.length} · ${bloc.matiere}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              if (!bloc.pause)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(bloc.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: couleurSecondaire(context))),
                  ),
                ),
              const SizedBox(height: kEsp24),
              Center(
                child: Text(
                  '${(r ~/ 60).toString().padLeft(2, '0')}:${(r % 60).toString().padLeft(2, '0')}',
                  style: TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.bold,
                      color: couleur,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
              const SizedBox(height: kEsp12),
              LinearProgressIndicator(
                value: 1 - r / total,
                color: couleur,
                minHeight: 6,
              ),
              const SizedBox(height: kEsp24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(running ? Icons.pause : Icons.play_arrow),
                      label: Text(running ? 'Pause' : 'Reprendre'),
                      onPressed: _pauseOuReprise,
                    ),
                  ),
                  const SizedBox(width: kEsp12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.skip_next),
                      label: const Text('Passer'),
                      onPressed: () =>
                          setState(() => _finBloc(complet: false)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: kEsp12),
              Text(
                'L\'écran reste allumé pendant la session.',
                textAlign: TextAlign.center,
                style: styleMeta(context),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
