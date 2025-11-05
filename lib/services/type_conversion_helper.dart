/// Helper functions for safe type conversions
class TypeConversionHelper {
  /// Safely convert dynamic value to int
  static int toInt(dynamic value, {int defaultValue = 0}) {
    if (value == null) return defaultValue;

    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      return parsed ?? defaultValue;
    }

    return defaultValue;
  }

  /// Safely convert dynamic value to double
  static double toDouble(dynamic value, {double defaultValue = 0.0}) {
    if (value == null) return defaultValue;

    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed ?? defaultValue;
    }

    return defaultValue;
  }

  /// Safely convert dynamic value to String
  static String toStringValue(dynamic value, {String defaultValue = ''}) {
    if (value == null) return defaultValue;
    return value.toString();
  }

  /// Safely convert dynamic value to bool
  static bool toBool(dynamic value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;

    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) {
      final lower = value.toLowerCase();
      if (lower == 'true' || lower == '1') return true;
      if (lower == 'false' || lower == '0') return false;
    }

    return defaultValue;
  }
}
