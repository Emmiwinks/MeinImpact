import 'package:flutter/material.dart';

import '../features/feed/domain/action_repository.dart';
import '../features/feed/presentation/action_feed_screen.dart';

class MeinImpactApp extends StatelessWidget {
  const MeinImpactApp({
    required this.actionRepository,
    super.key,
  });

  final ActionRepository actionRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MeinImpact',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1FA37A),
        ),
        useMaterial3: true,
      ),
      home: ActionFeedScreen(actionRepository: actionRepository),
    );
  }
}
