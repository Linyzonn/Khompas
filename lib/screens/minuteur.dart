import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models.dart';
import '../store.dart';

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
            if (m.chapitres[i].prochaineRevision != null) {
              // Chapitre suivi en revision espacee : "Ca va" par defaut
              // (l'intervalle double), faute d'auto-evaluation ici.
              m.evaluerRevision(b.chapitreId!, 'cava');
            } else {
              m.chapitres[i].dernierRevu = DateTime.now();
              m.updateChapitre(m.chapitres[i]);
            }
          }
        }
      }
    }
    if (index + 1 >= widget.blocs.length) {
      termine = true;
      finBloc = null;
      WakelockPlus.disable();
    } else {
      index++;
      running = true;
      finBloc = DateTime.now().add(Duration(minutes: bloc.minutes));
    }
  }

  @override
  Widget build(BuildContext context) {
    final couleur = termine
        ? Colors.green
        : bloc.pause
            ? Colors.teal
            : Color(subjectColor(bloc.matiere));
    final total = termine ? 1 : bloc.minutes * 60;
    final r = restant;
    return Scaffold(
      appBar: AppBar(title: const Text('Minuteur')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (termine) ...[
              const Center(child: Text('🎉', style: TextStyle(fontSize: 56))),
              const SizedBox(height: 12),
              const Center(
                child: Text('Session terminée — séances enregistrées !',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 24),
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
                            fontSize: 13, color: Colors.grey.shade600)),
                  ),
                ),
              const SizedBox(height: 24),
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
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: 1 - r / total,
                color: couleur,
                minHeight: 6,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(running ? Icons.pause : Icons.play_arrow),
                      label: Text(running ? 'Pause' : 'Reprendre'),
                      onPressed: _pauseOuReprise,
                    ),
                  ),
                  const SizedBox(width: 12),
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
              const SizedBox(height: 12),
              Text(
                'L\'écran reste allumé pendant la session.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
