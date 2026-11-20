import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/mi_theme.dart';
import '../../feed/domain/home_location.dart';
import '../../feed/domain/lebenslage.dart';
import '../../feed/domain/local_coverage.dart';
import '../../feed/domain/lebenslagen_catalog.g.dart';
import '../../feed/domain/lebenslagen_search.dart';
import '../../feed/domain/mdb.dart';
import '../../feed/domain/user_profile.dart';
import 'hanging_tag.dart';
import 'rucksack_bag.dart';

/// The second onboarding step: the Rucksack. "Dein Bild" from the values
/// questionnaire drops in first. Then, asked big, where the user lives
/// (for actions nearby, and to find their members of parliament); the PLZ
/// flies onto the bag as its luggage tag. It is required: the server
/// locates it once and the app keeps only where it lies. Then what belongs
/// to them: one card per area, swiped like the hand, with the Lebenslagen
/// as hanging tags that fly over the bag and drop in. Private ones go into
/// the Privatfach at the front. The Lebenslagen are optional and stay on
/// the device.
class RucksackScreen extends StatefulWidget {
  const RucksackScreen({
    required this.onComplete,
    required this.onLocate,
    this.werte = const {},
    this.dropPicture = true,
    this.initialPlz,
    this.initialWahlkreis,
    this.initialLebenslagen = const {},
    this.onBack,
    super.key,
  });

  /// When re-packing from the profile: the PLZ to start with (looked up
  /// again) and what is already in the bag.
  final String? initialPlz;

  /// The Wahlkreis chosen before, picked again when the PLZ lies in
  /// several.
  final String? initialWahlkreis;
  final Set<String> initialLebenslagen;

  final ValueChanged<UserProfile> onComplete;

  /// Locates a PLZ (see OpportunityRepository.locate); null when unknown.
  final Future<PlzLookup?> Function(String plz) onLocate;

  /// The answers from the questionnaire, for the picture in the bag.
  final Map<String, double> werte;

  /// Drops the picture in when the bag first shows, straight after the
  /// questionnaire; when re-packing it is already in the bag.
  final bool dropPicture;

  /// System Back on the first step; null lets the route pop.
  final VoidCallback? onBack;

  @override
  State<RucksackScreen> createState() => _RucksackScreenState();
}

enum _Step { plz, lebenslagen }

enum _Lookup { idle, loading, done, error, notFound }

