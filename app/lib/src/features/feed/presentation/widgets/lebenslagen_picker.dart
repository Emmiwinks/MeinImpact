import 'package:flutter/material.dart';

import '../../domain/lebenslage.dart';
import '../../domain/lebenslagen_catalog.g.dart';
import '../../domain/lebenslagen_search.dart';
import 'app_colors.dart';

/// "Was ist dir wichtig?": the Lebenslagen picker, shared between onboarding
/// (`DemographicScreen`) and the always-editable Profil tab
/// (`ProfileColumn`). One relation only: picking a group means it matters
/// to you, whether you are affected yourself, know someone who is or simply
/// care. Stateless about the value: the caller owns the selection and gets
/// a full replacement set on every change.
///
/// Every group sits in the same list; private ones (see
/// `Lebenslage.isPrivate`) only carry a lock and are never named in the
/// profile overview or on a feed card.
class LebenslagenPicker extends StatefulWidget {
  const LebenslagenPicker({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  State<LebenslagenPicker> createState() => _LebenslagenPickerState();
}

class _LebenslagenPickerState extends State<LebenslagenPicker> {
  // The occupation list is long, so it is collapsed unless one is picked.
  static const _collapsedArea = 'Beruf';

  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(String id) {
    final next = {...widget.selected};
    if (!next.remove(id)) next.add(id);
    widget.onChanged(next);
  }

  Widget _chips(Iterable<Lebenslage> items) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          _LebenslageChip(
            item: item,
            selected: widget.selected.contains(item.id),
            onTap: () => _toggle(item.id),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: AppColors.mutedText);
    final query = _search.text.trim();
    final results = searchLebenslagen(query);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Was ist dir wichtig?',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Wähle, was dich betrifft oder dir am Herzen liegt, auch wenn es '
          'um andere geht. Alles, was du hier auswählst, bleibt auf deinem '
          'Gerät und wird nie übertragen.',
          style: muted,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(
              Icons.lock_outline,
              size: 13,
              color: AppColors.mutedText,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Erscheint nicht in deiner Profil-Übersicht.',
                style: muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          decoration: InputDecoration(
            hintText: 'Suchen, z. B. Beruf oder Lebenslage',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Suche leeren',
                    icon: const Icon(Icons.close),
                    onPressed: _search.clear,
                  ),
            isDense: true,
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
        ),
        const SizedBox(height: 14),
        if (query.isNotEmpty)
          results.isEmpty
              ? Text('Nichts gefunden.', style: muted)
              : _chips(results)
        else
          for (final area in kLebenslageAreas) ...[
            _AreaSection(
              area: area,
              collapsible: area == _collapsedArea,
              initiallyExpanded: kLebenslagen.any(
                (i) => i.area == area && widget.selected.contains(i.id),
              ),
              child: _chips(kLebenslagen.where((i) => i.area == area)),
            ),
            const SizedBox(height: 14),
          ],
      ],
    );
  }
}

class _AreaSection extends StatelessWidget {
  const _AreaSection({
    required this.area,
    required this.collapsible,
    required this.initiallyExpanded,
    required this.child,
  });

  final String area;
  final bool collapsible;
  final bool initiallyExpanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      area,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
    if (!collapsible) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [title, const SizedBox(height: 8), child],
      );
    }
    return Theme(
      // No divider lines: the section should look like its neighbours.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: title,
        subtitle: Text(
          'Oder oben nach deinem Beruf suchen',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.mutedText),
        ),
        initiallyExpanded: initiallyExpanded,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        expandedAlignment: Alignment.centerLeft,
        children: [child],
      ),
    );
  }
}

class _LebenslageChip extends StatelessWidget {
  const _LebenslageChip({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final Lebenslage item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(item.label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      avatar: item.isPrivate
          ? Icon(
              Icons.lock_outline,
              size: 15,
              color: selected ? AppColors.greenDark : AppColors.mutedText,
            )
          : null,
      selectedColor: AppColors.greenWash,
      backgroundColor: AppColors.surface,
      side: BorderSide(
        color: selected ? AppColors.green : AppColors.subtleBorder,
      ),
      labelStyle: TextStyle(
        color: selected ? AppColors.greenDark : AppColors.ink,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
