import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../ai_extractor.dart';
import '../store.dart';
import 'settings.dart';
import 'verify.dart';

/// Import du colloscope, deux chemins au choix :
/// - "automatique" : photo(s) -> API Claude (cle perso) -> verification ;
/// - "copier-coller" (gratuit) : on copie le prompt dans SON appli d'IA
///   (ChatGPT, Claude, Gemini...), on colle sa reponse ici -> verification.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final List<Uint8List> images = [];
  late final TextEditingController groupeCtl;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    groupeCtl = TextEditingController(text: AppModel.instance.groupe.toString());
  }

  Future<void> _pick(ImageSource source) async {
    final picker = ImagePicker();
    // On redimensionne des le pick : l'API vision reduit de toute facon les
    // images a ~1568 px de cote long, donc envoyer une photo 12 Mpx ne fait
    // que payer plus cher, uploader plus lentement et risquer la limite de
    // 5 Mo par image. 1600 px suffit pour lire un colloscope net.
    if (source == ImageSource.gallery) {
      final files = await picker.pickMultiImage(
          imageQuality: 88, maxWidth: 1600, maxHeight: 1600);
      for (final f in files) {
        images.add(await f.readAsBytes());
      }
    } else {
      final f = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 88,
          maxWidth: 1600,
          maxHeight: 1600);
      if (f != null) images.add(await f.readAsBytes());
    }
    setState(() {});
  }

  int? _groupeValide() {
    final groupe = int.tryParse(groupeCtl.text.trim());
    if (groupe == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Indique d'abord ton numéro de groupe."),
      ));
    }
    return groupe;
  }

  void _versVerification(ExtractionResult result) {
    if (result.colles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Aucun créneau trouvé pour ce groupe — vérifie la photo et le numéro.'),
      ));
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => VerifyScreen(result: result)),
    );
  }

  // ---------- Chemin 1 : extraction automatique (cle API) ----------

  Future<void> _lancer() async {
    final m = AppModel.instance;
    if (m.apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            "Pas de clé API ? Utilise l'import gratuit par copier-coller, juste en dessous."),
      ));
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
      return;
    }
    final groupe = _groupeValide();
    if (groupe == null || images.isEmpty) return;

    setState(() => busy = true);
    try {
      m.setProfil(filiere: m.filiere, groupe: groupe);
      final result = await extraireColloscope(
        apiKey: m.apiKey,
        images: images,
        groupe: groupe,
      );
      if (!mounted) return;
      _versVerification(result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Échec : $e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // ---------- Chemin 2 : copier-coller avec son IA (gratuit) ----------

  Future<void> _copierPrompt() async {
    final groupe = _groupeValide();
    if (groupe == null) return;
    final m = AppModel.instance;
    m.setProfil(filiere: m.filiere, groupe: groupe);
    await Clipboard.setData(ClipboardData(text: buildPromptColloscope(groupe)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      duration: Duration(seconds: 7),
      content: Text(
          'Prompt copié ✅ Ouvre ChatGPT, Claude ou Gemini : joins la ou les photos du colloscope, colle le prompt, puis copie TOUTE sa réponse et reviens appuyer sur « Coller la réponse ».'),
    ));
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              "Réponse illisible — copie bien TOUTE la réponse de l'IA, accolades comprises, puis réessaie."),
        ));
      }
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Importer mon colloscope')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                '📸 Le point de départ : une photo (ou capture d\'écran) de ton colloscope — le grand tableau des groupes par semaine. '
                'L\'IA repère tes créneaux, calcule les vraies dates (vacances comprises) et applique les règles écrites en bas de page. '
                'Tu vérifies tout avant l\'ajout.',
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: groupeCtl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Mon numéro de groupe',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Text('Automatique — avec ta clé API',
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
            ],
          ),
          if (images.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(images[i],
                          height: 110, width: 150, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: InkWell(
                        onTap: () => setState(() => images.removeAt(i)),
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
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(busy ? 'Analyse en cours…' : "Lancer l'extraction"),
            onPressed: busy || images.isEmpty ? null : _lancer,
          ),
          const SizedBox(height: 6),
          Text(
            'Nécessite ta clé API dans Réglages (quelques centimes par import). '
            'Astuce : une photo bien à plat, nette et entière (tableau + tableau des semaines + notes du bas) donne les meilleurs résultats.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
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
