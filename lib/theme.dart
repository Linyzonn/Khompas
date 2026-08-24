import 'package:flutter/material.dart';

/// FONDATIONS VISUELLES de Khompas — voir DESIGN.md pour le pourquoi.
/// Identite : « instrument de bord, pas application de bien-etre » — dense,
/// lisible en 30 secondes le soir, la couleur porte une INFORMATION et
/// jamais une decoration.
///
/// DA 2026 (board « DA Khompas ») : primaire BLEU D'ENCRE #3B54C0, fond de
/// page teinte a ~2 % par la primaire, cartes blanches, barre d'accent 4 px,
/// icones Material a la place des emojis.
///
/// Tout le style vit ici : aucun ecran ne doit ecrire `Colors.grey.shade700`
/// ni choisir un rayon au hasard. Deux sources autorisees :
///   - `Theme.of(context).colorScheme` pour le socle Material 3 ;
///   - `context.tokens` (ci-dessous) pour ce qui porte un SENS metier.

// ---------- Grille d'espacement (multiples de 4) ----------
// Valeurs autorisees, rien d'autre : une marge de 7 ou 13 est un bug.
const double kEsp4 = 4;
const double kEsp8 = 8;
const double kEsp12 = 12;
const double kEsp16 = 16;
const double kEsp24 = 24;
const double kEsp32 = 32;

// ---------- Formes ----------
const double kRayonPetit = 10; // chips, blocs compacts, boutons
const double kRayonCarte = 14; // cartes, dialogues, feuilles
const double kRayonJauge = 999; // barres de progression : pilule

// ---------- Mouvement ----------
const Duration kAnimCourte = Duration(milliseconds: 150);
const Duration kAnimMoyenne = Duration(milliseconds: 250);

// ---------- Primaire (DA « bleu d'encre ») ----------
const Color kPrimaire = Color(0xFF3B54C0);

/// Fond de page : la primaire a ~2 % sur blanc (clair) / une nuit teintee
/// bleu (sombre). Les cartes restent surface pure : la hierarchie vient du
/// contraste carte/fond, plus des bordures seules.
const Color kFondClair = Color(0xFFF5F6FA);
const Color kFondSombre = Color(0xFF14161E);
const Color kSurfaceSombre = Color(0xFF1C1F2A); // cartes en sombre

/// Couleurs SEMANTIQUES : chacune dit quelque chose.
@immutable
class KhompasTokens extends ThemeExtension<KhompasTokens> {
  /// Metadonnees, aides, textes de second plan.
  final Color texteSecondaire;

  /// Echeance imminente (≤ 24 h), retard, ce qui ne peut plus attendre.
  /// JAMAIS pour une mauvaise note : l'app ne culpabilise pas.
  final Color urgent;

  /// Echeance proche, conflit de synchro, « a verifier ».
  final Color attention;

  /// Fait, consolide, a jour, en avance.
  final Color succes;

  /// Rappel neutre, cartes de revision, trajet, information.
  final Color info;

  /// Jour off, vacances, dimanche : le repos est un etat legitime.
  final Color repos;

  const KhompasTokens({
    required this.texteSecondaire,
    required this.urgent,
    required this.attention,
    required this.succes,
    required this.info,
    required this.repos,
  });

  static const clair = KhompasTokens(
    texteSecondaire: Color(0xFF5B5B66),
    urgent: Color(0xFFC1442E),
    attention: Color(0xFF9A6511),
    succes: Color(0xFF1E7A4B),
    info: Color(0xFF3B5BC4),
    repos: Color(0xFF5A6B7C),
  );

  static const sombre = KhompasTokens(
    texteSecondaire: Color(0xFFB4B4C0),
    urgent: Color(0xFFFF9A85),
    attention: Color(0xFFE8B85C),
    succes: Color(0xFF6FD39B),
    info: Color(0xFF9DB2F5),
    repos: Color(0xFF9BAEC0),
  );

