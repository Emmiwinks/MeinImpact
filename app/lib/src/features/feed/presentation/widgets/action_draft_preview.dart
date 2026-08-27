import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/action_repository.dart';
import '../../domain/civic_action.dart';
import '../../domain/user_profile.dart';
import 'app_colors.dart';
import 'components/info_box.dart';
import 'components/surface_card.dart';
import 'components/text_badges.dart';

class ActionDetailCard extends StatefulWidget {
  const ActionDetailCard({
    required this.l10n,
    required this.recommendation,
    required this.profile,
    required this.repository,
    super.key,
  });

  final AppLocalizations l10n;
  final ActionRecommendation recommendation;
  final UserProfile profile;
  final ActionRepository repository;

  @override
  State<ActionDetailCard> createState() => _ActionDetailCardState();
}

enum _DraftState { idle, loading, done, error }

class _ActionDetailCardState extends State<ActionDetailCard> {
  _DraftState _draftState = _DraftState.idle;
  final _draftController = TextEditingController();
  String _errorMessage = '';
  late Future<String> _contextFuture;

  @override
  void initState() {
    super.initState();
    _contextFuture = _loadContext();
  }

  Future<String> _loadContext() {
    return widget.repository.getContext(
      actionId: widget.recommendation.action.id,
      profile: widget.profile,
    );
  }

  @override
  void didUpdateWidget(ActionDetailCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recommendation.action.id != widget.recommendation.action.id) {
      _draftState = _DraftState.idle;
      _draftController.clear();
      _contextFuture = _loadContext();
    }
  }

  @override
  void dispose() {
    _draftController.dispose();
    super.dispose();
  }

  String get _letterType {
    final t = widget.recommendation.action.actionType;
    return t == 'public_question' ? 'anfrage' : 'brief';
  }

  Future<void> _startDraft() async {
    setState(() {
      _draftState = _DraftState.loading;
      _draftController.clear();
    });
    try {
      await for (final event in widget.repository.streamDraft(
        actionId: widget.recommendation.action.id,
        profile: widget.profile,
        letterType: _letterType,
      )) {
        if (!mounted) return;
        if (event.data == '[DONE]') {
          setState(() => _draftState = _DraftState.done);
          return;
        }
        setState(() => _draftController.text += event.data);
      }
      if (mounted) setState(() => _draftState = _DraftState.done);
    } catch (e) {
      if (mounted) {
        setState(() {
          _draftState = _DraftState.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _openSource() async {
    final uri = Uri.tryParse(widget.recommendation.action.sourceUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  bool get _showDraftButton {
    final t = widget.recommendation.action.actionType;
    return t == 'representative_letter' || t == 'public_question';
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.recommendation.action;

    return SurfaceCard(
      color: AppColors.surface,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(label: widget.l10n.aiSupportTitle),
          const SizedBox(height: 9),
          Text(
            action.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.08,
                ),
          ),
          const SizedBox(height: 14),
          // Timing/urgency — why this matters to act on now.
          InfoBox(
            title: widget.l10n.whyNowTitle,
            body: action.impactHint,
            color: AppColors.surfaceMuted,
          ),
          const SizedBox(height: 10),
          // Personalised for the current profile via the AI context endpoint.
          FutureBuilder<String>(
            future: _contextFuture,
            builder: (context, snapshot) {
              final body = switch (snapshot.connectionState) {
                ConnectionState.done when snapshot.hasError =>
                  widget.l10n.contextUnavailable,
                ConnectionState.done => (snapshot.data?.isNotEmpty ?? false)
                    ? snapshot.data!
                    : widget.l10n.contextUnavailable,
                _ => widget.l10n.contextLoading,
              };
              return InfoBox(
                title: widget.l10n.whatItMeansTitle,
                body: body,
                color: AppColors.greenWash,
              );
            },
          ),
          if (action.proArgumente.isNotEmpty ||
              action.contraArgumente.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ProsConsSection(
              prosTitle: widget.l10n.prosTitle,
              consTitle: widget.l10n.consTitle,
              pros: action.proArgumente,
              cons: action.contraArgumente,
            ),
          ],
          const SizedBox(height: 16),
          // External source link — always available
          _SourceButton(label: 'Zur Quelle →', onTap: _openSource),
          // Draft panel for letter/question types
          if (_showDraftButton) ...[
            const SizedBox(height: 10),
            _DraftSection(
              state: _draftState,
              controller: _draftController,
              errorMessage: _errorMessage,
              onStart: _startDraft,
              onOpen: _openSource,
            ),
          ],
        ],
      ),
    );
  }
}

class _ProsConsSection extends StatelessWidget {
  const _ProsConsSection({
    required this.prosTitle,
    required this.consTitle,
    required this.pros,
    required this.cons,
  });

  final String prosTitle;
  final String consTitle;
  final List<String> pros;
  final List<String> cons;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = [
          if (pros.isNotEmpty)
            Expanded(
              child: _ArgumentList(
                title: prosTitle,
                points: pros,
                icon: Icons.add_circle_outline,
                color: AppColors.green,
              ),
            ),
          if (cons.isNotEmpty)
            Expanded(
              child: _ArgumentList(
                title: consTitle,
                points: cons,
                icon: Icons.remove_circle_outline,
                color: AppColors.amberText,
              ),
            ),
        ];
        if (constraints.maxWidth < 420 && columns.length > 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              columns[0].child,
              const SizedBox(height: 10),
              columns[1].child,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < columns.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              columns[i],
            ],
          ],
        );
      },
    );
  }
}

class _ArgumentList extends StatelessWidget {
  const _ArgumentList({
    required this.title,
    required this.points,
    required this.icon,
    required this.color,
  });

  final String title;
  final List<String> points;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.mutedText,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
          ),
          const SizedBox(height: 8),
          for (final point in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      point,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.ink,
                            height: 1.3,
                          ),
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

class _SourceButton extends StatelessWidget {
  const _SourceButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.subtleBorder),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _DraftSection extends StatelessWidget {
  const _DraftSection({
    required this.state,
    required this.controller,
    required this.errorMessage,
    required this.onStart,
    required this.onOpen,
  });

  final _DraftState state;
  final TextEditingController controller;
  final String errorMessage;
  final VoidCallback onStart;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case _DraftState.idle:
        return _PrimaryButton(
          label: 'Brief mit KI verfassen',
          onPressed: onStart,
        );

      case _DraftState.loading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              maxLines: null,
              readOnly: true,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                hintText: 'Wird geschrieben…',
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            const LinearProgressIndicator(
              backgroundColor: AppColors.subtleBorder,
              color: AppColors.green,
              minHeight: 2,
            ),
          ],
        );

      case _DraftState.done:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              maxLines: null,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                hintText: 'Brief bearbeiten…',
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            _PrimaryButton(
              label: 'Entwurf öffnen & absenden →',
              onPressed: onOpen,
            ),
          ],
        );

      case _DraftState.error:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'Brief-Erstellung nicht verfügbar. Öffne die Quelle und verfasse deinen Brief manuell.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.mutedText),
          ),
        );
    }
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.green,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
