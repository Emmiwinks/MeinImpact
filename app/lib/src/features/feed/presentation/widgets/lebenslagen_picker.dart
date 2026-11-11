import 'package:flutter/material.dart';

import '../../../../app/theme/mi_theme.dart';
import '../../domain/lebenslage.dart';
import '../../domain/lebenslagen_catalog.g.dart';
import '../../domain/lebenslagen_search.dart';

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
      spacing: MiSpace.sm,
      runSpacing: MiSpace.sm,
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
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: colors.onTableMuted);
    final query = _search.text.trim();
    final results = searchLebenslagen(query);
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(MiRadius.chip),
      borderSide: BorderSide(color: colors.keyline),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Was ist dir wichtig?', style: text.titleLarge),
        const SizedBox(height: MiSpace.sm),
        Text(
          'Wähle, was dich betrifft oder dir am Herzen liegt, auch wenn es '
          'um andere geht. Alles, was du hier auswählst, bleibt auf deinem '
          'Gerät und wird nie übertragen.',
          style: muted,
        ),
        const SizedBox(height: MiSpace.xs),
        Row(
          children: [
            Icon(Icons.lock_outline, size: 16, color: colors.onTableMuted),
            const SizedBox(width: MiSpace.xs),
            Expanded(
              child: Text(
                'Erscheint nicht in deiner Profil-Übersicht.',
                style: muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: MiSpace.base),
        TextField(
          controller: _search,
          style: text.bodyLarge,
          decoration: InputDecoration(
            hintText: 'Suchen, z. B. Beruf oder Lebenslage',
            hintStyle: muted,
            prefixIcon: Icon(Icons.search, color: colors.onTableMuted),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Suche leeren',
                    color: colors.onTableMuted,
                    icon: const Icon(Icons.close),
                    onPressed: _search.clear,
                  ),
            filled: true,
            fillColor: colors.tableRaised,
            border: fieldBorder,
            enabledBorder: fieldBorder,
            focusedBorder: fieldBorder.copyWith(
              borderSide: BorderSide(color: colors.onTableMuted, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: MiSpace.lg),
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
            const SizedBox(height: MiSpace.lg),
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
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final title = Text(area, style: text.titleMedium);
    if (!collapsible) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [title, const SizedBox(height: MiSpace.md), child],
      );
    }
    return Theme(
      // No divider lines: the section should look like its neighbours.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: title,
        subtitle: Text(
          'Oder oben nach deinem Beruf suchen',
          style: text.bodyMedium?.copyWith(color: colors.onTableMuted),
        ),
        initiallyExpanded: initiallyExpanded,
        iconColor: colors.onTable,
        collapsedIconColor: colors.onTableMuted,
        textColor: colors.onTable,
        collapsedTextColor: colors.onTable,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: MiSpace.xs),
        expandedAlignment: Alignment.centerLeft,
        children: [child],
      ),
    );
  }
}

/// Picked: the amber "selected" fill with ink text and a check (or the lock
/// for private groups), so the state never rests on colour alone. A pill of
/// its own rather than a FilterChip, so long labels ("Wohnungslos oder von
/// Wohnungslosigkeit bedroht") wrap instead of being cut off.
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
    final colors = context.mi;
    final foreground = selected ? colors.onCard : colors.onTable;
    final icon = item.isPrivate
        ? Icons.lock_outline
        : selected
            ? Icons.check
            : null;
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
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: foreground),
                    const SizedBox(width: MiSpace.sm - 2),
                  ],
                  Flexible(
                    child: Text(
                      item.label,
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
