import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

/// PASSERELLE VERS KHODE — l'app d'entrainement a l'informatique (ITC) qui
/// vit a cote de Khompas sur le PC de l'eleve.
///
/// Principe : Khompas ne SAIT pas si Khode est installe, et ne doit surtout
/// pas afficher un bouton mort. On interroge donc le systeme : le protocole
/// `khode://` n'est enregistre QUE par l'installeur de Khode. Pas de
/// protocole = pas de bouton, silencieusement.
///
/// Cote Khode (Electron), l'enregistrement se fait avec
/// `app.setAsDefaultProtocolClient('khode')`.
class Khode {
  /// Schema d'URL enregistre par l'installeur de Khode.
  static const String _schema = 'khode';

  /// Resultat de la derniere detection (null = pas encore cherche).
  /// Mis en cache : `canLaunchUrl` interroge le registre systeme, inutile
  /// de le refaire a chaque rebuild d'un ecran.
  static bool? _disponible;

  /// Khode est-il installe sur CET appareil ?
  /// Toujours false sur le web et sur mobile : Khode est une application de
  /// bureau, il n'existe pas de version telephone.
  static bool get disponible => _disponible ?? false;

  /// Detection unique, au demarrage. Silencieuse : une plateforme qui ne
  /// sait pas repondre (web, mobile) laisse simplement le lien masque.
  static Future<void> detecter() async {
    if (_disponible != null) return;
    if (kIsWeb) {
      // Sur navigateur, `canLaunchUrl` d'un schema inconnu ne renvoie rien
      // de fiable — et ouvrir une app de bureau depuis un onglet n'a pas
      // de sens. On ne propose pas la passerelle.
      _disponible = false;
      return;
    }
    try {
      _disponible = await canLaunchUrl(Uri(scheme: _schema, host: ''));
    } catch (_) {
      // Plateforme sans gestionnaire d'URL : on masque le lien.
      _disponible = false;
    }
  }

  /// Ouvre Khode. [theme] cible un theme precis du programme ITC (ex.
  /// « recursivite ») — Khode l'ouvre directement si l'URL le porte.
  /// Retourne false si l'ouverture a echoue (Khode desinstalle entre-temps :
  /// on remet alors la detection a zero pour que le bouton disparaisse).
  static Future<bool> ouvrir({String? theme}) async {
    if (!disponible) return false;
    final uri = Uri(
      scheme: _schema,
      host: 'ouvrir',
      queryParameters: theme == null || theme.trim().isEmpty
          ? null
          : {'theme': theme.trim()},
    );
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _disponible = false;
      return ok;
    } catch (_) {
      _disponible = false;
      return false;
    }
  }
}
