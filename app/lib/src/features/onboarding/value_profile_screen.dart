import 'package:flutter/material.dart';

import '../feed/domain/user_profile.dart';
import '../feed/presentation/widgets/app_colors.dart';

const _kQuestions = [
  _Question(
    key: 'wirtschaft_gleichheit',
    leftLabel: 'Umverteilung',
    leftDesc:
        'Der Staat sollte große Vermögen und Einkommen stärker ausgleichen.',
    rightLabel: 'Eigenverantwortung',
    rightDesc:
        'Wer Leistung bringt, sollte davon profitieren — mit möglichst wenig staatlichem Eingriff.',
  ),
  _Question(
    key: 'wirtschaft_staat',
    leftLabel: 'Staatliche Steuerung',
    leftDesc:
        'Der Staat muss Märkte regulieren und wichtige Bereiche selbst kontrollieren.',
    rightLabel: 'Freier Markt',
    rightDesc:
        'Privatwirtschaft und Wettbewerb lösen Probleme besser als der Staat.',
  ),
  _Question(
    key: 'diplomatie_nation',
    leftLabel: 'Nationale Interessen',
    leftDesc:
        'Deutschland sollte seine eigenen Interessen klar vertreten, auch wenn das Partner vor den Kopf stößt.',
    rightLabel: 'Internationale Kooperation',
    rightDesc:
        'Globale Probleme lassen sich nur gemeinsam lösen — nationale Alleingänge bringen nichts.',
  ),
  _Question(
    key: 'diplomatie_welt',
    leftLabel: 'Souveränität',
    leftDesc:
        'Deutschland sollte außenpolitisch unabhängiger werden und weniger Verpflichtungen eingehen.',
    rightLabel: 'Globale Verantwortung',
    rightDesc:
        'Deutschland muss mehr globale Verantwortung übernehmen, auch wenn das kostet.',
  ),
  _Question(
    key: 'freiheit_staat',
    leftLabel: 'Persönliche Freiheit',
    leftDesc:
        'Der Staat soll so wenig wie möglich in das Leben der Menschen eingreifen.',
    rightLabel: 'Gesellschaftliche Ordnung',
    rightDesc:
        'Mehr staatliche Regeln und Kontrolle sind nötig, um Sicherheit und Zusammenhalt zu gewährleisten.',
  ),
  _Question(
    key: 'freiheit_sicherheit',
    leftLabel: 'Bürgerrechte',
    leftDesc:
        'Im Zweifel sind Bürgerrechte wichtiger als staatliche Sicherheitsinteressen.',
    rightLabel: 'Innere Sicherheit',
    rightDesc:
        'Im Zweifel ist Sicherheit wichtiger als individuelle Freiheiten.',
  ),
  _Question(
    key: 'wandel_tradition',
    leftLabel: 'Bewährtes erhalten',
    leftDesc:
        'Gesellschaftliche Strukturen, die sich bewährt haben, sollten erhalten bleiben.',
    rightLabel: 'Wandel gestalten',
    rightDesc:
        'Die Gesellschaft muss sich mutig weiterentwickeln, auch wenn das unbequem ist.',
  ),
  _Question(
    key: 'wandel_zukunft',
    leftLabel: 'Generationengerechtigkeit',
    leftDesc:
        'Wir fordern zu viel von der heutigen Generation für Probleme, die erst in der Zukunft spürbar werden.',
    rightLabel: 'Zukunftsverantwortung',
    rightDesc:
        'Ich bin bereit, heute auf Komfort zu verzichten, damit zukünftige Generationen es besser haben.',
  ),
];

class ValueProfileScreen extends StatefulWidget {
  const ValueProfileScreen({required this.onComplete, super.key});

  final void Function(Map<String, int> werte) onComplete;

  @override
  State<ValueProfileScreen> createState() => _ValueProfileScreenState();
}

class _ValueProfileScreenState extends State<ValueProfileScreen> {
  int _step = 0;
  final _answers = <String, int>{};

  void _answer(int value) {
    setState(() {
      _answers[_kQuestions[_step].key] = value;
    });
  }

  void _next() {
    if (_step < _kQuestions.length - 1) {
      setState(() => _step++);
    } else {
      widget.onComplete(_answers);
    }
  }

  void _skip() {
    // Neutral (0) is valid — leave the key absent (defaults to 0 in profile)
    if (_step < _kQuestions.length - 1) {
      setState(() => _step++);
    } else {
      widget.onComplete(_answers);
    }
  }

  int get _answeredCount => _answers.values.where((v) => v != 0).length;
  bool get _canFinish => _answeredCount >= 4;

  @override
  Widget build(BuildContext context) {
    final q = _kQuestions[_step];
    final current = _answers[q.key] ?? 0;
    final isLast = _step == _kQuestions.length - 1;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Frage ${_step + 1} von ${_kQuestions.length}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.mutedText,
                        ),
                  ),
                  const Spacer(),
                  if (!isLast || !_canFinish)
                    TextButton(
                      onPressed: _skip,
                      child: Text(
                        'Überspringen',
                        style: TextStyle(
                          color: AppColors.mutedText,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: (_step + 1) / _kQuestions.length,
                backgroundColor: AppColors.subtleBorder,
                color: AppColors.green,
                minHeight: 3,
                borderRadius: BorderRadius.circular(2),
              ),
              const SizedBox(height: 28),
              Text(
                'Wo stehst du?',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Kein Richtig oder Falsch. Hilft uns, Briefe zu schreiben, die klingen wie du.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.mutedText,
                    ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: _QuestionCard(
                  question: q,
                  value: current,
                  onChanged: _answer,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    isLast ? 'Fertig' : 'Weiter',
                    style: const TextStyle(fontWeight: FontWeight.w700),
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

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.value,
    required this.onChanged,
  });

  final _Question question;
  final int value;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    question.leftLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    question.leftDesc,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.mutedText,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    question.rightLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                    textAlign: TextAlign.end,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    question.rightDesc,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.mutedText,
                        ),
                    textAlign: TextAlign.end,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Slider(
          value: value.toDouble(),
          min: -2,
          max: 2,
          divisions: 4,
          activeColor: AppColors.green,
          inactiveColor: AppColors.subtleBorder,
          onChanged: (v) => onChanged(v.round()),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final label in ['−2', '−1', '0', '+1', '+2'])
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.mutedText,
                      fontSize: 11,
                    ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Question {
  const _Question({
    required this.key,
    required this.leftLabel,
    required this.leftDesc,
    required this.rightLabel,
    required this.rightDesc,
  });

  final String key;
  final String leftLabel;
  final String leftDesc;
  final String rightLabel;
  final String rightDesc;
}
