import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

/// Why a card was thrown away, as the pop-up offers it.
enum CardReason {
  tooFar('too_far', 'Zu weit weg'),
  notInterested('not_interested', 'Thema interessiert mich nicht'),
  notAffected('not_affected', 'Betrifft mich nicht'),
  tooMuchEffort('too_much_effort', 'Zu viel Aufwand'),
  unclearText('unclear_text', 'Text unklar oder falsch'),
  dontSupport('dont_support', 'Möchte ich nicht unterstützen'),
  other('other', 'Sonstiges');

  const CardReason(this.wire, this.label);

  final String wire;
  final String label;

  /// Reasons that ask for a few words, if the user likes.
  bool get takesNote => this == dontSupport || this == other;
}

/// What a free-text message is about.
enum MessageKind {
  bug('bug', 'Fehler'),
  idea('idea', 'Idee'),
  praise('praise', 'Lob'),
  other('other', 'Sonstiges');

  const MessageKind(this.wire, this.label);

  final String wire;
  final String label;
}

/// Beta feedback for /admin/feedback: why a card was thrown away, and
/// messages from "Feedback geben". The server keeps it under a code name
/// for 180 days (specs/architecture/dsgvo.md).
///
/// Off (the default, so tests and demos send nothing) until `main` sets
/// [current].
class BetaFeedback {
  BetaFeedback({
    required Future<void> Function(String path, Map<String, Object?> body) post,
  }) : _post = post;

  BetaFeedback.off() : _post = null;

  static BetaFeedback current = BetaFeedback.off();

  final Future<void> Function(String path, Map<String, Object?> body)? _post;

  /// Best effort: offline, the reason is lost and the app carries on.
  void card({
    required String opportunityId,
    required CardReason reason,
    required Map<String, Object?> ranking,
    String? note,
  }) {
    final post = _post;
    if (post == null) return;
    final text = note?.trim();
    unawaited(
      post('/v1/feedback/card', {
        'opportunity_id': opportunityId,
        'reason': reason.wire,
        if (text != null && text.isNotEmpty) 'note': text,
        'ranking': ranking,
        'app_version': kAppVersion,
      }).catchError((Object error) {
        debugPrint('Card feedback could not be sent: $error');
      }),
    );
  }

  /// Throws when it could not be sent, so the user can try again.
  Future<void> message({
    required MessageKind kind,
    required String message,
    required String screen,
  }) async {
    final post = _post;
    if (post == null) return;
    await post('/v1/feedback', {
      'kind': kind.wire,
      'message': message.trim(),
      'screen': screen,
      'app_version': kAppVersion,
      'platform': kIsWeb
          ? 'web'
          : defaultTargetPlatform == TargetPlatform.iOS
              ? 'ios'
              : 'android',
    });
  }
}
