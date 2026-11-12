// Renders the redesigned screens with the real fonts at phone size and
// writes PNGs to ../.impeccable/review/ for the design review. Not part of
// the normal suite: run with `flutter test test_screenshots`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/l10n/app_localizations.dart';
import 'package:meinimpact/src/app/main_tab_screen.dart';
import 'package:meinimpact/src/app/theme/mi_theme.dart';
import 'package:meinimpact/src/features/feed/domain/interest_weights.dart';
import 'package:meinimpact/src/features/feed/domain/letter_recipients.dart';
import 'package:meinimpact/src/features/feed/domain/mdb.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity_repository.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';
import 'package:meinimpact/src/features/feed/presentation/aktionen_tab.dart';
import 'package:meinimpact/src/features/tracking/domain/action_log.dart';
import 'package:meinimpact/src/features/tracking/domain/impact_news.dart';

const _out = '../.impeccable/review';
final _boundary = GlobalKey();

void main() {
  setUpAll(_loadFonts);

  testWidgets('palettes, dark', (t) => _shootPalettes(t, Brightness.dark));
  testWidgets('palettes, light', (t) => _shootPalettes(t, Brightness.light));

  Future<void> shoot(
    WidgetTester tester,
    String name, {
    Brightness brightness = Brightness.dark,
    double textScale = 1,
    double pixelRatio = 2,
    List<Opportunity>? pool,
    UserProfile profile = const UserProfile(
      lebenslagen: {'eltern', 'oepnv', 'mieter'},
    ),
    List<ActionLogEntry> doneActions = const [],
    ImpactNewsFeed news = const ImpactNewsFeed(),
    Future<void> Function(WidgetTester tester)? act,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 141, bottom: 102);
    tester.view.viewPadding = const FakeViewPadding(top: 141, bottom: 102);
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    // flutter_test paints shadows without blur by default; the device does
    // not. The binding checks the flag is back on when the test ends.
    debugDisableShadows = false;

    await tester.pumpWidget(
      RepaintBoundary(
        key: _boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: legacyTheme(),
          home: MainTabScreen(
            opportunityRepository: _Pool(pool ?? _opportunities(), news),
            profile: profile,
            doneActions: doneActions,
            onActionDone: (_, __) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (act != null) {
      await act(tester);
      await tester.pumpAndSettle();
    }
    await tester.runAsync(() async {
      final boundary = _boundary.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_out/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
    debugDisableShadows = true;
  }

  testWidgets('hand, dark', (t) => shoot(t, 'phone-hand-dark'));
  testWidgets(
    'hand, light',
    (t) => shoot(t, 'phone-hand-light', brightness: Brightness.light),
  );
  testWidgets(
    'card back, dark',
    (t) => shoot(
      t,
      'phone-back-dark',
      act: (t) => t.tap(find.textContaining('Blitzer')),
    ),
  );
  testWidgets(
    'longest title, dark',
    (t) => shoot(
      t,
      'phone-long-title-dark',
      act: (t) async {
        // Swipe through to the fourth card, the council decision.
        for (var i = 0; i < 3; i++) {
          await t.flingFrom(const Offset(195, 300), const Offset(-200, 0), 800);
          await t.pumpAndSettle();
        }
      },
    ),
  );
  testWidgets(
    'all actions, dark',
    (t) => shoot(
      t,
      'phone-all-dark',
      act: (t) => t.tap(find.text('Alle 7 ansehen')),
    ),
  );
  testWidgets(
    'all actions, light',
    (t) => shoot(
      t,
      'phone-all-light',
      brightness: Brightness.light,
      act: (t) => t.tap(find.text('Alle 7 ansehen')),
    ),
  );
  testWidgets(
    'empty, dark',
    (t) => shoot(t, 'phone-empty-dark', pool: const []),
  );
  testWidgets(
    'font scale 1.3, dark',
    (t) => shoot(t, 'phone-hand-scale130-dark', textScale: 1.3),
  );

  // The pitch set: dark phones on light slides, at full phone resolution.
  Future<void> pitch(
    WidgetTester tester,
    String name, {
    Future<void> Function(WidgetTester tester)? act,
  }) =>
      shoot(
        tester,
        'pitch-$name',
        pixelRatio: 3,
        profile: _pitchProfile,
        doneActions: _pitchDone(),
        news: _pitchNews(),
        act: act,
      );

  testWidgets('pitch 1, hand', (t) => pitch(t, '1-hand'));
  testWidgets(
    'pitch 2, card back',
    (t) => pitch(t, '2-back', act: (t) => t.tap(find.textContaining('Blitzer'))),
  );
  testWidgets(
    'pitch 3, impact',
    (t) => pitch(
      t,
      '3-impact',
      act: (t) async {
        await t.tap(find.text('Mein Impact'));
        await t.pumpAndSettle();
        await t.tap(find.byTooltip('Folgen').first);
      },
    ),
  );
  testWidgets(
    'pitch 4, profile',
    (t) => pitch(t, '4-profile', act: (t) => t.tap(find.text('Mein Profil'))),
  );
}

const _pitchProfile = UserProfile(
  werte: {
    'wirtschaft_gleichheit': 1,
    'wirtschaft_staat': 0,
    'diplomatie_nation': -1,
    'diplomatie_welt': 2,
    'freiheit_staat': 1,
    'freiheit_sicherheit': 0,
    'wandel_tradition': -1,
    'wandel_zukunft': 1,
  },
  lebenslagen: {'eltern', 'oepnv', 'mieter'},
  interests: InterestWeights(
    manual: {
      'Mobilität/Verkehr': InterestLevel.more,
      'Familie/Kinder': InterestLevel.more,
    },
  ),
);

// Real actions and the reports the news dry run of 2026-11-11 judged
// relevant to them (backend/scripts/dryrun_output), oldest first.
List<ActionLogEntry> _pitchDone() => [
      ActionLogEntry(
        opportunityId: 'gewalt-kinder',
        doneAt: _in(-9),
        via: ActionVia.inAppBrowser,
        title: 'Aktionsplan gegen Gewalt an Kindern!',
        kind: OpportunityKind.petition,
        sourceOrg: 'WeAct',
        sourceUrl: 'https://weact.campact.de/petitions/'
            'aktionsplan-gegen-gewalt-an-kindern-jetzt',
        affectedTags: const ['Familie/Kinder'],
      ),
      ActionLogEntry(
        opportunityId: 'hilfsmittel',
        doneAt: _in(-5),
        via: ActionVia.inAppBrowser,
        title: 'Alarmstufe Rot: Individuelle Hilfsmittelversorgung sichern – '
            '3%-Pauschalabschlag streichen!',
        kind: OpportunityKind.petition,
        sourceOrg: 'openPetition',
        sourceUrl: 'https://www.openpetition.de/petition/online/'
            'alarmstufe-rot-individuelle-hilfsmittelversorgung-sichern-3-'
            'pauschalabschlag-streichen',
        affectedTags: const ['Gesundheit/Pflege'],
      ),
      ActionLogEntry(
        opportunityId: 'emissionshandel',
        doneAt: _in(-2),
        via: ActionVia.inAppBrowser,
        title: 'EU-Emissionshandelssystem (See- und Luftverkehr sowie '
            'ortsfeste Anlagen) und Marktstabilitätsreserve – Überprüfung',
        kind: OpportunityKind.consultation,
        sourceOrg: 'Europäische Kommission',
        sourceUrl: 'https://ec.europa.eu/info/law/better-regulation/'
            'have-your-say/initiatives/14549_de',
        affectedTags: const ['Umwelt/Natur', 'Mobilität/Verkehr'],
      ),
    ];

ImpactNewsFeed _pitchNews() => ImpactNewsFeed({
      'emissionshandel': ImpactNewsEntry(
        checkedAt: _now,
        items: [
          ImpactNewsItem(
            level: 'exact',
            kind: 'news',
            title: 'Merz hält am EU-Emissionshandel fest, Kommission will '
                'Luftverkehr 2029 einbeziehen',
            url: 'https://www.airliners.de/merz-haelt-eu-emissionshandel-fest-'
                'kommission-will-luftverkehr-2029-einbeziehen/91455',
            snippet: 'Kanzler Merz bekennt sich zum EU-Emissionshandel. Die '
                'Kommission will das ETS ab 2029 auf Flüge zu den '
                'Golf-Drehkreuzen und nach Istanbul ausweiten.',
            publishedOn: DateTime(2026, 11, 11),
          ),
          ImpactNewsItem(
            level: 'exact',
            kind: 'news',
            title: 'ICAO-Ratsvorsitzender kritisiert EU-Pläne für '
                'Airline-Emissionshandel',
            url: 'https://www.dvz.de/politik/detail/news/icao-ratsvorsitzender-'
                'kritisiert-eu-plaene-fuer-airline-emissionshandel.html',
            snippet: 'Die EU-Kommission spürt internationalen Gegenwind für '
                'ihren Vorschlag, den Luftverkehr-Emissionshandel über '
                'Europas Grenzen hinaus auszudehnen.',
            publishedOn: DateTime(2026, 10, 19),
          ),
          ImpactNewsItem(
            level: 'exact',
            kind: 'news',
            title: 'Airlines gegen EU-Pläne für erweiterten CO2-Emissionshandel',
            url: 'https://www.news.at/ausflugsziele/airlines-gegen-eu-plane-'
                'fur-erweiterten-co2-emissionshandel',
            snippet: 'Die EU-Kommission hat vorgeschlagen, den Emissionshandel '
                'auf Flüge aus der EU in andere Regionen auszuweiten.',
            publishedOn: DateTime(2026, 10, 8),
          ),
        ],
      ),
      'hilfsmittel': ImpactNewsEntry(
        checkedAt: _now,
        items: [
          ImpactNewsItem(
            level: 'issue',
            kind: 'statement',
            title: 'GKV-BStabG zerstört die Hilfsmittelversorgungsstrukturen '
                'in Deutschland',
            url: 'https://www.ord.de/unternehmen/beitraege/gkv-bstabg-'
                'zerstoert-die-hilfsmittelversorgungsstrukturen-in-deutschland',
            snippet: 'Der Hilfsmittelbereich gehört nicht zu den '
                'Kostentreibern der gesetzlichen Krankenversicherungen!',
            publishedOn: DateTime(2026, 6, 3),
          ),
          ImpactNewsItem(
            level: 'exact',
            kind: 'news',
            title: 'Korrekturgesetz: Die Koalition ändert das Sparpaket',
            url: 'https://www.aok.de/pp/gg/gesundheitssystem/'
                'korrekturgesetz-sparpaket',
            snippet: 'Im Bereich der Hilfsmittelversorgung hat die '
                'schwarz-rote Koalition einen pauschalen Abschlag auf alle '
                'vertraglich vereinbarten Preise für Hilfsmittel eingeführt.',
            publishedOn: DateTime(2026, 6, 10),
          ),
        ],
      ),
      'gewalt-kinder': ImpactNewsEntry(
        checkedAt: _now,
        items: [
          ImpactNewsItem(
            level: 'exact',
            kind: 'social',
            title: 'Gewalt an Kindern: Wo bleibt der Aufschrei?',
            url: 'https://www.campact.de/blog/'
                'gewalt-an-kindern-weact-petition-statistik',
            snippet: '',
            publishedOn: DateTime(2026, 10, 2),
          ),
        ],
      ),
    });

// Palette alternatives, rendered side by side on the same hand. Each keeps
// ink text readable on its four faces.
final _palettes = <String, (Color table, Color stock, List<Color> faces)>{
  'A  Jetzt': (
    const Color(0xFF101820),
    const Color(0xFFF4F1EA),
    const [
      Color(0xFFFF5A5F),
      Color(0xFF2EC4B6),
      Color(0xFFFFBF3C),
      Color(0xFF8C84FF),
    ],
  ),
  'B  Riso': (
    const Color(0xFF0E0E10),
    const Color(0xFFFFFFFF),
    const [
      Color(0xFFFF6FC4),
      Color(0xFF4FA8FF),
      Color(0xFFFFE600),
      Color(0xFF2FD88A),
    ],
  ),
  'C  Primär': (
    const Color(0xFF1A1A1A),
    const Color(0xFFF2EFE8),
    const [
      Color(0xFFF25C4B),
      Color(0xFF6C9BFF),
      Color(0xFFF6C21C),
      Color(0xFF57D9A3),
    ],
  ),
  'D  Pastell': (
    const Color(0xFF1B1F3A),
    const Color(0xFFF7F5F0),
    const [
      Color(0xFFFFB3A7),
      Color(0xFFA7E3D9),
      Color(0xFFFFE29A),
      Color(0xFFC9C2FF),
    ],
  ),
};

Future<void> _shootPalettes(WidgetTester tester, Brightness brightness) async {
  const phone = Size(390, 760);
  // Four phones, a 20dp gap after each, 20dp padding around.
  tester.view.physicalSize =
      Size(phone.width * 4 + 20 * 4 + 40, phone.height + 40) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  debugDisableShadows = false;
  final base = miTheme(brightness);
  final light = brightness == Brightness.light;
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ColoredBox(
          color: const Color(0xFF777777),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                for (final MapEntry(key: name, value: (table, stock, faces))
                    in _palettes.entries) ...[
                  SizedBox.fromSize(
                    size: phone,
                    child: Theme(
                      data: base.copyWith(
                        scaffoldBackgroundColor: table,
                        extensions: [
                          (light ? MiColors.light : MiColors.dark).copyWith(
                            table: light ? null : table,
                            onTable: light ? table : null,
                            onCard: table,
                            cardStock: stock,
                            topics: faces,
                          ),
                        ],
                      ),
                      child: Builder(
                        builder: (context) => Scaffold(
                          backgroundColor: context.mi.table,
                          appBar: AppBar(
                            backgroundColor: context.mi.table,
                            foregroundColor: context.mi.onTable,
                            title: Text(name),
                          ),
                          body: AktionenTab(
                            opportunityRepository: _Pool(_opportunities()),
                            profile: const UserProfile(
                              lebenslagen: {'eltern', 'oepnv', 'mieter'},
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$_out/palettes-${brightness.name}.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
  debugDisableShadows = true;
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> assets) async {
    final loader = FontLoader(family);
    for (final asset in assets) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }

  await load('Unbounded', [
    'assets/fonts/Unbounded-Bold.ttf',
    'assets/fonts/Unbounded-ExtraBold.ttf',
  ]);
  await load('AlbertSans', [
    'assets/fonts/AlbertSans-Medium.ttf',
    'assets/fonts/AlbertSans-SemiBold.ttf',
    'assets/fonts/AlbertSans-Bold.ttf',
    'assets/fonts/AlbertSans-ExtraBold.ttf',
  ]);
  // The legacy tabs and system widgets fall back to Roboto.
  final root = Platform.environment['FLUTTER_ROOT']!;
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
          .readAsBytes()
          .then((b) => ByteData.sublistView(b)),
    );
  await icons.load();
}

final _now = DateTime.now();
DateTime _in(int days) => DateTime(_now.year, _now.month, _now.day + days);

List<Opportunity> _opportunities() => [
      _o(
        'kita',
        kind: OpportunityKind.petition,
        source: 'openPetition',
        title: 'Sollen Blitzer vor Kitas und Schulen kommen?',
        summary: 'Eine Petition fordert feste Blitzer vor allen Dresdner '
            'Kitas und Grundschulen, damit Autos dort Tempo 30 einhalten.',
        tags: ['Familie/Kinder', 'Sicherheit'],
        snippets: {
          'hat_kinder:true':
              'Dein Kind ist auf dem Schulweg sicherer, wenn Autos dort '
                  'langsamer fahren.',
        },
        closes: 12,
        support: 1840,
        goal: 2500,
        pro: ['Weniger Unfälle auf Schulwegen', 'Tempo 30 wird ernst genommen'],
        contra: ['Kosten für Anschaffung und Betrieb', 'Gilt als Abzocke'],
      ),
      _o(
        'bahnhof',
        kind: OpportunityKind.publicDisplay,
        source: 'Beteiligungsportal Sachsen',
        title: 'Wie wird der Alte Leipziger Bahnhof in Neustadt bebaut?',
        summary: 'Die Stadt legt den Bebauungsplan für das Gelände am Alten '
            'Leipziger Bahnhof aus. Bis zum Ende der Frist kann jede:r '
            'Hinweise geben.',
        tags: ['Stadtentwicklung/Bauen', 'Mobilität/Verkehr'],
        snippets: {
          'oepnv_nutzung:true':
              'Du fährst Bus und Bahn – auf dem Gelände ist eine neue '
                  'Haltestelle geplant.',
        },
        closes: 3,
        lebenslagen: ['oepnv'],
      ),
      _o(
        'wohngeld',
        kind: OpportunityKind.consultation,
        source: 'Beteiligungsportal Sachsen',
        title: 'Drohen Kürzungen beim Wohngeld?',
        summary: 'Das Land fragt, wie die Wohngeldstellen künftig arbeiten '
            'sollen und wo gespart werden kann.',
        tags: ['Wohnen/Miete'],
        snippets: {
          'wohnsituation:mieter':
              'Als Mieter:in kann sich ändern, wie viel Wohngeld du '
                  'bekommst.',
        },
        closes: 24,
      ),
      _o(
        'gruna',
        kind: OpportunityKind.decision,
        source: 'Ratsinformationssystem Dresden',
        title: 'Sollen die Parkplätze am Ärztehaus und der Apotheke in '
            'Dresden-Gruna erhalten oder neu eingerichtet werden?',
        summary: 'Der Ortsbeirat Blasewitz entscheidet, ob die Stellplätze '
            'vor dem Ärztehaus bleiben.',
        tags: ['Mobilität/Verkehr', 'Gesundheit/Pflege'],
        closes: 6,
        lebenslagen: ['oepnv'],
      ),
      _o(
        'mecfs',
        kind: OpportunityKind.petition,
        source: 'WeAct',
        title: 'Bekommen ME/CFS-Betroffene genug Hilfe?',
        summary: 'Eine Petition fordert mehr Forschung und Versorgung für '
            'Menschen mit ME/CFS.',
        tags: ['Gesundheit/Pflege'],
        closes: 40,
        support: 52310,
      ),
      _o(
        'opensource',
        kind: OpportunityKind.survey,
        source: 'EU-Kommission: Ihre Meinung zählt',
        title: 'Soll Open-Source-Arbeit als Ehrenamt gelten?',
        summary: 'Die EU fragt, wie freiwillige Arbeit an offener Software '
            'anerkannt werden soll.',
        tags: ['Digitales/Datenschutz'],
        announced: true,
        opens: 20,
      ),
      _o(
        'pflege',
        kind: OpportunityKind.consultation,
        source: 'EU-Kommission: Ihre Meinung zählt',
        title: 'Darf die Pflege für Angehörige teurer werden?',
        summary: 'Die EU-Kommission sammelt Meinungen zur Finanzierung der '
            'Langzeitpflege.',
        tags: ['Rente/Alter'],
        closes: 31,
      ),
    ];

Opportunity _o(
  String id, {
  required OpportunityKind kind,
  required String source,
  required String title,
  required String summary,
  required List<String> tags,
  Map<String, String> snippets = const {},
  List<String> lebenslagen = const [],
  List<String> pro = const [],
  List<String> contra = const [],
  int? closes,
  int? opens,
  int? support,
  int? goal,
  bool announced = false,
}) =>
    Opportunity(
      id: id,
      sourceOrg: source,
      sourceUrl: 'https://example.org/$id',
      kind: kind,
      isAnnounced: announced,
      region: 'dresden',
      title: title,
      summary: summary,
      affectedTags: tags,
      lebenslagen: lebenslagen,
      werteRelevanz: const {},
      proArgumente: pro,
      contraArgumente: contra,
      personalImpactSnippets: snippets,
      opensOn: opens == null ? null : _in(opens),
      closesOn: closes == null ? null : _in(closes),
      supportCount: support,
      supportGoal: goal,
      everydayRelevance: 4,
      accessibility: 4,
      firstSeenAt: _in(-2),
    );

class _Pool implements OpportunityRepository {
  _Pool(this.items, [this.news = const ImpactNewsFeed()]);

  final List<Opportunity> items;
  final ImpactNewsFeed news;

  @override
  Future<List<Opportunity>> pool() async => items;

  @override
  Future<List<MdbOption>> lookupMdb(String plz) async => const [];

  @override
  Stream<String> streamLetter(String opportunityId, {String? notes}) =>
      const Stream.empty();

  @override
  Future<LetterRecipients> letterRecipients(String opportunityId) async =>
      const LetterRecipients();

  @override
  Future<void> markTracked(String opportunityId) async {}

  @override
  Future<ImpactNewsFeed> impactNews() async => news;
}
