// Ce fichier DOIT exister dans le depot : sinon, le `flutter create .` des
// workflows CI genere le widget_test par defaut (app compteur "MyApp") qui
// ne compile pas ici et casse `flutter test`.
import 'package:flutter_test/flutter_test.dart';
import 'package:khompas/main.dart';

void main() {
  testWidgets('l\'app démarre sans planter', (tester) async {
    await tester.pumpWidget(const KhompasApp());
    await tester.pump();
    // Avant le chargement des donnees, l'aiguillage affiche le spinner.
    expect(find.byType(KhompasApp), findsOneWidget);
  });
}
