import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamsterfy/main.dart' as app;
import 'package:hamsterfy/models.dart';
import 'package:hamsterfy/player.dart';
import 'package:hamsterfy/profiles.dart';
import 'package:hamsterfy/search/search_service.dart';
import 'package:hamsterfy/ui/pages.dart';
import 'package:hamsterfy/ui/theme.dart';

class FakePlayer extends ChangeNotifier implements Player {
  @override
  bool get playing => false;
  @override
  bool get loading => false;
  @override
  Track? current;
  @override
  List<Track> queue = [];
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

SearchResults answer(String query, String title) {
  final t = Track(id: 'au:$title', title: title, artist: 'Артист', url: 'https://x/$title');
  return SearchResults(query, [SearchHit(t, SearchSource.audius, Availability.full, 100)], const [], const []);
}

void main() {
  setUpAll(() {
    app.player = FakePlayer();
    app.profiles = Profiles(app.library, app.player);
  });

  testWidgets('a slow answer to an old query never replaces the newer one', (tester) async {
    final pending = <String, Completer<SearchResults>>{};
    final asked = <String>[];
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: CatalogPage(search: (q) {
        asked.add(q);
        return (pending[q] = Completer<SearchResults>()).future;
      }),
    ));

    // The user types "ноч" and pauses: the debounce timer fires a search.
    await tester.enterText(find.byType(TextField), 'ноч');
    await tester.pump(const Duration(milliseconds: 500));
    expect(asked, ['ноч']);

    // Before it answers, the text changes and a second search starts.
    await tester.enterText(find.byType(TextField), 'ночной');
    await tester.pump(const Duration(milliseconds: 500));
    expect(asked, ['ноч', 'ночной']);

    // The NEW request answers first...
    pending['ночной']!.complete(answer('ночной', 'Новый ответ'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Новый ответ'), findsOneWidget);

    // ...and the OLD, slow one arrives afterwards. It must be ignored.
    pending['ноч']!.complete(answer('ноч', 'Старый ответ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Новый ответ'), findsOneWidget);
    expect(find.text('Старый ответ'), findsNothing);
  });

  testWidgets('typing again before the pause ends sends only the final text', (tester) async {
    final asked = <String>[];
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: CatalogPage(search: (q) async {
        asked.add(q);
        return answer(q, 'Ответ на $q');
      }),
    ));
    for (final text in ['н', 'но', 'ноч', 'ночь']) {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump(const Duration(milliseconds: 200)); // shorter than the pause
    }
    expect(asked, isEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    expect(asked, ['ночь']);
    await tester.pump();
    expect(find.text('Ответ на ночь'), findsOneWidget);
  });

  testWidgets('clearing the field while a search is pending shows no stale results', (tester) async {
    final slow = Completer<SearchResults>();
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: CatalogPage(search: (q) => slow.future)));
    await tester.enterText(find.byType(TextField), 'ночь');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    slow.complete(answer('ночь', 'Запоздалый ответ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Запоздалый ответ'), findsNothing);
  });
}