  @override
  KhompasTokens copyWith({
    Color? texteSecondaire,
    Color? urgent,
    Color? attention,
    Color? succes,
    Color? info,
    Color? repos,
  }) =>
      KhompasTokens(
        texteSecondaire: texteSecondaire ?? this.texteSecondaire,
        urgent: urgent ?? this.urgent,
        attention: attention ?? this.attention,
        succes: succes ?? this.succes,
        info: info ?? this.info,
        repos: repos ?? this.repos,
      );

  @override
  KhompasTokens lerp(ThemeExtension<KhompasTokens>? autre, double t) {
    if (autre is! KhompasTokens) return this;
    return KhompasTokens(
      texteSecondaire: Color.lerp(texteSecondaire, autre.texteSecondaire, t)!,
      urgent: Color.lerp(urgent, autre.urgent, t)!,
      attention: Color.lerp(attention, autre.attention, t)!,
      succes: Color.lerp(succes, autre.succes, t)!,
      info: Color.lerp(info, autre.info, t)!,
      repos: Color.lerp(repos, autre.repos, t)!,
    );
  }
}

extension TokensContext on BuildContext {
  KhompasTokens get tokens =>
      Theme.of(this).extension<KhompasTokens>() ?? KhompasTokens.clair;

  ColorScheme get couleurs => Theme.of(this).colorScheme;
}

Color couleurSecondaire(BuildContext context) => context.tokens.texteSecondaire;

/// Le theme complet, clair ou sombre.
ThemeData themeKhompas(Brightness luminosite) {
  final sombre = luminosite == Brightness.dark;
  final couleurs = ColorScheme.fromSeed(
    // DA 2026 : bleu d'encre. `primary` est force pour que les actions et
    // le « ce soir » gardent EXACTEMENT la teinte de la charte (fromSeed
    // seul la delave).
    seedColor: kPrimaire,
    brightness: luminosite,
  ).copyWith(
    primary: sombre ? const Color(0xFFAAB9F2) : kPrimaire,
    surface: sombre ? kSurfaceSombre : Colors.white,
  );
  final tokens = sombre ? KhompasTokens.sombre : KhompasTokens.clair;
  final bordure = BorderSide(color: couleurs.outlineVariant);
  final fond = sombre ? kFondSombre : kFondClair;

  return ThemeData(
    useMaterial3: true,
    colorScheme: couleurs,
    extensions: [tokens],
    // Fond de page teinte par la primaire (~2 %), cartes blanches : c'est
    // le contraste carte/fond qui structure l'ecran, la bordure precise.
    scaffoldBackgroundColor: fond,
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: kEsp12),
      clipBehavior: Clip.antiAlias,
      color: couleurs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRayonCarte),
        side: bordure,
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRayonCarte),
      ),
    ),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      headlineSmall: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
      titleLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: 15, height: 1.35),
      bodyMedium: TextStyle(fontSize: 14, height: 1.35),
      bodySmall: TextStyle(fontSize: 13, height: 1.35),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      // L'app bar vit sur le FOND teinte, pas sur une surface blanche :
      // le titre appartient a la page, pas a une barre.
      backgroundColor: fond,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: couleurs.onSurface,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRayonPetit),
        side: bordure,
      ),
      labelStyle: TextStyle(fontSize: 12.5, color: couleurs.onSurface),
      secondaryLabelStyle:
          TextStyle(fontSize: 12.5, color: couleurs.onSecondaryContainer),
      backgroundColor: couleurs.surface,
      selectedColor: couleurs.secondaryContainer,
      checkmarkColor: couleurs.onSecondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: kEsp8, vertical: kEsp4),
    ),
    listTileTheme: const ListTileThemeData(
      minVerticalPadding: kEsp8,
      minTileHeight: 44,
    ),
    dividerTheme: DividerThemeData(
      color: couleurs.outlineVariant,
      space: kEsp24,
      thickness: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRayonPetit),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRayonPetit),
      ),
      isDense: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRayonPetit),
        ),
        minimumSize: const Size(0, 44),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRayonPetit),
        ),
        minimumSize: const Size(0, 44),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRayonPetit),
        ),
      ),
    ),
  );
}

// ---------- Briques partagees ----------

