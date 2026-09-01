import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';

/// GRILLE HORAIRE facon Google Calendar (Agenda sur grand ecran) :
/// heures en gouttiere a gauche, 7 colonnes-jours qui remplissent la
/// largeur, chaque cours/kholle/evenement place a sa VRAIE heure avec sa
/// duree, trait rouge « maintenant » sur la colonne du jour. Les elements
/// sans heure (DS, DM, oral non date) vivent dans une rangee « journee »
/// sous l'en-tete. La grille prend TOUTE la hauteur disponible ; si la
/// fenetre est trop basse, elle defile verticalement (min 44 px par heure).
class GrilleSemaine extends StatefulWidget {
  final DateTime debut;
  final int jours;
  const GrilleSemaine({super.key, required this.debut, this.jours = 7});

  @override
  State<GrilleSemaine> createState() => _GrilleSemaineState();
}

class _Bloc {
  final int debutMin;
  final int dureeMin;
  final String label;
  final Color couleur;
  final bool important;
  _Bloc(this.debutMin, this.dureeMin, this.label, this.couleur,
      this.important);
}

class _GrilleSemaineState extends State<GrilleSemaine> {
  final _scroll = ScrollController();
  bool _cadre = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    final now = DateTime.now();
    final scheme = Theme.of(context).colorScheme;

    // ---- Collecte : blocs horaires + elements "journee" par jour ----
    final parJour = <List<_Bloc>>[];
    final journee = <List<(String, Color)>>[];
    var minH = 8, maxH = 22;
    for (var i = 0; i < widget.jours; i++) {
      final d = widget.debut.add(Duration(days: i));
      final blocs = <_Bloc>[];
      final jour = <(String, Color)>[];
      final plage = m.plageSansCours(d);
      if (plage != null) jour.add(('🏖 ${plage.titre}', context.tokens.repos));
      if (plage == null) {
        for (final r in m.routinesLe(d)) {
          blocs.add(_Bloc(
            r.debutMin,
            r.dureeMin,
            r.titre,
            r.matiere.isEmpty
                ? context.tokens.repos
                : Color(subjectColor(r.matiere)),
            false,
          ));
        }
      }
      for (final e in m.evenementsLe(d)) {
        blocs.add(_Bloc(
          e.debutMin,
          e.dureeMin,
          '⭐ ${e.titre}',
          e.matiere.isEmpty ? context.tokens.repos : Color(subjectColor(e.matiere)),
          false,
        ));
      }
      for (final c in m.colles) {
        if (c.start.year == d.year &&
            c.start.month == d.month &&
            c.start.day == d.day) {
          blocs.add(_Bloc(
            c.start.hour * 60 + c.start.minute,
            c.dureeMin,
            '🎤 Khôlle ${c.matiere}${c.salle.isEmpty ? '' : ' · s.${c.salle}'}',
            Color(subjectColor(c.matiere)),
            true,
          ));
        }
      }
      for (final ds in m.ds) {
        if (ds.date.year == d.year &&
            ds.date.month == d.month &&
            ds.date.day == d.day) {
          // Avec une heure saisie, le DS est un VRAI bloc de la grille
          // (comme une kholle) — sans heure, pastille de journee.
          if (ds.debutMin != null) {
            blocs.add(_Bloc(
              ds.debutMin!,
              ds.dureeMin,
              '📝 ${ds.titre} ${ds.matiere}',
              Color(subjectColor(ds.matiere)),
              true,
            ));
          } else {
            jour.add((
              '📝 ${ds.titre} ${ds.matiere}',
              Color(subjectColor(ds.matiere))
            ));
          }
        }
      }
      for (final dev in m.devoirsARendre()) {
        if (dev.dateRendu.year == d.year &&
            dev.dateRendu.month == d.month &&
            dev.dateRendu.day == d.day) {
          jour.add((
            '📥 ${dev.titre} ${dev.matiere}',
            Color(subjectColor(dev.matiere))
          ));
        }
      }
      for (final o in m.oraux) {
        if (o.date != null &&
            o.date!.year == d.year &&
            o.date!.month == d.month &&
            o.date!.day == d.day) {
          if (o.debutMin != null) {
            blocs.add(_Bloc(
              o.debutMin!,
              60,
              '🎓 ${o.concours} ${o.epreuve}',
              Color(subjectColor(o.epreuve)),
              true,
            ));
          } else {
            jour.add((
              '🎓 Oral ${o.concours} ${o.epreuve}',
              Color(subjectColor(o.epreuve))
            ));
          }
        }
      }
      blocs.sort((a, b) => a.debutMin.compareTo(b.debutMin));
      for (final b in blocs) {
        if (b.debutMin ~/ 60 < minH) minH = b.debutMin ~/ 60;
        final fin = ((b.debutMin + b.dureeMin) + 59) ~/ 60;
        if (fin > maxH) maxH = fin;
      }
      parJour.add(blocs);
      journee.add(jour);
    }
    if (minH < 0) minH = 0;
    if (maxH > 24) maxH = 24;
    final aJournee = journee.any((j) => j.isNotEmpty);

