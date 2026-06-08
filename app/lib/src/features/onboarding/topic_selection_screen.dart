import 'package:flutter/material.dart';

import '../feed/domain/user_profile.dart';
import '../feed/presentation/widgets/app_colors.dart';

const _kTopics = [
  _Topic('klimaschutz', 'Klimaschutz', '🌱'),
  _Topic('soziales', 'Soziale Gerechtigkeit', '🤝'),
  _Topic('demokratie', 'Demokratie & Rechtsstaat', '🗳️'),
  _Topic('bildung', 'Bildung', '📚'),
  _Topic('gesundheit', 'Gesundheit', '🏥'),
  _Topic('wirtschaft', 'Wirtschaft & Arbeit', '💼'),
  _Topic('wohnen', 'Wohnen', '🏠'),
  _Topic('digital', 'Digitalisierung', '💻'),
  _Topic('verkehr', 'Verkehr & Infrastruktur', '🚆'),
  _Topic('aussenpolitik', 'Außenpolitik', '🌍'),
];

class TopicSelectionScreen extends StatefulWidget {
  const TopicSelectionScreen({required this.onComplete, super.key});

  final void Function(List<String> topics, List<String> blacklist) onComplete;

  @override
  State<TopicSelectionScreen> createState() => _TopicSelectionScreenState();
}

class _TopicSelectionScreenState extends State<TopicSelectionScreen> {
  final _selected = <String>{};
  final _blacklisted = <String>{};

  void _tap(String key) {
    setState(() {
      if (_blacklisted.contains(key)) return; // blacklisted can't be selected
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else {
        _selected.add(key);
      }
    });
  }

  void _longPress(String key) {
    setState(() {
      if (_blacklisted.contains(key)) {
        _blacklisted.remove(key);
      } else {
        _blacklisted.add(key);
        _selected.remove(key);
      }
    });
  }

  void _confirm() {
    if (_selected.length < 2) return;
    widget.onComplete(_selected.toList(), _blacklisted.toList());
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = _selected.length >= 2;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'MeinImpact',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Was bewegt dich? Wähle mindestens 2 Themen.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.mutedText,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Gedrückt halten = nie anzeigen',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.mutedText,
                    ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.4,
                  children: [
                    for (final topic in _kTopics)
                      _TopicTile(
                        topic: topic,
                        selected: _selected.contains(topic.key),
                        blacklisted: _blacklisted.contains(topic.key),
                        onTap: () => _tap(topic.key),
                        onLongPress: () => _longPress(topic.key),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: canConfirm ? _confirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.subtleBorder,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Weiter',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({
    required this.topic,
    required this.selected,
    required this.blacklisted,
    required this.onTap,
    required this.onLongPress,
  });

  final _Topic topic;
  final bool selected;
  final bool blacklisted;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color border;
    final Color textColor;

    if (blacklisted) {
      bg = const Color(0xFFF5F0EB);
      border = AppColors.subtleBorder;
      textColor = AppColors.mutedText;
    } else if (selected) {
      bg = AppColors.greenWash;
      border = AppColors.green;
      textColor = AppColors.ink;
    } else {
      bg = AppColors.surface;
      border = AppColors.subtleBorder;
      textColor = AppColors.ink;
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border, width: selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Text(topic.emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                topic.label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: textColor,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      decoration: blacklisted
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (blacklisted)
              Icon(Icons.block, size: 12, color: AppColors.mutedText),
          ],
        ),
      ),
    );
  }
}

class _Topic {
  const _Topic(this.key, this.label, this.emoji);

  final String key;
  final String label;
  final String emoji;
}
