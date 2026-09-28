import 'package:flutter/material.dart';

import '../../domain/betroffenheitsprofil.dart';
import 'app_colors.dart';

/// Editable Betroffenheitsprofil form — shared between onboarding
/// (`DemographicScreen`) and the always-editable "Mein Profil" tab
/// (`ProfileColumn`). Stateless: the caller owns the value and receives a
/// full replacement `Betroffenheitsprofil` on every change, so it can
/// either buffer it (onboarding) or persist it immediately (profile tab).
class BetroffenheitsprofilEditor extends StatelessWidget {
  const BetroffenheitsprofilEditor({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final Betroffenheitsprofil value;
  final ValueChanged<Betroffenheitsprofil> onChanged;

  Betroffenheitsprofil _with({
    Wohnsituation? wohnsituation,
    bool? oepnvNutzung,
    bool? autoNutzung,
    bool? hatKinder,
    Erwerbsstatus? erwerbsstatus,
    bool? pflegeBetroffen,
    bool? migrationshintergrund,
    bool clearWohnsituation = false,
    bool clearErwerbsstatus = false,
    bool clearMigrationshintergrund = false,
  }) {
    return Betroffenheitsprofil(
      wohnsituation:
          clearWohnsituation ? null : (wohnsituation ?? value.wohnsituation),
      oepnvNutzung: oepnvNutzung ?? value.oepnvNutzung,
      autoNutzung: autoNutzung ?? value.autoNutzung,
      hatKinder: hatKinder ?? value.hatKinder,
      erwerbsstatus:
          clearErwerbsstatus ? null : (erwerbsstatus ?? value.erwerbsstatus),
      pflegeBetroffen: pflegeBetroffen ?? value.pflegeBetroffen,
      migrationshintergrund: clearMigrationshintergrund
          ? null
          : (migrationshintergrund ?? value.migrationshintergrund),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Deine Situation',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 12),
        const _QuestionLabel('Wie wohnst du?'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _ChoiceChip(
              label: 'Mieter:in',
              selected: value.wohnsituation == Wohnsituation.mieter,
              onSelected: (sel) => onChanged(
                sel
                    ? _with(wohnsituation: Wohnsituation.mieter)
                    : _with(clearWohnsituation: true),
              ),
            ),
            _ChoiceChip(
              label: 'Eigentümer:in',
              selected: value.wohnsituation == Wohnsituation.eigentuemer,
              onSelected: (sel) => onChanged(
                sel
                    ? _with(wohnsituation: Wohnsituation.eigentuemer)
                    : _with(clearWohnsituation: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _QuestionLabel('Was beschreibt dich beruflich am besten?'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final status in Erwerbsstatus.values)
              _ChoiceChip(
                label: _erwerbsstatusLabel(status),
                selected: value.erwerbsstatus == status,
                onSelected: (sel) => onChanged(
                  sel
                      ? _with(erwerbsstatus: status)
                      : _with(clearErwerbsstatus: true),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        _SwitchRow(
          label: 'Ich pflege einen Angehörigen',
          value: value.pflegeBetroffen,
          onChanged: (v) => onChanged(_with(pflegeBetroffen: v)),
        ),
        _SwitchRow(
          label: 'Ich habe Kinder',
          value: value.hatKinder,
          onChanged: (v) => onChanged(_with(hatKinder: v)),
        ),
        _SwitchRow(
          label: 'Ich nutze regelmäßig Bus & Bahn',
          value: value.oepnvNutzung,
          onChanged: (v) => onChanged(_with(oepnvNutzung: v)),
        ),
        _SwitchRow(
          label: 'Ich nutze regelmäßig das Auto',
          value: value.autoNutzung,
          onChanged: (v) => onChanged(_with(autoNutzung: v)),
        ),
        const SizedBox(height: 10),
        const _QuestionLabel('Hast du einen Migrationshintergrund?'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _ChoiceChip(
              label: 'Ja',
              selected: value.migrationshintergrund == true,
              onSelected: (sel) => onChanged(
                sel
                    ? _with(migrationshintergrund: true)
                    : _with(clearMigrationshintergrund: true),
              ),
            ),
            _ChoiceChip(
              label: 'Nein',
              selected: value.migrationshintergrund == false,
              onSelected: (sel) => onChanged(
                sel
                    ? _with(migrationshintergrund: false)
                    : _with(clearMigrationshintergrund: true),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _erwerbsstatusLabel(Erwerbsstatus status) => switch (status) {
      Erwerbsstatus.angestellt => 'Angestellt',
      Erwerbsstatus.selbststaendig => 'Selbstständig',
      Erwerbsstatus.arbeitslos => 'Arbeitssuchend',
      Erwerbsstatus.rentner => 'Rentner:in',
      Erwerbsstatus.schuelerStudent => 'Schüler:in / Student:in',
    };

class _QuestionLabel extends StatelessWidget {
  const _QuestionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final void Function(bool) onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
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

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.green,
          ),
        ],
      ),
    );
  }
}
