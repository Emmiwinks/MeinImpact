class UserProfile {
  const UserProfile({
    required this.topics,
    required this.valueAxes,
    this.region,
  });

  final List<String> topics;
  final Map<String, int> valueAxes;
  final String? region;

  Map<String, Object?> toJson() {
    return {
      'topics': topics,
      'value_axes': valueAxes,
      'region': region,
    };
  }
}
