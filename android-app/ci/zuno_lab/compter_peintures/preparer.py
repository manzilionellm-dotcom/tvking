"""Ajouter deux compteurs de peinture à une copie d'un arbre Flutter épinglé."""
from pathlib import Path
import sys

root, variant = Path(sys.argv[1]), sys.argv[2]
if variant not in ('actuel','anneau-isole'):
    raise ValueError(variant)
player = root/'lib/features/tv/presentation/tv_player_screen.dart'
s = player.read_text(); s = "import 'package:flutter/rendering.dart';\n" + s
start = s.index('Widget _loadingCard()'); end = s.index('Widget ',start+19)
panel = s[start:end]

def wrap(block, expression, name, isolate=False):
    i=block.index(expression); j=i+len(expression); depth=1
    while depth:
        token=block[j]; depth+=int(token=='(')-int(token==')');j+=1
    original=block[i:j]
    probe="ZunoPaintProbe('"+name+"', "+original+")"
    if isolate: probe='RepaintBoundary(child: '+probe+')'
    return block[:i]+probe+block[j:]

title='Text(\n                c.cleanName,'
assert panel.count(title)==1 and panel.count('CircularProgressIndicator(')==1
panel=wrap(panel,title,'titre')
panel=wrap(panel,'CircularProgressIndicator(','anneau',variant=='anneau-isole')
s=s[:start]+panel+s[end:]+'''
class ZunoPaintProbe extends SingleChildRenderObjectWidget {
  const ZunoPaintProbe(this.identifiant, Widget child) : super(child: child);
  final String identifiant;
  static final counts = <String,int>{};
  @override
  RenderObject createRenderObject(BuildContext context) => _ZunoPaintRender(identifiant);
}
class _ZunoPaintRender extends RenderProxyBox {
  _ZunoPaintRender(this.identifiant);
  final String identifiant;
  @override
  void paint(PaintingContext context, Offset offset) {
    ZunoPaintProbe.counts.update(identifiant, (n) => n + 1, ifAbsent: () => 1);
    super.paint(context, offset);
  }
}
''';player.write_text(s)
# Réutiliser l'initialisation de ZUNO, SQLite et des listes propres à cette révision.
p=root/'test/features/tv/zuno_tv_variant_focus_test.dart';t=p.read_text();i=t.index('  testWidgets(')
if "import 'dart:io';" not in t[:i]:t="import 'dart:io';\n"+t;i=t.index('  testWidgets(')
t=t[:i]+'''  testWidgets('compter les peintures du titre ZUNO', (tester) async {
    try {
      await show(tester, TvPlayerScreen(channels: PlaylistRepository.instance.currentChannels, startIndex: 0));
      // Une taille et une animation réelles sont requises pour qualifier la fenêtre.
      final spinner = find.byType(CircularProgressIndicator);
      expect(spinner, findsOneWidget);
      expect(tester.getSize(spinner).shortestSide, greaterThan(0));
      expect(ZunoPaintProbe.counts['titre'], greaterThan(0));
      ZunoPaintProbe.counts.clear();
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final title=ZunoPaintProbe.counts['titre'] ?? 0;
      final ring=ZunoPaintProbe.counts['anneau'] ?? 0;
      expect(ring, greaterThan(0));
      print('ZUNO_PEINTURES pas=120 titre=$title anneau=$ring');
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
''' + t[i:];p.write_text(t)
