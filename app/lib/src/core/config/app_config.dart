class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  factory AppConfig.fromEnvironment() {
    const configuredBaseUrl = String.fromEnvironment(
      'MEINIMPACT_API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8000',
    );
    return AppConfig(apiBaseUrl: Uri.parse(configuredBaseUrl));
  }

  final Uri apiBaseUrl;
}
