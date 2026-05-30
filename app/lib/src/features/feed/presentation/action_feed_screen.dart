import 'package:flutter/material.dart';

import '../domain/action_repository.dart';
import '../domain/civic_action.dart';
import '../domain/user_profile.dart';

class ActionFeedScreen extends StatelessWidget {
  const ActionFeedScreen({
    required this.actionRepository,
    super.key,
  });

  final ActionRepository actionRepository;

  static const _defaultProfile = UserProfile(
    topics: ['climate', 'housing', 'democracy'],
    valueAxes: {'civil_rights': 2},
    region: 'Germany',
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MeinImpact')),
      body: FutureBuilder<List<ActionRecommendation>>(
        future: actionRepository.recommendations(_defaultProfile),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _FeedError(message: snapshot.error.toString());
          }
          final recommendations = snapshot.data ?? const [];
          return _RecommendationList(recommendations: recommendations);
        },
      ),
    );
  }
}

class _RecommendationList extends StatelessWidget {
  const _RecommendationList({required this.recommendations});

  final List<ActionRecommendation> recommendations;

  @override
  Widget build(BuildContext context) {
    if (recommendations.isEmpty) {
      return const Center(child: Text('No actions available yet.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        return _ActionCard(recommendation: recommendations[index]);
      },
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemCount: recommendations.length,
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.recommendation});

  final ActionRecommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final action = recommendation.action;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              action.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(action.summary),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('${action.effortMinutes} min')),
                Chip(label: Text('Score ${recommendation.score}')),
                for (final topic in action.topics) Chip(label: Text(topic)),
              ],
            ),
            const SizedBox(height: 12),
            Text(action.impactHint),
          ],
        ),
      ),
    );
  }
}

class _FeedError extends StatelessWidget {
  const _FeedError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Could not load recommendations: $message'),
      ),
    );
  }
}
