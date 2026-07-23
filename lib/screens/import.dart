import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../ai_extractor.dart';
import '../api_client.dart';
import '../store.dart';
import 'settings.dart';
import 'verify.dart';

/// Import du colloscope, trois chemins :
/// - "code de classe" (serveur Khompas) : un eleve envoie les photos une
///   fois, tous les autres tapent le code + leur groupe. RECOMMANDE.
/// - "automatique" : photo(s) -> API Claude avec sa propre cle ;
/// - "copier-coller" (gratuit) : prompt colle dans SON appli d'IA.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final List<PieceColloscope> pieces = [];
  late final TextEditingController groupeCtl;
  late final TextEditingController codeCtl;
  bool busy = false;
  String busyLabel = '';

  @override
  void initState() {
    super.initState();
    final m = AppModel.instance;
    groupeCtl = TextEditingController(text: m.groupe.toString());
    codeCtl = TextEditingController(text: m.codeClasse);
  }

  void _setBusy(String label) => setState(() {
        busy = true;
        busyLabel = label;
      });

  void _clearBusy() {
    if (mounted) setState(() => busy = false);
  }

  String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  void _snack(String msg, {int secondes = 4}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: Duration(seconds: secondes),
      content: Text(msg),
    ));
  }

  Future<void> _pick(ImageSource source) async {
    final picker = ImagePicker();
    // On redimensionne des le pick : l'API vision reduit de toute facon les
    // images a ~1568 px de cote long, et le serveur borne chaque photo a
    // ~1,5 Mo. 1600 px suffit pour lire un colloscope net.
    if (source == ImageSource.gallery) {
      final files = await picker.pickMultiImage(
          imageQuality: 88, maxWidth: 1600, maxHeight: 1600);
      for (final f in files) {
        pieces.add(PieceColloscope(await f.readAsBytes()));
      }
    } else {
      final f = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 88,
          maxWidth: 1600,
          maxHeight: 1600);
      if (f != null) pieces.add(PieceColloscope(await f.readAsBytes()));
    }
    setState(() {});
  }

  Future<void> _pickPdf() async {
    // Beaucoup de colloscopes circulent en PDF : on le prend tel quel,
    // les IA (Gemini comme Claude) lisent les PDF nativement.
    final res = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    final bytes = res?.files.single.bytes;
    if (bytes == null) return;
    if (bytes.length > 3 * 1024 * 1024) {
      if (mounted) _snack('PDF trop lourd (3 Mo max) — exporte-le en qualité réduite ou fais des captures d\'écran.');
      return;
    }
    setState(() => pieces.add(PieceColloscope(bytes, pdf: true)));
  }

  int? _groupeValide() {
    final groupe = int.tryParse(groupeCtl.text.trim());
    if (groupe == null) {
      _snack("Indique d'abord ton numéro de groupe.");
    }
    return groupe;
  }

  void _versVerification(ExtractionResult result) {
    if (result.colles.isEmpty) {
      _snack(
          'Aucun créneau trouvé pour ce groupe — vérifie le numéro (et la photo).');
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => VerifyScreen(result: result)),
    );
  }

  // ---------- Chemin 1 : code de classe (serveur Khompas) ----------

  Future<void> _viaCode() async {
    final groupe = _groupeValide();
    if (groupe == null) return;
    final code = codeCtl.text.trim().toUpperCase();
    if (code.length != 6) {
      _snack('Le code de classe fait 6 caractères (ex. K7M2PX).');
      return;
    }
    final m = AppModel.instance;
    _setBusy(
        'Récupération de tes khôlles… (jusqu\'à 2 min si ton groupe est le premier à demander)');
    try {
      final result = await ApiKhompas(m.serverUrl).groupe(code, groupe);
      m.setProfil(filiere: m.filiere, groupe: groupe);
      m.setCodeClasse(code);
      if (!mounted) return;
      _versVerification(result);
    } catch (e) {
      if (mounted) _snack('Échec : ${_msg(e)}', secondes: 6);
    } finally {
      _clearBusy();
    }
  }

  Future<void> _creerClasse() async {
    final groupe = _groupeValide();
    if (groupe == null) return;
    if (pieces.isEmpty) {
      _snack(
          "Ajoute d'abord le colloscope (photos ou PDF, section juste en dessous).");
      return;
    }
    final m = AppModel.instance;
    try {
      _setBusy('Création du code de classe…');
      final api = ApiKhompas(m.serverUrl);
      final code = await api.creerClasse();
      for (var i = 0; i < pieces.length; i++) {
        _setBusy('Envoi du fichier ${i + 1}/${pieces.length}…');
        await api.envoyerPhoto(code, i, pieces[i].bytes, pdf: pieces[i].pdf);
      }
      m.setCodeClasse(code);
      m.setProfil(filiere: m.filiere, groupe: groupe);
      codeCtl.text = code;
      _clearBusy();
      if (!mounted) return;
      await _montrerCode(code);
      _setBusy('Extraction des khôlles de ton groupe… (jusqu\'à 2 min)');
      final result = await api.groupe(code, groupe);
      if (!mounted) return;
      _versVerification(result);
    } catch (e) {
      if (mounted) _snack('Échec : ${_msg(e)}', secondes: 6);
    } finally {
      _clearBusy();
    }
  }

  Future<void> _montrerCode(String code) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Code de ta classe 🎉'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: SelectableText(
                code,
                style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Partage-le à ta classe (groupe WhatsApp, Discord…) : chacun '
              'entre ce code et son numéro de groupe, et reçoit ses khôlles — '
              'sans photo, sans clé, gratuitement. Le code reste enregistré '
              'dans ton profil.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
            },
            child: const Text('Copier le code'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
  }

  // ---------- Chemin 2 : extraction directe (cle API perso) ----------

  Future<void> _lancer() async {
    final m = AppModel.instance;
    if (m.apiKey.isEmpty) {
      _snack(
          "Pas de clé API ? Utilise le code de classe ou l'import copier-coller.");
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
      return;
    }
    final groupe = _groupeValide();
    if (groupe == null || pieces.isEmpty) return;

    _setBusy('Analyse du colloscope en cours…');
    try {
      m.setProfil(filiere: m.filiere, groupe: groupe);
      final result = await extraireColloscope(
        apiKey: m.apiKey,
        pieces: pieces,
        groupe: groupe,
      );
      if (!mounted) return;
      _versVerification(result);
    } catch (e) {
      if (mounted) _snack('Échec : ${_msg(e)}', secondes: 6);
    } finally {
      _clearBusy();
    }
  }

  // ---------- Chemin 3 : copier-coller avec son IA (gratuit) ----------

  Future<void> _copierPrompt() async {
    final groupe = _groupeValide();
    if (groupe == null) return;
    final m = AppModel.instance;
    m.setProfil(filiere: m.filiere, groupe: groupe);
    await Clipboard.setData(ClipboardData(text: buildPromptColloscope(groupe)));
    if (!mounted) return;
    _snack(
        'Prompt copié ✅ Ouvre ChatGPT, Claude ou Gemini : joins la ou les photos du colloscope, colle le prompt, puis copie TOUTE sa réponse et reviens appuyer sur « Coller la réponse ».',
        secondes: 7);
  }

  Future<void> _collerReponse() async {
    // Pre-remplit avec le presse-papiers si on y trouve du JSON probable.
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final clipText = clip?.text ?? '';
    final ctl =
        TextEditingController(text: clipText.contains('{') ? clipText : '');
    if (!mounted) return;
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Réponse de l'IA"),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: ctl,
            maxLines: 10,
            minLines: 5,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Colle ici la réponse complète de ton IA '
                  '(le bloc {"colles": …} avec ses accolades).',
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctl.text),
              child: const Text('Analyser')),
        ],
      ),
    );
    if (raw == null || raw.trim().isEmpty || !mounted) return;
    try {
      final result = parseExtraction(raw);
      if (!mounted) return;
      _versVerification(result);
    } catch (_) {
      if (mounted) {
        _snack(
            "Réponse illisible — copie bien TOUTE la réponse de l'IA, accolades comprises, puis réessaie.",
            secondes: 6);
      }
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    final serveurActif = m.serverUrl.isNotEmpty;
    // Avec un serveur configure, l'extraction "cle perso" est redondante :
    // on ne la montre que s'il n'y a pas de serveur (ou si une cle existe).
    final montrerClePerso = !serveurActif || m.apiKey.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Importer mon colloscope')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (busy)
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(busyLabel)),
                  ],
                ),
              ),
            ),
          TextField(
            controller: groupeCtl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Mon numéro de groupe',
              border: OutlineInputBorder(),
            ),
          ),
          if (serveurActif) ...[
            const SizedBox(height: 20),
            Text('Ma classe — avec un code',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Quelqu'un de ta classe a déjà créé un code ? Entre-le : "
                      'tes khôlles arrivent toutes seules — sans photo, sans clé.',
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey.shade800),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: codeCtl,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Code de classe',
                              border: OutlineInputBorder(),
                              hintText: 'ex. K7M2PX',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          icon: const Icon(Icons.download),
                          label: const Text('Récupérer'),
                          onPressed: busy ? null : _viaCode,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Premier de ta classe ? Ajoute les photos ou le PDF du '
                      'colloscope (section suivante) puis :',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.group_add),
                      label: const Text('Créer le code de ma classe'),
                      onPressed: busy ? null : _creerClasse,
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text('Photos ou PDF du colloscope',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Photo'),
                  onPressed: busy ? null : () => _pick(ImageSource.camera),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Galerie'),
                  onPressed: busy ? null : () => _pick(ImageSource.gallery),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('PDF'),
                  onPressed: busy ? null : _pickPdf,
                ),
              ),
            ],
          ),
          if (pieces.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: pieces.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: pieces[i].pdf
                          ? Container(
                              height: 110,
                              width: 150,
                              color: Colors.grey.shade200,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.picture_as_pdf,
                                      size: 36, color: Colors.red.shade400),
                                  const SizedBox(height: 6),
                                  const Text('PDF',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12)),
                                ],
                              ),
                            )
                          : Image.memory(pieces[i].bytes,
                              height: 110, width: 150, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: InkWell(
                        onTap: () => setState(() => pieces.removeAt(i)),
                        child: const CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.black54,
                          child:
                              Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Une photo bien à plat, nette et entière (tableau + tableau des semaines + notes du bas) donne les meilleurs résultats.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          if (montrerClePerso) ...[
            const SizedBox(height: 20),
            Text('Extraction directe — avec ta clé API',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.auto_awesome),
              label: const Text("Lancer l'extraction"),
              onPressed: busy || pieces.isEmpty ? null : _lancer,
            ),
            const SizedBox(height: 6),
            Text(
              'Nécessite ta clé API dans Réglages (quelques centimes par import).',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('OU',
                    style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.bold)),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 20),
          Text('Gratuit — avec ton IA à toi',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Tu as déjà ChatGPT, Claude ou Gemini ? Pas besoin de clé :\n'
                '1. Copie le prompt (bouton ci-dessous).\n'
                '2. Dans ton appli d\'IA, joins la ou les photos du colloscope et colle le prompt.\n'
                '3. Copie toute sa réponse, reviens ici et colle-la.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy_all),
            label: const Text('1. Copier le prompt'),
            onPressed: busy ? null : _copierPrompt,
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.content_paste_go),
            label: const Text("2. Coller la réponse de l'IA"),
            onPressed: busy ? null : _collerReponse,
          ),
          const SizedBox(height: 8),
          Text(
            'Les photos restent dans ton appli d\'IA : Khompas n\'a besoin que de la réponse.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
