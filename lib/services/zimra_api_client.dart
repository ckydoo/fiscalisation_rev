import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';
import 'package:http/io_client.dart' as http show IOClient;
import 'package:intl/intl.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256r1.dart';
import 'package:pointycastle/signers/ecdsa_signer.dart';
import 'package:pointycastle/signers/rsa_signer.dart';
import 'zimra_request_validator.dart';

class ZimraApiClient {
  static const String _zimraApiBaseUrl = 'https://fdmsapitest.zimra.co.zw';
  static const String _deviceModelName = 'YourAppModel';
  static const String _deviceModelVersion = '1.0.0';

  AsymmetricKey? _signingPrivateKey;
  SecurityContext? _securityContext;

  ZimraApiClient({
    AsymmetricKey? signingPrivateKey,
    SecurityContext? securityContext,
  }) : _signingPrivateKey = signingPrivateKey,
       _securityContext = securityContext;

  void setSigningPrivateKey(AsymmetricKey? key) {
    _signingPrivateKey = key;
  }

  void setSecurityContext(SecurityContext? context) {
    _securityContext = context;
  }

  http.Client _getHttpClient() {
    if (_securityContext != null) {
      final httpClient = HttpClient(context: _securityContext!);
      return http.IOClient(httpClient);
    }
    debugPrint('Warning: Using regular HTTP client (no mutual TLS).');
    return http.Client();
  }

  Map<String, String> _getHeaders({bool includeAuth = true}) {
    return {
      'Content-Type': 'application/json',
      'DeviceModelName': _deviceModelName,
      'DeviceModelVersion': _deviceModelVersion,
    };
  }

  ValidationResult _validateRequest({
    required int deviceID,
    required Map<String, dynamic> receipt,
  }) {
    final headers = _getHeaders();
    final requestBody = {
      'Receipt': receipt,
      'DeviceModelVersion': _deviceModelVersion,
    };
    return ZimraRequestValidator.validateSubmitReceiptRequest(
      headers: headers,
      deviceID: deviceID,
      requestBody: requestBody,
    );
  }

