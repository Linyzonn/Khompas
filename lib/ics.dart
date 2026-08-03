import 'models.dart';

/// Genere un fichier .ics (calendrier standard) avec toutes les khôlles :
/// importe dans l'agenda du telephone, il donne les NOTIFICATIONS NATIVES
/// sans qu'on ait a gerer nous-memes les permissions de notification.
String buildIcs(List<Colle> colles) {
  String two(int n) => n.toString().padLeft(2, '0');
  String stamp(DateTime d) =>
      '${d.year}${two(d.month)}${two(d.day)}T${two(d.hour)}${two(d.minute)}00';

  // Echappement impose par le format iCalendar (RFC 5545) : sans lui, une
  // virgule ou un ";" dans un programme de colle casse l'import chez
  // certains clients calendrier.
  String esc(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll('\n', '\\n')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,');

  final b = StringBuffer();
  // Le standard exige des fins de ligne CRLF (\r\n) ET le PLIAGE des
  // lignes de plus de 75 octets (RFC 5545 §3.1) : une ligne continue sur
  // la suivante precedee d'un espace. Sans pliage, un DESCRIPTION portant
  // un long programme de colle fait rejeter le fichier ENTIER par certains
  // clients (Outlook/Exchange notamment).
  void line(String s) => b.write('${plieIcs(s)}\r\n');

  line('BEGIN:VCALENDAR');
  line('VERSION:2.0');
  line('PRODID:-//Khompas//Colloscope//FR');
  line('CALSCALE:GREGORIAN');
  for (final c in colles) {
    line('BEGIN:VEVENT');
    line('UID:khompas-${c.id}@khompas.app');
    line('DTSTAMP:${stamp(DateTime.now().toUtc())}Z');
    // Heures "flottantes" : interpretees dans le fuseau local du telephone.
    line('DTSTART:${stamp(c.start)}');
    line('DTEND:${stamp(c.end)}');
    final salle = c.salle.isEmpty ? '' : ' (salle ${c.salle})';
    line('SUMMARY:${esc('Khôlle ${c.matiere}$salle')}');
    final desc = <String>[];
    if (c.kholleur.isNotEmpty) desc.add('Khôlleur : ${c.kholleur}');
    if (c.programme.isNotEmpty) desc.add('Programme : ${c.programme}');
    if (desc.isNotEmpty) {
      line('DESCRIPTION:${esc(desc.join(' — '))}');
    }
    if (c.salle.isNotEmpty) line('LOCATION:${esc('Salle ${c.salle}')}');
    // Rappel 1h avant.
    line('BEGIN:VALARM');
    line('TRIGGER:-PT60M');
    line('ACTION:DISPLAY');
    line('DESCRIPTION:${esc('Khôlle ${c.matiere} dans 1h')}');
    line('END:VALARM');
    line('END:VEVENT');
  }
  line('END:VCALENDAR');
  return b.toString();
}

/// Plie une ligne iCalendar a 75 OCTETS maximum (RFC 5545 §3.1) : les
/// continuations commencent par un espace. La coupe se fait sur une
/// frontiere de caractere UTF-8 (jamais au milieu d'un accent) et evite de
/// separer une sequence echappee ("\\n", "\\,") en deux.
String plieIcs(String s) {
  const max = 75;
  final runes = s.runes.toList();
  final out = StringBuffer();
  var octets = 0;
  for (var i = 0; i < runes.length; i++) {
    var chunk = String.fromCharCode(runes[i]);
    var taille = utf8Len(runes[i]);
    // Une sequence echappee ("\\n", "\\,"...) s'ecrit d'un bloc : la
    // couper en deux la rendrait illisible pour le client calendrier.
    if (chunk == '\\' && i + 1 < runes.length) {
      chunk += String.fromCharCode(runes[i + 1]);
      taille += utf8Len(runes[i + 1]);
      i++;
    }
    if (octets + taille > max) {
      out.write('\r\n ');
      octets = 1; // l'espace de continuation compte dans les 75 octets
    }
    out.write(chunk);
    octets += taille;
  }
  return out.toString();
}

/// Nombre d'octets UTF-8 d'un point de code.
int utf8Len(int rune) {
  if (rune <= 0x7f) return 1;
  if (rune <= 0x7ff) return 2;
  if (rune <= 0xffff) return 3;
  return 4;
}
