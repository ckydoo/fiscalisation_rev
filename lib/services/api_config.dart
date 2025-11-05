/// Configuration for Laravel API integration
class ApiConfig {
  // API Base URL - Update this with your Laravel backend URL
  static const String baseUrl = 'https://your-laravel-backend.com';

  // API Token for authentication - Update with your actual token
  // You can generate this in your Laravel backend
  static const String? apiToken = 'your-api-token-here';

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
    return baseUrl.isNotEmpty && baseUrl != 'https://your-laravel-backend.com';
  }

  /// Get full API URL
  static String getApiUrl(String endpoint) {
    return '$baseUrl$endpoint';
  }
}