class _RucksackScreenState extends State<RucksackScreen>
    with TickerProviderStateMixin {
  final _stackKey = GlobalKey();
  final _bagKey = GlobalKey<RucksackBagState>();
  final _plzFieldKey = GlobalKey();

  _Step _step = _Step.plz;

  final _plz = TextEditingController();
  _Lookup _lookup = _Lookup.idle;
  HomeLocation? _home;
  LocalCoverage _coverage = LocalCoverage.local;
  List<MdbOption> _results = const [];
  MdbOption? _mdb;
  bool _luggageOn = false;

  // In the order packed; a LinkedHashMap.
  final _packed = <String, PackedItem>{};
  final _inFlight = <String>{};
  final _flights = <_Flight>[];

  final _pages = PageController(viewportFraction: 0.86);
  int _page = 0;
  final _berufSearch = TextEditingController();

  late final List<double?>? _answers = () {
    final answers = [for (final k in werteQuestionKeys) widget.werte[k]];
    return answers.every((a) => a == null) ? null : answers;
  }();

  bool _unpacked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // What was packed before lies in the bag from the start.
    if (_unpacked) return;
    _unpacked = true;
    for (final item
        in packedLebenslagen(widget.initialLebenslagen, context.mi.topics)) {
      _packed[item.id] = item;
    }
  }

  @override
  void initState() {
    super.initState();
    final plz = widget.initialPlz;
    if (plz != null && plz.length == 5) {
      _plz.text = plz;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onPlzChanged(plz);
      });
    }
    _berufSearch.addListener(() => setState(() {}));
    _pages.addListener(() {
      final page = _pages.page?.round() ?? 0;
      if (page != _page) setState(() => _page = page);
    });
  }

  @override
  void dispose() {
    _plz.dispose();
    _pages.dispose();
    _berufSearch.dispose();
    for (final f in _flights) {
      f.controller.dispose();
    }
    super.dispose();
  }

  // ── PLZ ──────────────────────────────────────────────────────────────

  String? get _plzValue => _plz.text.length == 5 ? _plz.text : null;

  Future<void> _onPlzChanged(String value) async {
    if (value.length < 5) {
      if (_lookup != _Lookup.idle) {
        setState(() {
          _lookup = _Lookup.idle;
          _home = null;
          _coverage = LocalCoverage.local;
          _results = const [];
          _mdb = null;
        });
      } else {
        setState(() {});
      }
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _lookup = _Lookup.loading;
      _home = null;
      _coverage = LocalCoverage.local;
      _results = const [];
      _mdb = null;
    });
    try {
      final found = await widget.onLocate(value);
      if (!mounted || _plz.text != value) return;
      final results = found?.wahlkreise ?? const <MdbOption>[];
      setState(() {
        _home = found?.home;
        _coverage = found?.coverage ?? LocalCoverage.local;
        _results = results;
        _mdb = results.isEmpty
            ? null
            : results.firstWhere(
                (r) => r.wahlkreisName == widget.initialWahlkreis,
                orElse: () => results.first,
              );
        _lookup = found == null ? _Lookup.notFound : _Lookup.done;
      });
    } catch (_) {
      if (!mounted || _plz.text != value) return;
      setState(() => _lookup = _Lookup.error);
    }
  }

  void _toLebenslagen() {
    FocusScope.of(context).unfocus();
    final plz = _plzValue;
    setState(() => _step = _Step.lebenslagen);
    if (plz == null || _luggageOn) return;
    final from = _globalCentre(_plzFieldKey);
    final to = _bagKey.currentState?.luggagePoint();
    if (MiMotion.reduced(context) || from == null || to == null) {
      setState(() => _luggageOn = true);
      _bagKey.currentState?.bump();
      return;
    }
    final scale = _bagScale;
    _fly(
      from: from,
      to: to,
      startScale: 1.7,
      endScale: scale,
      endTurn: 7,
      centred: true,
      duration: const Duration(milliseconds: 700),
      child: LuggageTag(plz: plz, place: _mdb?.wahlkreisName),
      onLanded: (_, __) {
        setState(() => _luggageOn = true);
        _bagKey.currentState?.bump();
      },
    );
  }

  // ── Packing ──────────────────────────────────────────────────────────

  double _bagScale = 1;

  void _toggle(Lebenslage item, Color color, BuildContext tagContext) {
    if (_inFlight.contains(item.id)) return;
    HapticFeedback.selectionClick();
    if (_packed.containsKey(item.id)) {
      setState(() => _packed.remove(item.id));
      return;
    }
    final taken = {
      for (final p in _packed.values)
        if (p.isPrivate == item.isPrivate) p.slot,
    };
    var slot = 0;
    while (taken.contains(slot)) {
      slot++;
    }
    final packed = PackedItem(
      id: item.id,
      color: color,
      slot: slot,
      isPrivate: item.isPrivate,
    );
    final box = tagContext.findRenderObject() as RenderBox?;
    final to = _bagKey.currentState?.dropPoint(packed);
    if (MiMotion.reduced(context) || box == null || to == null) {
      setState(() => _packed[item.id] = packed);
      return;
    }
    final from = box.localToGlobal(box.size.center(Offset.zero));
    final (size, turn) = RucksackBag.tagOf(packed);
    setState(() => _inFlight.add(item.id));
    _fly(
      from: from,
      to: to,
      startScale: 1,
      endScale: _bagScale,
      endTurn: turn * 0.4,
      centred: false,
      duration: const Duration(milliseconds: 620),
      child: SizedBox.fromSize(
        size: size,
        child: PackedTagTop(
          color: color,
          inner: RucksackBag.innerOf(context),
          small: item.isPrivate,
        ),
      ),
      // The drop into the bag carries on at the speed and pull of the
      // throw, in the bag's own units.
      onLanded: (speed, pull) => setState(() {
        _inFlight.remove(item.id);
        _packed[item.id] = packed.thrown(
          speed: speed / _bagScale,
          pull: pull / _bagScale,
        );
      }),
    );
  }

  Offset? _globalCentre(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  /// Throws [child] from [from] up over the bag and down onto [to] (global
  /// points), so it arrives falling from above. [to] is the child's top
  /// centre, or its centre when [centred]. [onLanded] gets the downward
  /// speed it arrives with and the pull it fell under (logical pixels per
  /// second, and per second squared).
  void _fly({
    required Offset from,
    required Offset to,
    required double startScale,
    required double endScale,
    required double endTurn,
    required bool centred,
    required Duration duration,
    required Widget child,
    required void Function(double speed, double pull) onLanded,
  }) {
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null) return onLanded(0, 0);
    final controller = AnimationController(vsync: this, duration: duration);
    final flight = _Flight(
      controller: controller,
      from: stack.globalToLocal(from),
      to: stack.globalToLocal(to),
      startScale: startScale,
      endScale: endScale,
      endTurn: endTurn,
      centred: centred,
      child: child,
    );
    setState(() => _flights.add(flight));
    controller.forward().then((_) {
      if (!mounted) return;
      final seconds = duration.inMicroseconds / 1e6;
      onLanded(
        (flight.b + 2 * flight.a) / seconds,
        2 * flight.a / (seconds * seconds),
      );
      setState(() => _flights.remove(flight));
      controller.dispose();
    });
  }

  void _done() {
    widget.onComplete(
      UserProfile(
        plz: _plzValue,
        mdbName: _mdb?.mdbName,
        mdbParty: _mdb?.mdbParty,
        mdbWahlkreis: _mdb?.wahlkreisName,
        home: _home,
        lebenslagen: {..._packed.keys},
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final reduced = MiMotion.reduced(context);
    final onPlz = _step == _Step.plz;

    return PopScope(
      canPop: onPlz && widget.onBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (onPlz) {
          widget.onBack?.call();
        } else {
          setState(() => _step = _Step.plz);
        }
      },
      child: Scaffold(
        backgroundColor: colors.table,
        body: SafeArea(
          child: Stack(
            key: _stackKey,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      MiSpace.lg,
                      MiSpace.base,
                      MiSpace.lg,
                      0,
                    ),
                    child: _Switch(
                      reduced: reduced,
                      child: onPlz
                          ? const _Heading(
                              key: ValueKey('plz'),
                              title: 'Wo bist du zuhause?',
                              line: 'Damit du Aktionen in deiner Nähe findest. '
                                  'Wir speichern deine PLZ nicht.',
                            )
                          : const _Heading(
                              key: ValueKey('ll'),
                              title: 'Was gehört zu dir?',
                              line: 'Wähle, was dich betrifft oder dir am '
                                  'Herzen liegt. Alles bleibt auf deinem '
                                  'Gerät.',
                            ),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final stage = (box.maxHeight * 0.36).clamp(
                          140.0,
                          236.0,
                        );
                        _bagScale = (stage - 36) / RucksackBag.sheet.height;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: stage,
                              child: Column(
                                children: [
                                  const SizedBox(height: MiSpace.sm),
                                  RucksackBag(
                                    key: _bagKey,
                                    width: RucksackBag.sheet.width * _bagScale,
                                    items: [..._packed.values],
                                    answers: _answers,
                                    dropPicture: widget.dropPicture,
                                    plz: _luggageOn ? _plzValue : null,
                                    place: _mdb?.wahlkreisName,
                                  ),
                                  const Spacer(),
                                  AnimatedOpacity(
                                    opacity: onPlz ? 0 : 1,
                                    duration: MiMotion.settle,
                                    child: Text(
                                      _count,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: text.labelMedium?.copyWith(
                                        color: colors.onTableMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: _Switch(
                                reduced: reduced,
                                rise: true,
                                child: onPlz
                                    ? KeyedSubtree(
                                        key: const ValueKey('plz'),
                                        child: _plzStep(context),
                                      )
                                    : KeyedSubtree(
                                        key: const ValueKey('ll'),
                                        child: _shelf(context),
                                      ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      MiSpace.lg,
                      MiSpace.sm,
                      MiSpace.lg,
                      MiSpace.base,
                    ),
                    child: onPlz
                        ? FilledButton(
                            // Offline the PLZ still goes in; the app locates
                            // it later. An unknown one does not.
                            onPressed:
                                _plzValue == null || _lookup == _Lookup.notFound
                                    ? null
                                    : _toLebenslagen,
                            style: colors.tableButton,
                            child: const Text('Weiter'),
                          )
                        : FilledButton(
                            onPressed: _inFlight.isEmpty ? _done : null,
                            style: colors.tableButton,
                            child: const Text('Fertig'),
                          ),
                  ),
                ],
              ),
              for (final flight in _flights) _FlightView(flight: flight),
            ],
          ),
        ),
      ),
    );
  }

  String get _count {
    final private = _packed.values.where((p) => p.isPrivate).length;
    final public = _packed.length - private;
    if (_packed.isEmpty) return 'Noch nichts ausgewählt';
    return private == 0
        ? '$public ausgewählt'
        : '$public ausgewählt · $private im Privatfach';
  }

  Widget _plzStep(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final ink = colors.onCard;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        MiSpace.base + 4,
        MiSpace.sm,
        MiSpace.base + 4,
        MiSpace.base,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: _cardDecoration(colors),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Postleitzahl',
                  style: text.labelMedium?.copyWith(color: colors.onCardMuted),
                ),
                const SizedBox(height: MiSpace.sm),
                TextField(
                  key: _plzFieldKey,
                  controller: _plz,
                  keyboardType: TextInputType.number,
                  maxLength: 5,
                  autofillHints: const [AutofillHints.postalCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: _onPlzChanged,
                  cursorColor: ink,
                  style: TextStyle(
                    fontFamily: MiFonts.display,
                    fontWeight: FontWeight.w800,
                    fontSize: 30,
                    letterSpacing: 3.6,
                    color: ink,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '01067',
                    hintStyle: TextStyle(
                      fontFamily: MiFonts.display,
                      fontWeight: FontWeight.w800,
                      fontSize: 30,
                      letterSpacing: 3.6,
                      color: ink.withValues(alpha: 0.18),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFFFFCF8),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: MiSpace.base,
                      vertical: 14,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: ink.withValues(alpha: 0.15),
                        width: 1.5,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide:
                          BorderSide(color: colors.onCardMuted, width: 2),
                    ),
                  ),
                ),
                _found(context),
              ],
            ),
          ),
          const SizedBox(height: MiSpace.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MiSpace.xs),
            child: Text(
              'Mit der PLZ finden wir auch deine Abgeordneten, falls du '
              'ihnen mal schreiben willst.',
              style: text.bodyMedium?.copyWith(
                color: colors.onTableMuted,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _found(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final ink = colors.onCard;
    final muted = text.bodyMedium?.copyWith(color: colors.onCardMuted);
    Widget note(String message) => Padding(
          padding: const EdgeInsets.only(top: MiSpace.md),
          child: Text(message, style: muted),
        );
    switch (_lookup) {
      case _Lookup.idle:
        return const SizedBox.shrink();
      case _Lookup.loading:
        return Padding(
          padding: const EdgeInsets.only(top: MiSpace.md),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.onCardMuted,
                ),
              ),
              const SizedBox(width: MiSpace.md),
              Text('Suche deinen Wahlkreis …', style: muted),
            ],
          ),
        );
      case _Lookup.notFound:
        return note('Diese PLZ kennen wir nicht. Stimmt sie?');
      case _Lookup.error:
        return note('Gerade keine Verbindung. Die PLZ nehmen wir trotzdem '
            'mit.');
      case _Lookup.done:
        final mdb = _mdb;
        return Padding(
          padding: const EdgeInsets.only(top: MiSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_results.length > 1) ...[
                Text('Deine PLZ liegt in mehreren Wahlkreisen:', style: muted),
                const SizedBox(height: MiSpace.sm),
                Wrap(
                  spacing: MiSpace.sm,
                  runSpacing: MiSpace.sm,
                  children: [
                    for (final option in _results)
                      _ChoicePill(
                        label: option.wahlkreisName,
                        selected: option == mdb,
                        onTap: () => setState(() => _mdb = option),
                      ),
                  ],
                ),
                const SizedBox(height: MiSpace.md),
              ],
              if (mdb != null)
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colors.topics[2],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.place_rounded, size: 22, color: ink),
                    ),
                    const SizedBox(width: MiSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            mdb.wahlkreisName,
                            style: text.titleMedium?.copyWith(color: ink),
                          ),
                          Text(
                            'Im Bundestag: ${mdb.mdbName}, ${mdb.mdbParty}',
                            style: muted?.copyWith(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              if (_coverage.note case final coverageNote?)
                Padding(
                  padding: EdgeInsets.only(top: mdb != null ? MiSpace.md : 0),
                  child: Text(coverageNote, style: muted),
                ),
            ],
          ),
        );
    }
  }

  Widget _shelf(BuildContext context) {
    final colors = context.mi;
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pages,
            clipBehavior: Clip.none,
            itemCount: kLebenslageAreas.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.fromLTRB(6, MiSpace.sm, 6, 18),
              child: _areaCard(context, i),
            ),
          ),
        ),
        Semantics(
          label: 'Bereich ${_page + 1} von ${kLebenslageAreas.length}',
          excludeSemantics: true,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < kLebenslageAreas.length; i++)
                AnimatedContainer(
                  duration: MiMotion.quick,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colors.onTable.withValues(
                      alpha: i == _page ? 1 : 0.3,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _areaCard(BuildContext context, int index) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final area = kLebenslageAreas[index];
    final color = colors.topics[index % colors.topics.length];
    final all = kLebenslagen.where((l) => l.area == area).toList();
    final isBeruf = area == 'Beruf';
    final query = isBeruf ? _berufSearch.text.trim() : '';
    final items = query.isEmpty ? all : searchLebenslagen(query, catalog: all);
    final private = all.where((l) => l.isPrivate).length;
    // Only where the heading leaves a real question open.
    final String? note = private == all.length
        ? 'Kommt ins Privatfach: wird nirgends angezeigt, bleibt nur bei dir.'
        : private > 0
            ? 'Die mit dem Fach-Zeichen kommen ins Privatfach und werden '
                'nirgends angezeigt.'
            : isBeruf
                ? 'Dein Arbeitsfeld, auch wenn du gerade nicht darin '
                    'arbeitest.'
                : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 0),
      decoration: _cardDecoration(colors),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            area,
            style: text.titleLarge?.copyWith(
              fontSize: 18,
              letterSpacing: -0.36,
              color: colors.onCard,
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: MiSpace.xs),
            Text(
              note,
              style: text.labelMedium?.copyWith(
                color: colors.onCardMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: MiSpace.md),
          if (isBeruf) ...[
            TextField(
              controller: _berufSearch,
              style: text.bodyLarge?.copyWith(color: colors.onCard),
              cursorColor: colors.onCard,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Beruf suchen',
                hintStyle: text.bodyMedium?.copyWith(
                  color: colors.onCardMuted,
                ),
                prefixIcon: Icon(Icons.search, color: colors.onCardMuted),
                filled: true,
                fillColor: colors.onCard.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(MiRadius.chip),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(MiRadius.chip),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(MiRadius.chip),
                  borderSide: BorderSide(color: colors.onCardMuted),
                ),
              ),
            ),
            const SizedBox(height: MiSpace.sm),
          ],
          Expanded(
            child: SingleChildScrollView(
              clipBehavior: Clip.hardEdge,
              padding: const EdgeInsets.fromLTRB(14, MiSpace.xs, 4, 14),
              child: Wrap(
                spacing: MiSpace.sm + 2,
                runSpacing: MiSpace.xs,
                children: [
                  for (var k = 0; k < items.length; k++)
                    Builder(
                      builder: (tagContext) {
                        final item = items[k];
                        return HangingTag(
                          key: ValueKey(item.id),
                          label: item.label,
                          color: color,
                          isPrivate: item.isPrivate,
                          packed: _packed.containsKey(item.id) ||
                              _inFlight.contains(item.id),
                          tilt: (((k * 7 + index * 3) % 5) - 2) * 0.7,
                          onTap: () => _toggle(item, color, tagContext),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static BoxDecoration _cardDecoration(MiColors colors) => BoxDecoration(
        color: colors.cardStock,
        borderRadius: BorderRadius.circular(MiRadius.card),
        border: Border.all(color: colors.keyline),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      );
}

/// Headline and muted line of a step.
class _Heading extends StatelessWidget {
  const _Heading({required this.title, required this.line, super.key});

  final String title;
  final String line;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: text.headlineMedium),
        const SizedBox(height: MiSpace.sm),
        Text(
          line,
          style: text.bodyMedium?.copyWith(color: colors.onTableMuted),
        ),
      ],
    );
  }
}

/// Crossfades between the two steps; with [rise], the new one comes up
/// from below.
class _Switch extends StatelessWidget {
  const _Switch({
    required this.reduced,
    required this.child,
    this.rise = false,
  });

  final bool reduced;
  final bool rise;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 420),
      switchInCurve: MiMotion.ease,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: Offset(0, rise ? 0.12 : -0.08),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// One Wahlkreis to choose, on card stock: outlined, or amber with a check
/// when chosen.
class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final ink = colors.onCard;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(MiRadius.chip),
      side: BorderSide(
        color: selected ? colors.topics[2] : ink.withValues(alpha: 0.3),
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? colors.topics[2] : Colors.transparent,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MiSpace.base,
                vertical: MiSpace.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[
                    Icon(Icons.check, size: 16, color: ink),
                    const SizedBox(width: MiSpace.sm - 2),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: MiFonts.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        color: ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Something on its way into the bag, thrown: across at an even pace,
/// up and down on a parabola that peaks [_rise] above the higher end, so
/// it comes down onto its target still falling.
class _Flight {
  _Flight({
    required this.controller,
    required this.from,
    required this.to,
    required this.startScale,
    required this.endScale,
    required this.endTurn,
    required this.centred,
    required this.child,
  }) {
    // y(t) = from.dy + b·t + a·t², through both ends, highest at the apex.
    final apex = math.min(from.dy, to.dy) - _rise;
    final d = from.dy - apex;
    final s = math.sqrt(d * (to.dy - apex));
    b = -2 * d - 2 * s;
    a = (s + d) * (s + d) / d;
  }

  static const _rise = 110.0;

  final AnimationController controller;
  final Offset from;
  final Offset to;
  final double startScale;
  final double endScale;
  final double endTurn;
  final bool centred;
  final Widget child;
  late final double a;
  late final double b;

  Offset at(double t) =>
      Offset(lerpDouble(from.dx, to.dx, t)!, from.dy + b * t + a * t * t);
}

class _FlightView extends StatelessWidget {
  const _FlightView({required this.flight});

  final _Flight flight;

  @override
  Widget build(BuildContext context) {
    final f = flight;
    return AnimatedBuilder(
      animation: f.controller,
      builder: (context, child) {
        // Real time: the throw itself makes the slow top and fast fall.
        final t = f.controller.value;
        final p = f.at(t);
        final appear = (t / 0.12).clamp(0.0, 1.0);
        final scale =
            lerpDouble(f.startScale, f.endScale, Curves.easeOut.transform(t))! *
                (0.7 + 0.3 * appear);
        return Positioned(
          left: p.dx,
          top: p.dy,
          child: IgnorePointer(
            child: FractionalTranslation(
              translation: Offset(-0.5, f.centred ? -0.5 : 0),
              child: Transform.scale(
                alignment: f.centred ? Alignment.center : Alignment.topCenter,
                scale: scale,
                child: Transform.rotate(
                  // A tag turns round its foot, as it does in the bag.
                  alignment:
                      f.centred ? Alignment.center : Alignment.bottomCenter,
                  angle: (f.endTurn * t - 16 * math.sin(t * math.pi)) *
                      math.pi /
                      180,
                  child: Opacity(opacity: appear, child: child),
                ),
              ),
            ),
          ),
        );
      },
      child: f.child,
    );
  }
}
