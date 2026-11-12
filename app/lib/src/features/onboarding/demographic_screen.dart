import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/mi_theme.dart';
import '../feed/domain/mdb.dart';
import '../feed/domain/user_profile.dart';
import '../feed/presentation/widgets/lebenslagen_picker.dart';

/// PLZ/MdB lookup plus the Lebenslagen picker (what matters to the user).
/// Everything is optional and starts empty, matching the "skipping degrades
/// personalisation but never blocks usage" principle.
class DemographicScreen extends StatefulWidget {
  const DemographicScreen({
    required this.onComplete,
    required this.onLookupMdb,
    super.key,
  });

  final void Function(UserProfile? demographicPatch) onComplete;
  final Future<List<MdbOption>> Function(String plz) onLookupMdb;

  @override
  State<DemographicScreen> createState() => _DemographicScreenState();
}

enum _LookupState { idle, loading, done, error, notFound }

class _DemographicScreenState extends State<DemographicScreen> {
  final _plzController = TextEditingController();
  _LookupState _state = _LookupState.idle;
  List<MdbOption> _results = const [];
  MdbOption? _selected;

  Set<String> _lebenslagen = const {};

  @override
  void initState() {
    super.initState();
    _plzController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _plzController.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final plz = _plzController.text.trim();
    if (plz.length != 5) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _state = _LookupState.loading;
      _results = const [];
      _selected = null;
    });
    try {
      final results = await widget.onLookupMdb(plz);
      if (!mounted) return;
      if (results.isEmpty) {
        setState(() => _state = _LookupState.notFound);
        return;
      }
      setState(() {
        _results = results;
        _selected = results.first;
        _state = _LookupState.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _LookupState.error;
      });
    }
  }

  void _confirm() {
    final sel = _selected;
    final plz = _plzController.text.trim();
    widget.onComplete(
      UserProfile(
        plz: sel != null ? plz : null,
        mdbName: sel?.mdbName,
        mdbParty: sel?.mdbParty,
        mdbWahlkreis: sel?.wahlkreisName,
        lebenslagen: _lebenslagen,
      ),
    );
  }

  void _skip() => widget.onComplete(null);

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: colors.table,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MiSpace.lg,
                MiSpace.base,
                MiSpace.sm,
                0,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: MiSpace.sm),
                      child: Text('Über dich', style: text.headlineMedium),
                    ),
                  ),
                  TextButton(
                    onPressed: _skip,
                    style: TextButton.styleFrom(
                      foregroundColor: colors.onTableMuted,
                    ),
                    child: const Text('Überspringen'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  MiSpace.lg,
                  MiSpace.sm,
                  MiSpace.lg,
                  MiSpace.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Hilft uns, dir relevantere Themen zu zeigen. '
                      'Bleibt auf deinem Gerät, alles optional.',
                      style: text.bodyMedium?.copyWith(
                        color: colors.onTableMuted,
                      ),
                    ),
                    const SizedBox(height: MiSpace.xl),
                    _PlzSection(
                      controller: _plzController,
                      state: _state,
                      results: _results,
                      selected: _selected,
                      onLookup: _lookup,
                      onSelect: (opt) => setState(() => _selected = opt),
                      onChanged: () {
                        if (_state != _LookupState.idle) {
                          setState(() {
                            _state = _LookupState.idle;
                            _results = const [];
                            _selected = null;
                          });
                        }
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: MiSpace.lg),
                      child: Divider(height: 1, color: colors.keyline),
                    ),
                    LebenslagenPicker(
                      selected: _lebenslagen,
                      onChanged: (ids) => setState(() => _lebenslagen = ids),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MiSpace.lg,
                MiSpace.sm,
                MiSpace.lg,
                MiSpace.base,
              ),
              child: FilledButton(
                onPressed: _confirm,
                style: colors.tableButton,
                child: const Text('Fertig'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlzSection extends StatelessWidget {
  const _PlzSection({
    required this.controller,
    required this.state,
    required this.results,
    required this.selected,
    required this.onLookup,
    required this.onSelect,
    required this.onChanged,
  });

  final TextEditingController controller;
  final _LookupState state;
  final List<MdbOption> results;
  final MdbOption? selected;
  final VoidCallback onLookup;
  final void Function(MdbOption?) onSelect;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final pill = OutlineInputBorder(
      borderRadius: BorderRadius.circular(MiRadius.chip),
      borderSide: BorderSide(color: colors.keyline),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Dein Abgeordneter', style: text.titleLarge),
        const SizedBox(height: MiSpace.sm),
        Text(
          'Für persönliche Briefe an deine Vertretung im Bundestag.',
          style: text.bodyMedium?.copyWith(color: colors.onTableMuted),
        ),
        const SizedBox(height: MiSpace.base),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                maxLength: 5,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: text.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'Postleitzahl, z. B. 01067',
                  counterText: '',
                  prefixIcon: Icon(
                    Icons.place_outlined,
                    color: colors.onTableMuted,
                  ),
                  border: pill,
                  enabledBorder: pill,
                  focusedBorder: pill.copyWith(
                    borderSide: BorderSide(
                      color: colors.onTableMuted,
                      width: 1.5,
                    ),
                  ),
                ),
                onChanged: (_) => onChanged(),
                onSubmitted: (_) => onLookup(),
              ),
            ),
            const SizedBox(width: MiSpace.sm),
            FilledButton(
              onPressed:
                  controller.text.length == 5 && state != _LookupState.loading
                      ? onLookup
                      : null,
              style: colors.tableButton.copyWith(
                minimumSize: const WidgetStatePropertyAll(Size(96, 52)),
              ),
              child: state == _LookupState.loading
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onTableMuted,
                      ),
                    )
                  : const Text('Suchen'),
            ),
          ],
        ),
        _buildResult(context),
      ],
    );
  }

  Widget _buildResult(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    switch (state) {
      case _LookupState.idle:
      case _LookupState.loading:
        return const SizedBox.shrink();

      case _LookupState.notFound:
        return const _Note('Keine Wahlkreiszuordnung für diese PLZ gefunden.');

      case _LookupState.error:
        return const _Note(
          'Lookup nicht verfügbar. Du kannst diesen Schritt überspringen.',
        );

      case _LookupState.done:
        return Padding(
          padding: const EdgeInsets.only(top: MiSpace.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (results.length > 1) ...[
                Text(
                  'Deine PLZ liegt in mehreren Wahlkreisen. Wähle deinen:',
                  style: text.bodyMedium?.copyWith(color: colors.onTableMuted),
                ),
                const SizedBox(height: MiSpace.md),
                Wrap(
                  spacing: MiSpace.sm,
                  runSpacing: MiSpace.sm,
                  children: [
                    for (final opt in results)
                      _ChoicePill(
                        label: opt.wahlkreisName,
                        selected: opt == selected,
                        onTap: () => onSelect(opt),
                      ),
                  ],
                ),
                const SizedBox(height: MiSpace.base),
              ],
              if (selected != null) _MdbCard(mdb: selected!),
            ],
          ),
        );
    }
  }
}

