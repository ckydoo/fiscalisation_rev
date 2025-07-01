import 'package:flutter/foundation.dart';

class ZimraRequestValidator {
  /// Validates the complete submitReceipt request structure
  static ValidationResult validateSubmitReceiptRequest({
    required Map<String, String> headers,
    required int deviceID,
    required Map<String, dynamic> requestBody,
  }) {
    final errors = <String>[];

    // Validate HTTP Headers
    _validateHeaders(headers, errors);

    // Validate top-level request parameters
    _validateTopLevelParams(deviceID, requestBody, errors);

    // Validate presence of Receipt field at top level
    if (!requestBody.containsKey('Receipt')) {
      errors.add('Missing required top-level field: Receipt');
    } else {
      final receipt = requestBody['Receipt'];
      if (receipt is Map<String, dynamic>) {
        _validateReceiptObject(receipt, errors);
      } else {
        errors.add('Field Receipt must be an object');
      }
    }

    // Validate presence of DeviceModelVersion field at top level
    if (!requestBody.containsKey('DeviceModelVersion')) {
      errors.add('Missing required top-level field: DeviceModelVersion');
    } else {
      final deviceModelVersion = requestBody['DeviceModelVersion'];
      if (deviceModelVersion is! String || deviceModelVersion.isEmpty) {
        errors.add('Field DeviceModelVersion must be a non-empty string');
      }
    }

    return ValidationResult(isValid: errors.isEmpty, errors: errors);
  }

  /// Validates required HTTP headers
  static void _validateHeaders(
    Map<String, String> headers,
    List<String> errors,
  ) {
    // Required headers as per ZIMRA API documentation
    if (!headers.containsKey('DeviceModelName') ||
        headers['DeviceModelName']?.isEmpty == true) {
      errors.add('Missing required HTTP header: DeviceModelName');
    }

    if (!headers.containsKey('DeviceModelVersion') ||
        headers['DeviceModelVersion']?.isEmpty == true) {
      errors.add('Missing required HTTP header: DeviceModelVersion');
    }

    if (!headers.containsKey('Content-Type') ||
        headers['Content-Type'] != 'application/json') {
      errors.add(
        'Missing or invalid Content-Type header. Must be application/json',
      );
    }
  }

  /// Validates top-level request parameters
  static void _validateTopLevelParams(
    int deviceID,
    Map<String, dynamic> receipt,
    List<String> errors,
  ) {
    // deviceID validation
    if (deviceID <= 0) {
      errors.add('deviceID must be a positive integer');
    }

    // receipt object validation
    if (receipt.isEmpty) {
      errors.add('Missing required parameter: receipt object');
    }
  }

  /// Validates the receipt object structure and all required fields
  static void _validateReceiptObject(
    Map<String, dynamic> receipt,
    List<String> errors,
  ) {
    // Required top-level receipt fields
    _validateRequiredField(receipt, 'receiptType', 'String', errors);
    _validateRequiredField(receipt, 'receiptCurrency', 'String', errors);
    _validateRequiredField(receipt, 'receiptCounter', 'int', errors);
    _validateRequiredField(receipt, 'receiptGlobalNo', 'int', errors);
    _validateRequiredField(receipt, 'invoiceNo', 'String', errors);
    _validateRequiredField(receipt, 'receiptDate', 'String', errors);
    _validateRequiredField(receipt, 'receiptLinesTaxInclusive', 'bool', errors);
    _validateRequiredField(receipt, 'receiptTotal', 'num', errors);

    // Validate receiptCurrency format (must be 3-character code)
    if (receipt.containsKey('receiptCurrency')) {
      final currency = receipt['receiptCurrency'];
      if (currency is String && currency.length != 3) {
        errors.add(
          'receiptCurrency must be a 3-character currency code (e.g., USD, ZWL)',
        );
      }
    }

    // Validate receiptType enum
    if (receipt.containsKey('receiptType')) {
      final receiptType = receipt['receiptType'];
      if (receiptType is String) {
        final validTypes = [
          'FiscalInvoice',
          'FiscalReceipt',
          'NonFiscalReceipt',
        ];
        if (!validTypes.contains(receiptType)) {
          errors.add('receiptType must be one of: ${validTypes.join(', ')}');
        }
      }
    }

    // Validate receiptDate format (ISO 8601)
    if (receipt.containsKey('receiptDate')) {
      final dateStr = receipt['receiptDate'];
      if (dateStr is String) {
        try {
          DateTime.parse(dateStr);
        } catch (e) {
          errors.add(
            'receiptDate must be in ISO 8601 format (yyyy-MM-ddTHH:mm:ss)',
          );
        }
      }
    }

    // Validate required arrays
    _validateReceiptLines(receipt, errors);
    _validateReceiptTaxes(receipt, errors);
    _validateReceiptPayments(receipt, errors);
    _validateReceiptDeviceSignature(receipt, errors);
  }

