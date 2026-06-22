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
  final _customTopics = <String>[];
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _tap(String key) {
    setState(() {
      if (_blacklisted.contains(key)) return;
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

  void _addCustom() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return;
    final key = raw.toLowerCase();
    final predefinedKeys = _kTopics.map((t) => t.key).toSet();
    if (predefinedKeys.contains(key) || _customTopics.contains(key)) return;
    setState(() {
      _customTopics.add(key);
      _selected.add(key);
    });
    _controller.clear();
  }

  void _removeCustom(String key) {
    setState(() {
      _customTopics.remove(key);
      _selected.remove(key);
      _blacklisted.remove(key);
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
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
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
                      if (_customTopics.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Eigene Themen',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.mutedText,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final key in _customTopics)
                              _CustomChip(
                                label: key,
                                selected: _selected.contains(key),
                                blacklisted: _blacklisted.contains(key),
                                onTap: () => _tap(key),
                                onLongPress: () => _longPress(key),
                                onRemove: () => _removeCustom(key),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      _FreestyleInput(
                        controller: _controller,
                        onAdd: _addCustom,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
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

class _FreestyleInput extends StatelessWidget {
  const _FreestyleInput({
    required this.controller,
    required this.onAdd,
  });

  final TextEditingController controller;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onAdd(),
            decoration: InputDecoration(
              hintText: 'Weiteres Thema hinzufügen…',
              hintStyle: TextStyle(
                color: AppColors.mutedText,
                fontSize: 13,
              ),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.subtleBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.green, width: 1.5),
              ),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 44,
          height: 44,
          child: Material(
            color: AppColors.green,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onAdd,
              child: const Icon(Icons.add, color: Colors.white, size: 20),
            ),
          ),
        ),
      ],
    );
  }
}

class _CustomChip extends StatelessWidget {
  const _CustomChip({
    required this.label,
    required this.selected,
    required this.blacklisted,
    required this.onTap,
    required this.onLongPress,
    required this.onRemove,
  });

  final String label;
  final bool selected;
  final bool blacklisted;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRemove;

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
        padding: const EdgeInsets.only(left: 10, top: 6, bottom: 6, right: 4),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border, width: selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: textColor,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    decoration: blacklisted
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
            ),
            const SizedBox(width: 2),
            GestureDetector(
              onTap: onRemove,
              child: Icon(
                Icons.close,
                size: 14,
                color: AppColors.mutedText,
              ),
            ),
            const SizedBox(width: 4),
          ],
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
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
