import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import 'src/app/meinimpact_app.dart';
import 'src/features/feed/data/demo_action_copy.dart';
import 'src/features/feed/data/demo_action_repository.dart';

void main() {
  runApp(
    MeinImpactApp.localized(
      createActionRepository: (l10n) => DemoActionRepository(
        _demoActionCopy(l10n),
      ),
    ),
  );
}

DemoActionCopy _demoActionCopy(AppLocalizations l10n) {
  return DemoActionCopy(
    topicClimate: l10n.topicClimate,
    topicHousing: l10n.topicHousing,
    topicEnergy: l10n.topicEnergy,
    topicEducation: l10n.topicEducation,
    topicDemocracy: l10n.topicDemocracy,
    solarTitle: l10n.demoSolarTitle,
    solarSummary: l10n.demoSolarSummary,
    solarImpactHint: l10n.demoSolarImpactHint,
    solarReasonTopics: l10n.demoSolarReasonTopics,
    solarReasonEffort: l10n.demoSolarReasonEffort,
    schoolTitle: l10n.demoSchoolTitle,
    schoolSummary: l10n.demoSchoolSummary,
    schoolImpactHint: l10n.demoSchoolImpactHint,
    schoolReasonSpending: l10n.demoSchoolReasonSpending,
    schoolReasonEffort: l10n.demoSchoolReasonEffort,
    draftDelta: l10n.demoDraftDelta,
  );
}
