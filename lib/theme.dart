import 'package:flutter/material.dart';

/// Couleur de texte SECONDAIRE qui suit le theme : `Colors.grey.shade600`
/// code en dur etait passable sur fond clair (contraste ~4:1, deja sous le
/// seuil AA pour du petit texte) et franchement illisible en theme sombre.
/// `onSurfaceVariant` est prevu exactement pour ca dans Material 3, dans
/// les deux themes.
Color couleurSecondaire(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant;