    return LayoutBuilder(
      builder: (context, contraintes) {
        const gouttiere = 46.0;
        final enTeteH = 30.0 + (aJournee ? 26.0 : 0.0);
        // Chaque heure remplit la hauteur restante, minimum 44 px.
        final hph = ((contraintes.maxHeight - enTeteH - 6) / (maxH - minH))
            .clamp(44.0, 120.0);
        final grilleH = hph * (maxH - minH);
        final deborde = grilleH > contraintes.maxHeight - enTeteH;

        // Premier affichage d'une grille qui deborde : on se cadre sur
        // le debut de journee de cours (ou l'heure courante).
        if (deborde && !_cadre) {
          _cadre = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scroll.hasClients) return;
            final cible = ((now.hour - 1 - minH) * hph)
                .clamp(0.0, _scroll.position.maxScrollExtent);
            _scroll.jumpTo(cible);
          });
        }

        Widget colonne(int i) {
          final d = widget.debut.add(Duration(days: i));
          final estAujourdhui = d.year == now.year &&
              d.month == now.month &&
              d.day == now.day;
          // Decalage a droite pour les blocs qui en chevauchent un autre.
          final blocs = parJour[i];
          final decalages = List<int>.filled(blocs.length, 0);
          for (var a = 0; a < blocs.length; a++) {
            for (var b = 0; b < a; b++) {
              if (blocs[b].debutMin + blocs[b].dureeMin > blocs[a].debutMin &&
                  decalages[b] == decalages[a]) {
                decalages[a]++;
              }
            }
          }
          return Expanded(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                // Fond + separateur vertical + lignes d'heures.
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: estAujourdhui
                          ? scheme.primary.withValues(alpha: 0.045)
                          : null,
                      border: Border(
                          left: BorderSide(
                              color: Theme.of(context).colorScheme.outlineVariant)),
                    ),
                  ),
                ),
                for (var h = minH + 1; h < maxH; h++)
                  Positioned(
                    top: (h - minH) * hph,
                    left: 0,
                    right: 0,
                    child: Container(
                        height: 1, color: Colors.grey.withValues(alpha: 0.13)),
                  ),
                for (var b = 0; b < blocs.length; b++)
                  Positioned(
                    top: (blocs[b].debutMin - minH * 60) / 60 * hph + 1,
                    left: 3.0 + decalages[b] * 10,
                    right: 3,
                    height:
                        (blocs[b].dureeMin / 60 * hph - 2).clamp(16.0, 999.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                            blocs[b]
                                .couleur
                                .withValues(alpha: blocs[b].important ? 0.30 : 0.16),
                            Theme.of(context).canvasColor),
                        borderRadius: BorderRadius.circular(kRayonPetit),
                        border: Border(
                            left: BorderSide(
                                color: blocs[b].couleur, width: 3)),
                      ),
                      child: Text(
                        '${blocs[b].label}\n${frHeureMin(blocs[b].debutMin)} – ${frHeureMin(blocs[b].debutMin + blocs[b].dureeMin)}',
                        maxLines: blocs[b].dureeMin >= 55 ? 3 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.25,
                          color: blocs[b].couleur,
                          fontWeight: blocs[b].important
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                // Trait rouge « maintenant ».
                if (estAujourdhui &&
                    now.hour >= minH &&
                    now.hour < maxH) ...[
                  Positioned(
                    top: (now.hour * 60 + now.minute - minH * 60) / 60 * hph -
                        1,
                    left: 0,
                    right: 0,
                    child: Container(height: 2, color: context.tokens.urgent),
                  ),
                  Positioned(
                    top: (now.hour * 60 + now.minute - minH * 60) / 60 * hph -
                        4,
                    left: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: context.tokens.urgent, shape: BoxShape.circle),
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- En-tetes des jours (+ rangee « journee ») ----
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: gouttiere),
                for (var i = 0; i < widget.jours; i++)
                  Expanded(
                    child: Builder(builder: (context) {
                      final d = widget.debut.add(Duration(days: i));
                      final estAujourdhui = d.year == now.year &&
                          d.month == now.month &&
                          d.day == now.day;
                      final jl = frJour(d);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${jl[0].toUpperCase()}${jl.substring(1, 3)}. ${d.day}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: estAujourdhui
                                            ? scheme.primary
                                            : couleurSecondaire(context)),
                                  ),
                                ),
                                if (estAujourdhui)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: scheme.primary,
                                      borderRadius: BorderRadius.circular(kRayonPetit),
                                    ),
                                    child: const Text('auj.',
                                        style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white)),
                                  ),
                              ],
                            ),
                            if (aJournee)
                              SizedBox(
                                height: 24,
                                child: Row(
                                  children: [
                                    for (final j in journee[i].take(2))
                                      Flexible(
                                        child: Container(
                                          margin:
                                              const EdgeInsets.only(right: 3),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: j.$2.withValues(alpha: 0.16),
                                            borderRadius:
                                                BorderRadius.circular(kRayonPetit),
                                          ),
                                          child: Text(j.$1,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: j.$2)),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                  ),
              ],
            ),
            const SizedBox(height: kEsp4),
            // ---- La grille ----
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                physics: deborde
                    ? null
                    : const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  height: grilleH,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Gouttiere des heures.
                      SizedBox(
                        width: gouttiere,
                        height: grilleH,
                        child: Stack(
                          children: [
                            for (var h = minH; h <= maxH; h++)
                              Positioned(
                                top: (h - minH) * hph - 7,
                                right: 8,
                                child: Text(
                                  '${h}h',
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      color: couleurSecondaire(context)),
                                ),
                              ),
                          ],
                        ),
                      ),
                      for (var i = 0; i < widget.jours; i++) colonne(i),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// "8h", "8h30"…
String frHeureMin(int minutes) {
  final h = minutes ~/ 60;
  final mn = minutes % 60;
  return '${h}h${mn == 0 ? '' : mn.toString().padLeft(2, '0')}';
}