/// The found member of parliament, as a flat slip of card stock.
class _MdbCard extends StatelessWidget {
  const _MdbCard({required this.mdb});
  final MdbOption mdb;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(MiSpace.base),
      decoration: BoxDecoration(
        color: colors.cardStock,
        borderRadius: BorderRadius.circular(MiRadius.tile),
        border: Border.all(color: colors.keyline),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.onCard,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.how_to_vote_outlined,
              color: colors.cardStock,
              size: 22,
            ),
          ),
          const SizedBox(width: MiSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mdb.mdbName,
                  style: text.titleMedium?.copyWith(color: colors.onCard),
                ),
                const SizedBox(height: 2),
                Text(
                  '${mdb.mdbParty} · ${mdb.wahlkreisName}',
                  style: text.labelMedium?.copyWith(color: colors.onCardMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One Wahlkreis to choose: outlined, or amber with a check when chosen.
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
    final foreground = selected ? colors.onCard : colors.onTable;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(MiRadius.chip),
      side: BorderSide(
        color: selected ? colors.topics[2] : colors.onTableMuted,
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
                    Icon(Icons.check, size: 16, color: foreground),
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
                        color: foreground,
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

/// A muted line with an icon, for lookups that found nothing.
class _Note extends StatelessWidget {
  const _Note(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return Padding(
      padding: const EdgeInsets.only(top: MiSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: colors.onTableMuted),
          const SizedBox(width: MiSpace.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colors.onTableMuted),
            ),
          ),
        ],
      ),
    );
  }
}
