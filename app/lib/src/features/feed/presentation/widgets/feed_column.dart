import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../../domain/action_repository.dart';
import '../../domain/civic_action.dart';
import '../../domain/user_profile.dart';
import 'action_draft_preview.dart';
import 'recommendation_panel.dart';

class FeedColumn extends StatefulWidget {
  const FeedColumn({
    required this.l10n,
    required this.recommendations,
    required this.profile,
    required this.repository,
    super.key,
  });

  final AppLocalizations l10n;
  final List<ActionRecommendation> recommendations;
  final UserProfile profile;
  final ActionRepository repository;

  @override
  State<FeedColumn> createState() => _FeedColumnState();
}

class _FeedColumnState extends State<FeedColumn> {
  int? _selectedIndex;

  @override
  void didUpdateWidget(FeedColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset selection when recommendations change
    if (oldWidget.recommendations != widget.recommendations) {
      _selectedIndex = null;
    }
  }

  void _openDetail(int index) {
    setState(() => _selectedIndex = index);
    final recommendation = widget.recommendations[index];
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _ActionDetailDialog(
        l10n: widget.l10n,
        recommendation: recommendation,
        profile: widget.profile,
        repository: widget.repository,
      ),
    ).then((_) {
      if (mounted) setState(() => _selectedIndex = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return RecommendationPanel(
      l10n: widget.l10n,
      recommendations: widget.recommendations,
      selectedIndex: _selectedIndex ?? -1,
      onSelect: _openDetail,
    );
  }
}

class _ActionDetailDialog extends StatelessWidget {
  const _ActionDetailDialog({
    required this.l10n,
    required this.recommendation,
    required this.profile,
    required this.repository,
  });

  final AppLocalizations l10n;
  final ActionRecommendation recommendation;
  final UserProfile profile;
  final ActionRepository repository;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SingleChildScrollView(
              child: ActionDetailCard(
                key: ValueKey(recommendation.action.id),
                l10n: l10n,
                recommendation: recommendation,
                profile: profile,
                repository: repository,
              ),
            ),
            Positioned(
              top: -12,
              right: -12,
              child: _CloseButton(onTap: () => Navigator.of(context).pop()),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(Icons.close, size: 20),
        ),
      ),
    );
  }
}
