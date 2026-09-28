import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../feed/domain/betroffenheitsprofil.dart';
import '../feed/domain/mdb.dart';
import '../feed/domain/user_profile.dart';
import '../feed/presentation/widgets/app_colors.dart';
import '../feed/presentation/widgets/betroffenheitsprofil_editor.dart';
import '../feed/presentation/widgets/components/surface_card.dart';

/// PLZ/MdB lookup (unchanged) plus the real Betroffenheitsprofil — replaces
/// the hardcoded demo persona that used to seed every profile
/// (city/occupation/familyStatus/wohnsituation/sektor/lebenssituation, see
/// git history). All Betroffenheitsprofil fields are optional and default
/// to "not set", matching the "skipping degrades personalisation but never
/// blocks usage" principle.
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

  Wohnsituation? _wohnsituation;
  bool _oepnvNutzung = false;
  bool _autoNutzung = false;
  bool _hatKinder = false;
  Erwerbsstatus? _erwerbsstatus;
  bool _pflegeBetroffen = false;
  bool? _migrationshintergrund;

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

  Betroffenheitsprofil get _betroffenheitsprofil => Betroffenheitsprofil(
        wohnsituation: _wohnsituation,
        oepnvNutzung: _oepnvNutzung,
        autoNutzung: _autoNutzung,
        hatKinder: _hatKinder,
        erwerbsstatus: _erwerbsstatus,
        pflegeBetroffen: _pflegeBetroffen,
        migrationshintergrund: _migrationshintergrund,
      );

  void _confirm() {
    final sel = _selected;
    final plz = _plzController.text.trim();
    widget.onComplete(
      UserProfile(
        plz: sel != null ? plz : null,
        mdbName: sel?.mdbName,
        mdbParty: sel?.mdbParty,
        mdbWahlkreis: sel?.wahlkreisName,
        betroffenheitsprofil: _betroffenheitsprofil,
      ),
    );
  }

  void _skip() => widget.onComplete(null);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Über dich',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.4,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Hilft uns, dir relevantere Themen zu zeigen. '
                          'Bleibt auf deinem Gerät, alles optional.',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.mutedText,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _skip,
                    child: Text(
                      'Überspringen',
                      style:
                          TextStyle(color: AppColors.mutedText, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                      const SizedBox(height: 28),
                      BetroffenheitsprofilEditor(
                        value: _betroffenheitsprofil,
                        onChanged: (bp) => setState(() {
                          _wohnsituation = bp.wohnsituation;
                          _oepnvNutzung = bp.oepnvNutzung;
                          _autoNutzung = bp.autoNutzung;
                          _hatKinder = bp.hatKinder;
                          _erwerbsstatus = bp.erwerbsstatus;
                          _pflegeBetroffen = bp.pflegeBetroffen;
                          _migrationshintergrund = bp.migrationshintergrund;
                        }),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Fertig',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Dein Abgeordneter',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Für persönliche Briefe an deine Vertretung im Bundestag.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.mutedText),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                maxLength: 5,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Postleitzahl',
                  hintText: '10115',
                  counterText: '',
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.subtleBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.subtleBorder),
                  ),
                ),
                onChanged: (_) => onChanged(),
                onSubmitted: (_) => onLookup(),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: controller.text.length == 5 ? onLookup : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.subtleBorder,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: state == _LookupState.loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Suchen',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildResult(context),
      ],
    );
  }

  Widget _buildResult(BuildContext context) {
    switch (state) {
      case _LookupState.idle:
      case _LookupState.loading:
        return const SizedBox.shrink();

      case _LookupState.notFound:
        return _InfoBox(
          color: AppColors.warmSurface,
          child: Text(
            'Keine Wahlkreiszuordnung für diese PLZ gefunden.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.amberText),
          ),
        );

      case _LookupState.error:
        return _InfoBox(
          color: AppColors.warmSurface,
          child: Text(
            'Lookup nicht verfügbar. Du kannst diesen Schritt überspringen.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.amberText),
          ),
        );

      case _LookupState.done:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (results.length > 1) ...[
              Text(
                'Deine PLZ liegt in mehreren Wahlkreisen. Wähle deinen:',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.mutedText,
                    ),
              ),
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.subtleBorder),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<MdbOption>(
                    value: selected,
                    isExpanded: true,
                    items: results
                        .map(
                          (opt) => DropdownMenuItem(
                            value: opt,
                            child: Text(
                              '${opt.wahlkreisName} (${opt.mdbParty})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: onSelect,
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (selected != null) _MdbCard(mdb: selected!),
          ],
        );
    }
  }
}

class _MdbCard extends StatelessWidget {
  const _MdbCard({required this.mdb});
  final MdbOption mdb;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      color: AppColors.greenWash,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.how_to_vote_outlined,
              color: AppColors.greenDark,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mdb.mdbName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${mdb.mdbParty} · ${mdb.wahlkreisName}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.mutedText,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}
