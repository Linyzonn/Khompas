/// Bibliotheque de CONSIGNES D'ACTION par matiere et type de travail.
/// Principe (Dunlosky 2013, Bjork) : le rappel actif (se tester) et la
/// repetition espacee battent largement la relecture. Chaque suggestion du
/// plan du soir porte donc une consigne TESTABLE — la methode par defaut
/// de tout le monde etant, sinon, de relire (peu efficace).
library;

/// Types : 'rappel' (revision espacee), 'consolider' (chapitre fragile),
/// 'kholle', 'ds', 'fond', 'revision' (mode concours), 'oral' (mode oraux).
String consigneDe(String matiere, String type) {
  final cat = _categorie(matiere);
  return _table[cat]?[type] ?? _table['defaut']![type] ?? '';
}

/// Consigne pour la preparation d'une EPREUVE ORALE de concours.
/// [epreuve] peut etre une matiere ('Maths') ou une epreuve speciale
/// ('TIPE', 'ADS', 'SII (manip)').
String consigneOral(String epreuve) {
  final e = epreuve.trim().toLowerCase();
  if (e.contains('tipe')) {
    return 'Déroule ta présentation TIPE à voix haute, CHRONO (respecte le format du concours), puis prépare tes réponses à 3 questions pièges (limites, choix de méthode, ordres de grandeur).';
  }
  if (e.contains('ads')) {
    return 'Entraînement ADS : lis un article scientifique 20 min, construis une synthèse structurée, puis présente-la à voix haute en 10 min chrono.';
  }
  if (e.contains('manip') || e.contains('tp')) {
    return 'Refais mentalement un protocole type : matériel, montage, mesures, incertitudes. Verbalise chaque étape comme devant l\'examinateur.';
  }
  return consigneDe(epreuve, 'oral');
}

String _categorie(String matiere) {
  final m = matiere.trim().toLowerCase();
  if (m.contains('math')) return 'maths';
  if (m.contains('physique') || m == 'pc') return 'physique';
  if (m.contains('chimie')) return 'chimie';
  if (m.contains('sii') || m == 'si' || m.contains('ingenieur')) return 'sii';
  if (m.contains('info')) return 'info';
  if (m.contains('angl') ||
      m.contains('lv') ||
      m.contains('espagnol') ||
      m.contains('allemand')) {
    return 'langue';
  }
  if (m.contains('fran') || m.contains('philo') || m.contains('lettres')) {
    return 'francais';
  }
  return 'defaut';
}