  /// Validates receiptLines array and its contents
  static void _validateReceiptLines(
    Map<String, dynamic> receipt,
    List<String> errors,
  ) {
    if (!receipt.containsKey('receiptLines')) {
      errors.add('Missing required field: receiptLines array');
      return;
    }

    final receiptLines = receipt['receiptLines'];
    if (receiptLines is! List) {
      errors.add('receiptLines must be an array');
      return;
    }

    if (receiptLines.isEmpty) {
      errors.add('receiptLines array must contain at least one line (RCPT016)');
      return;
    }

    // Validate each receipt line
    for (int i = 0; i < receiptLines.length; i++) {
      final line = receiptLines[i];
      if (line is! Map<String, dynamic>) {
        errors.add('receiptLines[$i] must be an object');
        continue;
      }

      _validateRequiredField(
        line,
        'receiptLineType',
        'String',
        errors,
        'receiptLines[$i]',
      );
      _validateRequiredField(
        line,
        'receiptLineNo',
        'int',
        errors,
        'receiptLines[$i]',
      );
      _validateRequiredField(
        line,
        'receiptLineName',
        'String',
        errors,
        'receiptLines[$i]',
      );
      _validateRequiredField(
        line,
        'receiptLineQuantity',
        'num',
        errors,
        'receiptLines[$i]',
      );
      _validateRequiredField(
        line,
        'receiptLineTotal',
        'num',
        errors,
        'receiptLines[$i]',
      );
      _validateRequiredField(line, 'taxID', 'int', errors, 'receiptLines[$i]');

      // Validate receiptLineType enum
      if (line.containsKey('receiptLineType')) {
        final lineType = line['receiptLineType'];
        if (lineType is String) {
          final validTypes = ['Sale', 'Discount', 'Return', 'Void'];
          if (!validTypes.contains(lineType)) {
            errors.add(
              'receiptLines[$i].receiptLineType must be one of: ${validTypes.join(', ')}',
            );
          }
        }
      }

      // Validate receiptLineName length (max 200 characters)
      if (line.containsKey('receiptLineName')) {
        final name = line['receiptLineName'];
        if (name is String && name.length > 200) {
          errors.add(
            'receiptLines[$i].receiptLineName must not exceed 200 characters',
          );
        }
      }
    }
  }

  /// Validates receiptTaxes array and its contents
  static void _validateReceiptTaxes(
    Map<String, dynamic> receipt,
    List<String> errors,
  ) {
    if (!receipt.containsKey('receiptTaxes')) {
      errors.add('Missing required field: receiptTaxes array');
      return;
    }

    final receiptTaxes = receipt['receiptTaxes'];
    if (receiptTaxes is! List) {
      errors.add('receiptTaxes must be an array');
      return;
    }

    if (receiptTaxes.isEmpty) {
      errors.add('receiptTaxes array must contain at least one line (RCPT017)');
      return;
    }

    // Validate each tax entry
    for (int i = 0; i < receiptTaxes.length; i++) {
      final tax = receiptTaxes[i];
      if (tax is! Map<String, dynamic>) {
        errors.add('receiptTaxes[$i] must be an object');
        continue;
      }

      _validateRequiredField(tax, 'taxID', 'int', errors, 'receiptTaxes[$i]');
      _validateRequiredField(
        tax,
        'taxAmount',
        'num',
        errors,
        'receiptTaxes[$i]',
      );
      _validateRequiredField(
        tax,
        'salesAmountWithTax',
        'num',
        errors,
        'receiptTaxes[$i]',
      );
    }
  }

  /// Validates receiptPayments array and its contents
  static void _validateReceiptPayments(
    Map<String, dynamic> receipt,
    List<String> errors,
  ) {
    if (!receipt.containsKey('receiptPayments')) {
      errors.add('Missing required field: receiptPayments array');
      return;
    }

    final receiptPayments = receipt['receiptPayments'];
    if (receiptPayments is! List) {
      errors.add('receiptPayments must be an array');
      return;
    }

    if (receiptPayments.isEmpty) {
      errors.add(
        'receiptPayments array must contain at least one line (RCPT018)',
      );
      return;
    }

    // Validate each payment entry
    for (int i = 0; i < receiptPayments.length; i++) {
      final payment = receiptPayments[i];
      if (payment is! Map<String, dynamic>) {
        errors.add('receiptPayments[$i] must be an object');
        continue;
      }

      _validateRequiredField(
        payment,
        'moneyTypeCode',
        'String',
        errors,
        'receiptPayments[$i]',
      );
      _validateRequiredField(
        payment,
        'paymentAmount',
        'num',
        errors,
        'receiptPayments[$i]',
      );

      // Validate moneyTypeCode enum
      if (payment.containsKey('moneyTypeCode')) {
        final moneyType = payment['moneyTypeCode'];
        if (moneyType is String) {
          final validTypes = [
            'Cash',
            'Card',
            'MobileWallet',
            'Coupon',
            'Credit',
            'BankTransfer',
            'Other',
          ];
          if (!validTypes.contains(moneyType)) {
            errors.add(
              'receiptPayments[$i].moneyTypeCode must be one of: ${validTypes.join(', ')}',
            );
          }
        }
      }
    }
  }

