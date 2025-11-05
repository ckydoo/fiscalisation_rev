/// Configuration for Laravel API integration
class ApiConfig {
  // API Base URL - Update this with your Laravel backend URL
  static const String baseUrl = 'http://192.168.1.219:8000';

  // API Token for authentication - Update with your actual token
  // FIXED: Removed extra quote at the end
  static const String? apiToken =
      '2|SZ2lYC5x6n1Gc4v90VxQUOghBrMQwyo35tFI69bQ6ead7200';

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
  /// FIXED: Now checks if token exists, not if baseUrl is different
  static bool isConfigured() {
    return baseUrl.isNotEmpty && apiToken != null && apiToken!.isNotEmpty;
  }

  /// Get full API URL
  static String getApiUrl(String endpoint) {
    return '$baseUrl$endpoint';
  }
}