/// Carte du cockpit : barre d'accent laterale teintee (le detail signature
/// de Khompas, AFFINEE a 4 px par la DA 2026) + titre en petites capitales.
Widget carteKhompas(
  BuildContext context, {
  required Color accent,
  required IconData icone,
  required String titre,
  required Widget enfant,
  VoidCallback? onTap,
}) {
  final corps = Container(
    decoration: BoxDecoration(
      border: Border(left: BorderSide(color: accent, width: 4)),
    ),
    padding: const EdgeInsets.all(kEsp12),
    width: double.infinity,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icone, size: 15, color: accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                titre.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: kEsp8),
        enfant,
      ],
    ),
  );
  return Card(
    child: onTap == null
        ? corps
        : InkWell(
            borderRadius: BorderRadius.circular(kRayonCarte),
            onTap: onTap,
            child: corps,
          ),
  );
}

/// Banniere d'alerte du tableau de bord. [labelAction] la rend cliquable.
Widget banniereKhompas(
  BuildContext context, {
  required Color couleur,
  required IconData icone,
  required String texte,
  String? labelAction,
  VoidCallback? action,
}) {
  return Card(
    color: couleur.withValues(alpha: 0.10),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(kRayonCarte),
      side: BorderSide(color: couleur.withValues(alpha: 0.55)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(kEsp12),
      child: LayoutBuilder(
        builder: (context, contraintes) {
          final etroit = contraintes.maxWidth < 480;
          final message = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icone, size: 20, color: couleur),
              const SizedBox(width: 10),
              Expanded(
                child: Text(texte,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          );
          if (labelAction == null) return message;
          final bouton = FilledButton.tonal(
            onPressed: action,
            child: Text(labelAction, style: const TextStyle(fontSize: 12.5)),
          );
          if (etroit) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                message,
                const SizedBox(height: kEsp8),
                Align(alignment: Alignment.centerRight, child: bouton),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: message),
              const SizedBox(width: kEsp8),
              bouton,
            ],
          );
        },
      ),
    ),
  );
}

/// Liste d'ecran CENTREE et bornee en largeur.
Widget listeCentree(
  BuildContext context, {
  required List<Widget> children,
  double largeurMax = 680,
  EdgeInsets padding = const EdgeInsets.all(kEsp16),
}) {
  return Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: largeurMax),
      child: ListView(padding: padding, children: children),
    ),
  );
}

/// Titre de section (au-dessus d'un groupe de reglages, d'une liste...).
Widget titreSection(BuildContext context, String texte) => Padding(
      padding: const EdgeInsets.only(bottom: kEsp8),
      child: Text(texte, style: Theme.of(context).textTheme.titleMedium),
    );

/// Style des metadonnees : « salle 12 · M. Dupont », aides sous un champ.
TextStyle styleMeta(BuildContext context) =>
    TextStyle(fontSize: 11.5, height: 1.35, color: couleurSecondaire(context));

/// Style d'un CHIFFRE CLE (heures, moyenne, compte a rebours) : chiffres
/// TABULAIRES pour que les colonnes s'alignent d'une ligne a l'autre.
TextStyle styleChiffre(BuildContext context, {double taille = 22}) => TextStyle(
      fontSize: taille,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: Theme.of(context).colorScheme.onSurface,
    );

/// Etat VIDE standard : jamais « Aucune donnee », toujours quoi faire.
/// DA 2026 : ICONE Material a la place de l'emoji. `emoji` reste accepte
/// en secours le temps de migrer les appels ; `icone` gagne s'il est fourni.
Widget etatVide(
  BuildContext context, {
  IconData? icone,
  String? emoji,
  required String message,
  Widget? action,
}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(kEsp32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icone != null)
            Icon(icone, size: 44, color: couleurSecondaire(context))
          else
            Text(emoji ?? '·', style: const TextStyle(fontSize: 44)),
          const SizedBox(height: kEsp12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13.5, height: 1.4, color: couleurSecondaire(context)),
          ),
          if (action != null) ...[
            const SizedBox(height: kEsp16),
            action,
          ],
        ],
      ),
    ),
  );
}
