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
  // Le standard exige des fins de ligne CRLF (\r\n).
  void line(String s) => b.write('$s\r\n');

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
