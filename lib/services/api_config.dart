/// Configuration for Laravel API integration
class ApiConfig {
  // API Base URL - Update this with your Laravel backend URL
  static const String baseUrl = 'http://192.168.1.219:8000';

  // API Token for authentication - Update with your actual token
  // You can generate this in your Laravel backend
  static const String? apiToken =
      '1|q76OxwDIhsBIT5Gq1Ae1SBIljN8FstFyy7kGV2vQ24eb0052';

  // Enable/Disable API sync
  static const bool enableApiSync = true;

  // Request timeout in seconds
  static const int timeoutSeconds = 30;

  // Retry configuration
  static const int maxRetries = 3;
  static const int retryDelaySeconds = 5;

  // Batch sync settings
  static const int batchSize = 10;
  static const bool enableBatchSync = false;

  // Auto-sync settings
  static const bool autoSyncOnFiscalization = true;
  static const bool syncFailedFiscalizations = true;

  /// Validate configuration
  static bool isConfigured() {
    return baseUrl.isNotEmpty && baseUrl != 'http://192.168.1.219:8000';
  }

  /// Get full API URL
  static String getApiUrl(String endpoint) {
    return '$baseUrl$endpoint';
  }
}
