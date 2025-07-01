import 'dart:convert';
import 'lib/services/zimra_request_validator.dart';

void main() {
  print('=== TESTING ZIMRA REQUEST VALIDATION ===');

  // Test 1: Valid request structure
  final headers = {
    'Content-Type': 'application/json',
    'DeviceModelName': 'YourAppModel',
    'DeviceModelVersion': '1.0.0',
  };

  final receipt = {
    'receiptType': 'FiscalInvoice',
    'receiptCurrency': 'USD',
    'receiptCounter': 1,
    'receiptGlobalNo': 44,
    'invoiceNo': '44',
    'receiptDate': '2024-01-01T10:00:00',
    'receiptLinesTaxInclusive': true,
    'receiptTotal': 100.0,
    'receiptLines': [
      {
        'receiptLineType': 'Sale',
        'receiptLineNo': 1,
        'receiptLineName': 'Test Item',
        'receiptLineQuantity': 1.0,
        'receiptLineTotal': 100.0,
        'taxID': 1,
      },
    ],
    'receiptTaxes': [
      {'taxID': 1, 'taxAmount': 15.0, 'salesAmountWithTax': 115.0},
    ],
    'receiptPayments': [
      {'moneyTypeCode': 'Cash', 'paymentAmount': 115.0},
    ],
    'receiptDeviceSignature': {
      'hash': 'dGVzdGhhc2g=',
      'signature': 'dGVzdHNpZ25hdHVyZQ==',
    },
  };

  final requestBody = {'Receipt': receipt, 'DeviceModelVersion': '1.0.0'};

  print('Testing valid request structure...');
  final result = ZimraRequestValidator.validateSubmitReceiptRequest(
    headers: headers,
    deviceID: 123,
    requestBody: requestBody,
  );

  if (result.isValid) {
    print('✅ PASS: Valid request structure accepted');
  } else {
    print('❌ FAIL: Valid request rejected');
    print('Errors: ${result.errors}');
  }

  // Test 2: Missing Receipt field
  print('\nTesting missing Receipt field...');
  final invalidRequestBody1 = {'DeviceModelVersion': '1.0.0'};

  final result2 = ZimraRequestValidator.validateSubmitReceiptRequest(
    headers: headers,
    deviceID: 123,
    requestBody: invalidRequestBody1,
  );

  if (!result2.isValid &&
      result2.errors.contains('Missing required top-level field: Receipt')) {
    print('✅ PASS: Missing Receipt field correctly detected');
  } else {
    print('❌ FAIL: Missing Receipt field not detected');
    print('Errors: ${result2.errors}');
  }

  // Test 3: Missing DeviceModelVersion field
  print('\nTesting missing DeviceModelVersion field...');
  final invalidRequestBody2 = {'Receipt': receipt};

  final result3 = ZimraRequestValidator.validateSubmitReceiptRequest(
    headers: headers,
    deviceID: 123,
    requestBody: invalidRequestBody2,
  );

  if (!result3.isValid &&
      result3.errors.contains(
        'Missing required top-level field: DeviceModelVersion',
      )) {
    print('✅ PASS: Missing DeviceModelVersion field correctly detected');
  } else {
    print('❌ FAIL: Missing DeviceModelVersion field not detected');
    print('Errors: ${result3.errors}');
  }

  // Test 4: Missing header
  print('\nTesting missing DeviceModelVersion header...');
  final invalidHeaders = {
    'Content-Type': 'application/json',
    'DeviceModelName': 'YourAppModel',
  };

  final result4 = ZimraRequestValidator.validateSubmitReceiptRequest(
    headers: invalidHeaders,
    deviceID: 123,
    requestBody: requestBody,
  );

  if (!result4.isValid &&
      result4.errors.contains(
        'Missing required HTTP header: DeviceModelVersion',
      )) {
    print('✅ PASS: Missing DeviceModelVersion header correctly detected');
  } else {
    print('❌ FAIL: Missing DeviceModelVersion header not detected');
    print('Errors: ${result4.errors}');
  }

  print('\n=== TESTING COMPLETE ===');
}
