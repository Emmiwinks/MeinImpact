import 'package:flutter/material.dart';

import 'src/app/meinimpact_app.dart';
import 'src/features/feed/data/demo_action_repository.dart';

void main() {
  runApp(
    MeinImpactApp(
      actionRepository: DemoActionRepository(),
    ),
  );
}
