/// What the notifications say. Rotating pools, picked by the week, so the
/// same week always gets the same text and the next one another.
///
/// An action concerning a private Lebenslage is never named: those
/// notifications say something general instead, worded like the general
/// variants everyone gets now and then, so nothing stands out.
library;

typedef NotificationText = ({String title, String body});

/// Sunday evening, when the flame would go out at midnight. {n} is the
/// streak's weeks; those lines need at least two.
const kFlameTexts = <NotificationText>[
  (
    title: 'Deine Stimme fehlt noch',
    body: 'Eine Aktion bis Mitternacht, und deine Flamme brennt weiter.',
  ),
  (
    title: 'Gibt’s nichts, was dich nervt?',
    body: 'Dann sag’s laut. Eine Aktion bis Mitternacht hält deine Flamme '
        'am Leben.',
  ),
  (
    title: 'Noch keinen Senf dazugegeben?',
    body: 'Bis Mitternacht ist Zeit, sonst geht deine Flamme aus.',
  ),
  (
    title: 'Demokratie lebt vom Mitreden',
    body: 'Und deine Flamme davon, dass du’s tust. Noch bis Mitternacht.',
  ),
  (
    title: 'Ein Klick, eine Stimme',
    body: 'Mehr braucht’s nicht, damit deine Flamme die Nacht übersteht.',
  ),
  (
    title: '{n} Wochen mitgeredet',
    body: 'Mach die {n+1} voll: Eine Aktion bis Mitternacht reicht.',
  ),
  (
    title: 'Wer mitredet, hält das Feuer an',
    body: 'Deine Flamme braucht heute noch eine Aktion.',
  ),
];

/// Monday's titles. {x} is the number of new opportunities that fit; those
/// lines need at least two.
const kWeekTitles = [
  'Neue Woche, neue Möglichkeiten',
  'Wo willst du diese Woche mitreden?',
  'Diese Woche kannst du {x}-mal mitreden',
  'Deine Stimme ist gefragt',
  '{x} Gelegenheiten, gehört zu werden',
  'Gibt’s was, wozu du deinen Senf geben willst?',
  'Was diese Woche ansteht',
  '{x} neue Wege, etwas zu bewegen',
  'Neue Woche, neue Perspektiven',
  'Frischer Wind für deine Woche',
];

/// Monday's lines naming the best new one ({t}).
const kWeekBodiesNamed = [
  'Ganz vorn: {t}',
  'Zum Beispiel: {t}',
  'Passt gut zu dir: {t}',
];

/// Monday's lines without one: every third week for everyone, and always
/// when the best one concerns a private Lebenslage.
const kWeekBodiesPlain = [
  'Schau mal rein, was diesmal dabei ist.',
  'Manchmal reichen fünf Minuten.',
  'Mitreden geht leichter, als man denkt.',
];

NotificationText flameText(int week, int streakWeeks) {
  for (var i = 0; i < kFlameTexts.length; i++) {
    final text = kFlameTexts[(week + i) % kFlameTexts.length];
    if (text.title.contains('{n}') && streakWeeks < 2) continue;
    return (
      title: text.title.replaceAll('{n}', '$streakWeeks'),
      body: text.body
          .replaceAll('{n+1}', '${streakWeeks + 1}')
          .replaceAll('{n}', '$streakWeeks'),
    );
  }
  return kFlameTexts.first;
}

/// [best] is the title to name, or null to name none.
NotificationText weekText(int week, int count, String? best) {
  var title = kWeekTitles.first;
  for (var i = 0; i < kWeekTitles.length; i++) {
    final candidate = kWeekTitles[(week + i) % kWeekTitles.length];
    if (candidate.contains('{x}') && count < 2) continue;
    title = candidate.replaceAll('{x}', '$count');
    break;
  }
  final named = best != null && week % 3 != 0;
  return (
    title: title,
    body: named
        ? kWeekBodiesNamed[week % kWeekBodiesNamed.length]
            .replaceAll('{t}', best)
        : kWeekBodiesPlain[(week ~/ 3) % kWeekBodiesPlain.length],
  );
}

/// New reports on starred actions: [titles] of the actions (null for a
/// private one), [reports] the new headlines of a single action.
NotificationText newsText(List<String?> titles, List<String> reports) {
  if (titles.length > 1) {
    return (
      title: 'Neues zu ${titles.length} deiner Aktionen',
      body: 'Es gibt neue Berichte dazu.',
    );
  }
  final title = titles.single;
  final body = reports.length == 1 && title != null
      ? reports.single
      : reports.length == 1
          ? 'Es gibt einen neuen Bericht dazu.'
          : '${reports.length} neue Berichte';
  return (
    title:
        title != null ? 'Neues zu: $title' : 'Neues zu einer deiner Aktionen',
    body: body,
  );
}

NotificationText resultText(String? title) => (
      title: 'Geschafft! 🎉',
      body: title != null
          ? 'Die Petition „$title“ hat ihr Ziel erreicht. Du warst dabei.'
          : 'Eine Petition, bei der du mitgemacht hast, hat ihr Ziel '
              'erreicht.',
    );

NotificationText decisionText(String? title) => (
      title: 'Morgen wird entschieden',
      body: title != null
          ? 'Der Rat stimmt morgen darüber ab: $title'
          : 'Morgen wird über etwas abgestimmt, bei dem du mitgemacht hast.',
    );

NotificationText deadlineText(String? title, int daysLeft) => (
      title: 'Noch $daysLeft Tage',
      body: title ?? 'Eine Aktion, die du dir angesehen hast, läuft bald ab.',
    );

NotificationText tookPartText(String? title) => (
      title: 'Abgeschickt?',
      body: title != null
          ? 'Hast du bei „$title“ mitgemacht?'
          : 'Hast du bei der Aktion von gestern mitgemacht?',
    );
