import 'dart:math';

import 'home_location.dart';
import 'opportunity.dart';

/// Every tuning number of ranking by distance, in one place, like
/// [InterestConfig] for interests. The defaults are a starting point.
class LocalityConfig {
  const LocalityConfig({
    this.farPenalty = 0.8,
    this.neighbourhoodBonus = 0.3,
  });

  // Appeal (0-1 scale) a card loses when the place it concerns is far from
  // home: nothing inside its area, then more with every further radius of
  // distance, up to this. Large enough that another city's matters sink
  // below one's own, never removed.
  final double farPenalty;
  // Appeal a neighbourhood's card (Ortschaftsrat, Stadtbezirksbeirat ...)
  // gains when home lies in that neighbourhood: one's own street first.
  final double neighbourhoodBonus;

  /// The appeal [opportunity] gains (or loses) for lying near (or far from)
  /// [home]; 0 for Bund, EU and Land matters, and while home is unknown.
  double adjustment(Opportunity opportunity, HomeLocation? home) {
    final area = opportunity.umkreis;
    if (area == null || home == null) return 0;
    final weight = nearness(area, home);
    final bonus =
        opportunity.reichweite == 'nachbarschaft' ? neighbourhoodBonus : 0.0;
    return bonus * weight - farPenalty * (1 - weight);
  }
}

/// 1 inside [area], halving with every further radius of distance.
double nearness(Umkreis area, HomeLocation home) {
  final beyond = distanceKm(area.lat, area.lon, home.lat, home.lon) - area.km;
  if (beyond <= 0) return 1;
  return pow(0.5, beyond / max(area.km, 0.1)).toDouble();
}

/// Great-circle distance (haversine), as the server computes it.
double distanceKm(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusKm = 6371.0;
  double rad(double degrees) => degrees * pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final h = pow(sin(dLat / 2), 2) +
      cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(dLon / 2), 2);
  return 2 * earthRadiusKm * asin(sqrt(h));
}