  Future<Map<String, dynamic>?> verifyTaxpayerInformation({
    required int deviceID,
    required String activationKey,
    required String deviceSerialNo,
  }) async {
    final url = Uri.parse('$_zimraApiBaseUrl/api/v1/verifyTaxpayerInformation');
    try {
      final response = await http.post(
        url,
        headers: _getHeaders(includeAuth: false),
        body: json.encode({
          'deviceID': deviceID,
          'activationKey': activationKey,
          'deviceSerialNo': deviceSerialNo,
          'deviceModelName': _deviceModelName,
          'deviceModelVersionNo': _deviceModelVersion,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        debugPrint(
          'verifyTaxpayerInformation failed: ${response.statusCode} - ${response.body}',
        );
        return {'error': true, 'message': response.body};
      }
    } catch (e, st) {
      debugPrint('Error verifying taxpayer information: $e\n$st');
      return {'error': true, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>?> registerDevice({
    required int deviceID,
    required String activationKey,
    required String deviceSerialNo,
    required String certificateRequest,
  }) async {
    final url = Uri.parse('$_zimraApiBaseUrl/api/v1/registerDevice');
    try {
      final response = await http.post(
        url,
        headers: _getHeaders(includeAuth: false),
        body: json.encode({
          'deviceID': deviceID,
          'activationKey': activationKey,
          'deviceSerialNo': deviceSerialNo,
          'certificateRequest': certificateRequest,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        debugPrint(
          'registerDevice failed: ${response.statusCode} - ${response.body}',
        );
        return {'error': true, 'message': response.body};
      }
    } catch (e, st) {
      debugPrint('Error registering device: $e\n$st');
      return {'error': true, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>?> getConfig({required int deviceID}) async {
    final url = Uri.parse('$_zimraApiBaseUrl/api/v1/getConfig');
    try {
      final client = _getHttpClient();
      final response = await client.post(
        url,
        headers: _getHeaders(),
        body: json.encode({'deviceID': deviceID}),
      );
      client.close();

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        debugPrint(
          'getConfig failed: ${response.statusCode} - ${response.body}',
        );
        return {'error': true, 'message': response.body};
      }
    } catch (e, st) {
      debugPrint('Error getting config: $e\n$st');
      return {'error': true, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>?> submitReceipt({
    required int deviceID,
    required Map<String, dynamic> receipt,
  }) async {
    final validationResult = _validateRequest(
      deviceID: deviceID,
      receipt: receipt,
    );

    if (!validationResult.isValid) {
      debugPrint('=== VALIDATION FAILED ===');
      debugPrint('Validation errors: ${validationResult.getErrorSummary()}');
      debugPrint('========================');

      return {
        'status': 'error',
        'message': 'Request validation failed',
        'validationErrors': validationResult.errors,
        'detailedError': validationResult.getFormattedErrors(),
        'errorType': 'validation_error',
      };
    }

    final url = Uri.parse(
      '$_zimraApiBaseUrl/Device/v1/$deviceID/SubmitReceipt',
    );

    // Build the correct request body structure with Receipt and DeviceModelVersion at top level
    final requestBody = {
      'Receipt': receipt,
      'DeviceModelVersion': _deviceModelVersion,
    };

    debugPrint('=== ZIMRA API CLIENT DEBUG ===');
    debugPrint('Request URL: $url');
    debugPrint('Device ID: $deviceID');
    debugPrint('Headers: ${_getHeaders()}');
    debugPrint('Request body: ${json.encode(requestBody)}');
    debugPrint('Using security context: ${_securityContext != null}');
    debugPrint('Validation: PASSED');
    debugPrint('===============================');

    try {
      final client = _getHttpClient();
      final response = await client.post(
        url,
        headers: _getHeaders(),
        body: json.encode(requestBody),
      );
      client.close();

      debugPrint('=== RESPONSE DEBUG ===');
      debugPrint('Status Code: ${response.statusCode}');
      debugPrint('Response Headers: ${response.headers}');
      debugPrint('Response Body: ${response.body}');
      debugPrint('======================');

      if (response.statusCode == 200) {
        debugPrint('SUCCESS: Receipt submitted successfully');
        return json.decode(response.body);
      } else if (response.statusCode == 400) {
        debugPrint('=== 400 BAD REQUEST ERROR ===');
        debugPrint('This indicates a malformed request structure.');
        debugPrint('Response: ${response.body}');
        debugPrint('============================');

        return {
          'status': 'error',
          'message': 'Bad Request - Request structure is malformed',
          'httpStatusCode': 400,
          'serverResponse': response.body,
          'errorType': 'bad_request',
          'troubleshooting': _get400TroubleshootingTips(),
        };
      } else {
        final errorMessage =
            'submitReceipt failed: ${response.statusCode} - ${response.body}';
        debugPrint('ERROR: $errorMessage');
        return {
          'status': 'error',
          'message': 'API Error (${response.statusCode}): ${response.body}',
          'httpStatusCode': response.statusCode,
          'serverResponse': response.body,
          'errorType': 'api_error',
        };
      }
    } catch (e, st) {
      debugPrint('EXCEPTION in submitReceipt: $e');
      debugPrint('Stack trace: $st');
      return {
        'status': 'error',
        'message': 'Network or connection error: $e',
        'errorType': 'network_error',
      };
    }
  }

  List<String> _get400TroubleshootingTips() {
    return [
      'Verify all required HTTP headers are present: DeviceModelName, DeviceModelVersion',
      'Ensure deviceID is a positive integer',
      'Check that receipt object contains all required fields',
      'Verify receiptLines array has at least one item',
      'Verify receiptTaxes array has at least one item',
      'Verify receiptPayments array has at least one item',
      'Check that receiptDeviceSignature object has hash and signature fields',
      'Ensure all enum fields use valid values (receiptType, moneyTypeCode, etc.)',
      'Verify receiptCurrency is a 3-character code (USD, ZWL, etc.)',
      'Check that receiptDate is in ISO 8601 format',
      'Ensure invoiceNo does not exceed 50 characters',
      'Verify receiptLineName does not exceed 200 characters per line',
    ];
  }

  Future<Map<String, dynamic>?> ping({required int deviceID}) async {
    final url = Uri.parse('$_zimraApiBaseUrl/api/v1/ping');
    try {
      final client = _getHttpClient();
      final response = await client.post(
        url,
        headers: _getHeaders(),
        body: json.encode({'deviceID': deviceID}),
      );
      client.close();

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        debugPrint('ping failed: ${response.statusCode} - ${response.body}');
        return {'error': true, 'message': response.body};
      }
    } catch (e, st) {
      debugPrint('Error pinging device: $e\n$st');
      return {'error': true, 'message': e.toString()};
    }
  }

  String generateSHA256Hash(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return hex.encode(digest.bytes);
  }

  String _signHashWithPrivateKey(String hashHex) {
    if (_signingPrivateKey == null) {
      debugPrint('Warning: Private key not loaded. Returning dummy signature.');
      return base64Encode(
        Uint8List.fromList(List.generate(256, (index) => index % 256)),
      );
    }

    final hashBytes = Uint8List.fromList(hex.decode(hashHex));
    Signature? signature;

    if (_signingPrivateKey is RSAPrivateKey) {
      final signer = RSASigner(SHA256Digest(), '06092a864886f70d01010b');
      signer.init(
        true,
        PrivateKeyParameter<RSAPrivateKey>(_signingPrivateKey as RSAPrivateKey),
      );
      signature = signer.generateSignature(hashBytes);
      return base64Encode((signature as RSASignature).bytes!);
    } else if (_signingPrivateKey is ECPrivateKey) {
      final ecDomainParams = ECCurve_secp256r1();
      final signer = ECDSASigner(SHA256Digest(), ecDomainParams as Mac?);
      signer.init(
        true,
        PrivateKeyParameter<ECPrivateKey>(_signingPrivateKey as ECPrivateKey),
      );
      signature = signer.generateSignature(hashBytes);
      final ecSignature = signature as ECSignature;
      final rBytes = _bigIntToPaddedBytes(ecSignature.r!, 32);
      final sBytes = _bigIntToPaddedBytes(ecSignature.s!, 32);
      final combinedBytes = Uint8List(rBytes.length + sBytes.length);
      combinedBytes.setRange(0, rBytes.length, rBytes);
      combinedBytes.setRange(rBytes.length, combinedBytes.length, sBytes);
      return base64Encode(combinedBytes);
    } else {
      throw Exception("Unsupported private key type for signing.");
    }
  }

  Uint8List _bigIntToPaddedBytes(BigInt value, int length) {
    final result = Uint8List(length);
    int i = length - 1;
    BigInt temp = value;
    while (temp > BigInt.zero && i >= 0) {
      result[i--] = (temp & BigInt.from(0xFF)).toInt();
      temp >>= 8;
    }
    return result;
  }

  Map<String, dynamic> buildReceiptDeviceSignature({
    required int deviceID,
    required String receiptType,
    required String receiptCurrency,
    required int receiptGlobalNo,
    required DateTime receiptDate,
    required double receiptTotal,
    required List<Map<String, dynamic>> receiptTaxes,
    String? previousReceiptHash,
  }) {
    final StringBuffer concatenatedString = StringBuffer();
    concatenatedString.write(deviceID);
    concatenatedString.write(receiptType.toUpperCase());
    concatenatedString.write(receiptCurrency.toUpperCase());
    concatenatedString.write(receiptGlobalNo);
    concatenatedString.write(
      DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(receiptDate),
    );
    concatenatedString.write((receiptTotal * 100).toInt());

    receiptTaxes.sort((a, b) {
      final taxIdComparison = (a['taxID'] as int).compareTo(b['taxID'] as int);
      if (taxIdComparison != 0) return taxIdComparison;
      return (a['taxCode'] ?? '').compareTo(b['taxCode'] ?? '');
    });

    for (var tax in receiptTaxes) {
      concatenatedString.write(tax['taxCode'] ?? '');
      concatenatedString.write(
        (tax['taxPercent'] as num?)?.toStringAsFixed(2) ?? '',
      );
      concatenatedString.write((tax['taxAmount'] * 100).toInt());
      concatenatedString.write((tax['salesAmountWithTax'] * 100).toInt());
    }

    concatenatedString.write(previousReceiptHash ?? '');

    final hash = generateSHA256Hash(concatenatedString.toString());
    final signature = _signHashWithPrivateKey(hash);

    return {'hash': base64Encode(hex.decode(hash)), 'signature': signature};
  }
}
