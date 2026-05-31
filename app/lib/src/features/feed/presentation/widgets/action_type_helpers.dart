import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import 'app_colors.dart';

String actionTypeLabel(AppLocalizations l10n, String actionType) {
  return switch (actionType) {
    'representative_letter' => l10n.actionTypeLetter,
    'petition_signature' => l10n.actionTypePetition,
    'public_question' => l10n.actionTypeQuestion,
    'consultation_comment' => l10n.actionTypeStatement,
    _ => l10n.actionTypeAction,
  };
}

IconData actionTypeIcon(String actionType) {
  return switch (actionType) {
    'representative_letter' => Icons.mail_outline_rounded,
    'petition_signature' => Icons.fact_check_outlined,
    'public_question' => Icons.forum_outlined,
    'consultation_comment' => Icons.edit_note_outlined,
    _ => Icons.bolt_outlined,
  };
}

Color actionTypeColor(String actionType) {
  return switch (actionType) {
    'petition_signature' => AppColors.amberText,
    'public_question' => AppColors.blueText,
    _ => AppColors.greenDark,
  };
}