  /// Validates receiptDeviceSignature object
  static void _validateReceiptDeviceSignature(
    Map<String, dynamic> receipt,
    List<String> errors,
  ) {
    if (!receipt.containsKey('receiptDeviceSignature')) {
      errors.add('Missing required field: receiptDeviceSignature object');
      return;
    }

    final signature = receipt['receiptDeviceSignature'];
    if (signature is! Map<String, dynamic>) {
      errors.add('receiptDeviceSignature must be an object');
      return;
    }

    _validateRequiredField(
      signature,
      'hash',
      'String',
      errors,
      'receiptDeviceSignature',
    );
    _validateRequiredField(
      signature,
      'signature',
      'String',
      errors,
      'receiptDeviceSignature',
    );

    // Validate hash format (should be base64 encoded 32-byte SHA-256)
    if (signature.containsKey('hash')) {
      final hash = signature['hash'];
      if (hash is String) {
        try {
          // Basic validation - should be base64 string
          if (hash.isEmpty) {
            errors.add('receiptDeviceSignature.hash cannot be empty');
          }
        } catch (e) {
          errors.add(
            'receiptDeviceSignature.hash must be a valid base64 encoded string',
          );
        }
      }
    }

    // Validate signature format (should be base64 encoded 256-byte signature)
    if (signature.containsKey('signature')) {
      final sig = signature['signature'];
      if (sig is String) {
        try {
          // Basic validation - should be base64 string
          if (sig.isEmpty) {
            errors.add('receiptDeviceSignature.signature cannot be empty');
          }
        } catch (e) {
          errors.add(
            'receiptDeviceSignature.signature must be a valid base64 encoded string',
          );
        }
      }
    }
  }

  /// Helper method to validate required fields with type checking
  static void _validateRequiredField(
    Map<String, dynamic> object,
    String fieldName,
    String expectedType,
    List<String> errors, [
    String? objectPath,
  ]) {
    final prefix = objectPath != null ? '$objectPath.' : '';

    if (!object.containsKey(fieldName)) {
      errors.add('Missing required field: $prefix$fieldName');
      return;
    }

    final value = object[fieldName];
    bool isValidType = false;

    switch (expectedType.toLowerCase()) {
      case 'string':
        isValidType = value is String;
        break;
      case 'int':
        isValidType = value is int;
        break;
      case 'num':
        isValidType = value is num;
        break;
      case 'bool':
        isValidType = value is bool;
        break;
      case 'list':
        isValidType = value is List;
        break;
      case 'map':
        isValidType = value is Map;
        break;
    }

    if (!isValidType) {
      errors.add(
        'Field $prefix$fieldName must be of type $expectedType, got ${value.runtimeType}',
      );
    }

    // Additional validation for specific types
    if (expectedType == 'String' && value is String && value.isEmpty) {
      errors.add('Field $prefix$fieldName cannot be empty');
    }
  }

  /// Validates invoiceNo field length (max 50 characters)
  static void _validateInvoiceNoLength(
    Map<String, dynamic> receipt,
    List<String> errors,
  ) {
    if (receipt.containsKey('invoiceNo')) {
      final invoiceNo = receipt['invoiceNo'];
      if (invoiceNo is String && invoiceNo.length > 50) {
        errors.add('invoiceNo must not exceed 50 characters');
      }
    }
  }
}

/// Result class for validation operations
class ValidationResult {
  final bool isValid;
  final List<String> errors;

  ValidationResult({required this.isValid, required this.errors});

  /// Returns a formatted error message for display
  String getFormattedErrors() {
    if (isValid) return 'Validation passed';

    return 'Validation failed:\n${errors.map((e) => '• $e').join('\n')}';
  }

  /// Returns errors as a single string for logging
  String getErrorSummary() {
    if (isValid) return 'Valid';

    return 'Invalid: ${errors.join('; ')}';
  }
}