const Map<String, Map<String, String>> _table = {
  'maths': {
    'rappel':
        'Feuille blanche 10 min : écris de mémoire théorèmes, hypothèses et définitions, puis compare au cours. Les trous = ton programme.',
    'consolider':
        'Reprends un exo raté du TD et refais-le EN ENTIER sans regarder la correction. Cherche ≥ 10 min avant d\'ouvrir quoi que ce soit.',
    'kholle':
        'Questions de cours à voix haute comme en colle, puis 2 exos types du programme au brouillon, chrono.',
    'ds':
        'Mini-DS chrono : 1-2 exos d\'annales de DS, puis relecture ciblée de tes erreurs. Pas de relecture passive du cours.',
    'fond':
        'Refais les exos RATÉS de la semaine (pas les réussis) — cherche avant d\'ouvrir le corrigé.',
    'revision':
        'Feuille blanche sur le chapitre (plan + théorèmes de mémoire), puis 1 exo type sans le cours.',
    'oral':
        'Exo au tableau (ou brouillon) en EXPLIQUANT chaque étape à voix haute à un examinateur imaginaire — c\'est l\'exercice de l\'oral, pas la résolution silencieuse.',
  },
  'physique': {
    'rappel':
        'Plan du chapitre de mémoire + les grands résultats sous chaque partie. Récite le cours À L\'ÉCRIT, pas en relisant.',
    'consolider':
        'Refais une démo type SANS le cours, puis un exo type en schématisant systématiquement.',
    'kholle':
        'Les démos exigibles du programme sans le cours + 1 exo type chrono (le satellite, le circuit RLC…).',
    'ds':
        'Repère les exos de TD qui font des « premières parties » classiques de DS et refais-les sans correction.',
    'fond':
        'Un exo type refait sans le corrigé + les ordres de grandeur du chapitre de mémoire.',
    'revision':
        'Démos types de mémoire + 1 exo d\'application. Vérifie tes ordres de grandeur.',
    'oral':
        'Un exo de banque d\'oral au tableau en verbalisant : modélisation, équations, ordres de grandeur. Termine par 2 questions de cours à voix haute.',
  },
  'chimie': {
    'rappel':
        'Redessine DE MÉMOIRE les mécanismes / diagrammes du chapitre (E-pH, binaires…), puis compare. Dessin + texte = double ancrage.',
    'consolider':
        'Un exo type par famille (dosage, cinétique…) refait sans la correction.',
    'kholle': 'Mécanismes au tableau de mémoire + questions de cours à voix haute.',
    'ds': 'Refais tes fiches de mécanismes DE MÉMOIRE, puis un exo d\'annale.',
    'fond': 'Un mécanisme redessiné de mémoire + un exo type.',
    'revision': 'Mécanismes et diagrammes de mémoire, puis exo d\'annale du chapitre.',
    'oral':
        'Mécanisme expliqué à voix haute en le dessinant, puis un exo d\'oral en commentant chaque choix.',
  },
  'sii': {
    'rappel':
        'Schémas-blocs et méthodes types DE MÉMOIRE ; retrace le schéma cinématique du TD sans le regarder.',
    'consolider': 'Un problème COMPLET plutôt que des morceaux d\'exos.',
    'kholle': 'Méthodes types du programme déroulées au brouillon, sans le cours.',
    'ds': 'Une annale de DS (ou un problème complet) en conditions.',
    'fond': 'Un problème complet, schémas d\'abord.',
    'revision': 'Méthodes types de mémoire + un problème d\'annale.',
    'oral':
        'Déroule une méthode type en la commentant à voix haute, schéma au tableau d\'abord.',
  },
  'info': {
    'rappel':
        'Réécris les algos du cours DE ZÉRO (pas de relecture de code), puis trace leur exécution sur un petit exemple à la main.',
    'consolider': 'Refais un TP clé sans la correction.',
    'kholle': 'Questions de cours + un algo écrit au tableau/brouillon de mémoire.',
    'ds': 'Refais les TP clés sans correction + trace d\'exécution à la main.',
    'fond': 'Un algo réécrit de zéro + sa trace sur un exemple.',
    'revision': 'Réécris les algos types de mémoire + une trace d\'exécution.',
    'oral':
        'Écris un algo au tableau en expliquant tes choix à voix haute, puis fais-en la trace en la commentant.',
  },
  'langue': {
    'rappel':
        '10-15 min de vocabulaire en rappel actif (cache la colonne, récite, vérifie) — la régularité bat le gros bloc du dimanche.',
    'consolider':
        'Un article de presse : lis, puis résume À L\'ORAL en 2-3 min sans le texte.',
    'kholle':
        'Press review chrono : lecture → synthèse orale 3 min → opinion. Enregistre-toi et réécoute.',
    'ds': 'Un essai type en conditions + relecture de tes erreurs de grammaire récurrentes.',
    'fond': '10 mots de vocab en rappel actif + 5 min d\'audio (podcast, news).',
    'revision': 'Press review chrono + vocabulaire des colles précédentes en rappel.',
    'oral':
        'Press review complète en conditions d\'oral : lecture chrono, synthèse orale, opinion, questions. Enregistre-toi et réécoute.',
  },
  'francais': {
    'rappel':
        '2-3 citations du thème en rappel actif (récite, vérifie) — la régularité fait toute la note.',
    'consolider':
        'Un plan détaillé en 20 min sur un sujet d\'annale, SANS rédiger. Compare ensuite aux bons plans.',
    'kholle': 'Résumé chronométré d\'un texte + tes citations récitées de mémoire.',
    'ds': 'Un plan détaillé complet (20 min) + l\'intro rédigée entièrement.',
    'fond': '2 citations apprises en rappel actif + relecture ACTIVE d\'une fiche œuvre (cache, récite).',
    'revision': 'Plans détaillés en série sur les annales du thème + citations de mémoire.',
    'oral':
        'Présente un plan à voix haute en 5 min chrono, citations de mémoire incluses.',
  },
  'defaut': {
    'rappel':
        'Feuille blanche 10 min : écris de mémoire l\'essentiel du chapitre, puis compare. Les trous = ton programme.',
    'consolider': 'Refais un exercice raté sans regarder la correction.',
    'kholle': 'Questions de cours à voix haute + un exercice type chrono.',
    'ds': 'Un sujet type en conditions, puis relecture ciblée des erreurs.',
    'fond': 'Teste-toi sur le dernier cours (feuille blanche) plutôt que de relire.',
    'revision': 'L\'essentiel du chapitre de mémoire, puis un exercice d\'annale.',
    'oral':
        'Travaille À VOIX HAUTE en conditions d\'oral : questions de cours récitées, puis un exercice expliqué comme à un examinateur, chrono.',
  },
};
