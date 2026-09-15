import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../domain/action_repository.dart';
import '../domain/topic.dart';
import '../domain/user_profile.dart';
import 'widgets/feed_error.dart';
import 'widgets/loading_card.dart';
import 'widgets/topic_detail_dialog.dart';
import 'widgets/topic_panel.dart';

/// The "Aktionen" tab — topics grouped from the scored action pool, tap to
/// see the petition/letter options for that topic. Fetches the pool once
/// per tab instance (device-side scoring, unchanged — see
/// `LocalFeedScorer`); grouping into topics is a pure presentation
/// transform on top of that (see `domain/topic.dart`).
class AktionenTab extends StatefulWidget {
  const AktionenTab({
    required this.actionRepository,
    required this.profile,
    super.key,
  });

  final ActionRepository actionRepository;
  final UserProfile profile;

  @override
  State<AktionenTab> createState() => _AktionenTabState();
}

class _AktionenTabState extends State<AktionenTab> {
  late Future<List<Topic>> _future;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Topic>> _load() async {
    final scored =
        await widget.actionRepository.recommendations(widget.profile);
    return groupIntoTopics(scored);
  }

  void _openTopic(List<Topic> topics, int index) {
    setState(() => _selectedIndex = index);
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => TopicDetailDialog(
        l10n: l10n,
        topic: topics[index],
        profile: widget.profile,
        repository: widget.actionRepository,
      ),
    ).then((_) {
      if (mounted) setState(() => _selectedIndex = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Topic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingCard();
        }
        if (snapshot.hasError) {
          return FeedError(message: snapshot.error.toString());
        }
        final topics = snapshot.data ?? const [];
        return TopicPanel(
          topics: topics,
          selectedIndex: _selectedIndex ?? -1,
          onSelect: (index) => _openTopic(topics, index),
        );
      },
    );
  }
}
