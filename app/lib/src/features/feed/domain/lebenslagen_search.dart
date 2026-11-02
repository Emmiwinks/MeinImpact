import 'dart:math';

import 'lebenslage.dart';
import 'lebenslagen_catalog.g.dart';

/// On-device search over the catalog's labels and synonyms, tolerant of
/// umlaut spelling ("baecker" finds "bäcker") and small typos ("erziherin").
/// Results are ordered: word starts with the query, then contains it, then
/// one typo away. An empty query returns nothing.
List<Lebenslage> searchLebenslagen(
  String query, {
  List<Lebenslage> catalog = kLebenslagen,
}) {
  final q = _normalize(query);
  if (q.isEmpty) return const [];
  final scored = <(Lebenslage, int)>[];
  for (final item in catalog) {
    final score = _score(q, item);
    if (score != null) scored.add((item, score));
  }
  scored.sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final (item, _) in scored) item];
}

// Lower is better; null = no match.
int? _score(String q, Lebenslage item) {
  final words = [
    for (final text in [item.label, ...item.synonyms])
      ..._normalize(text).split(RegExp(r'[^a-z0-9]+')),
  ].where((w) => w.isNotEmpty);
  int? best;
  void consider(int value) => best = min(best ?? value, value);
  for (final word in words) {
    if (word.startsWith(q)) {
      consider(0);
    } else if (word.contains(q)) {
      consider(1);
    } else if (q.length >= 5 && _withinOneEdit(q, word)) {
      consider(2);
    }
  }
  return best;
}

String _normalize(String text) => text
    .toLowerCase()
    .replaceAll('ä', 'ae')
    .replaceAll('ö', 'oe')
    .replaceAll('ü', 'ue')
    .replaceAll('ß', 'ss')
    .trim();

/// True when [a] and [b] differ by at most one insertion, deletion or
/// substitution, or when [a] is one edit away from a prefix of [b] (so a
/// typo in a partly typed word still matches).
bool _withinOneEdit(String a, String b) {
  for (final candidate in {
    b,
    if (b.length > a.length) b.substring(0, a.length),
  }) {
    if (_editDistanceAtMostOne(a, candidate)) return true;
  }
  return false;
}

bool _editDistanceAtMostOne(String a, String b) {
  if ((a.length - b.length).abs() > 1) return false;
  var i = 0;
  var j = 0;
  var edits = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      i++;
      j++;
      continue;
    }
    if (++edits > 1) return false;
    if (a.length > b.length) {
      i++;
    } else if (b.length > a.length) {
      j++;
    } else {
      i++;
      j++;
    }
  }
  return edits + (a.length - i) + (b.length - j) <= 1;
}
