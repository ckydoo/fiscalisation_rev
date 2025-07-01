import 'package:flutter_test/flutter_test.dart';
import 'package:fiscalisation_rev/services/zimra_request_validator.dart';

void main() {
  group('ZIMRA Request Validation Tests', () {
    test('Valid request structure should pass validation', () {
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

      final result = ZimraRequestValidator.validateSubmitReceiptRequest(
        headers: headers,
        deviceID: 123,
        requestBody: requestBody,
      );

      expect(
        result.isValid,
        true,
        reason: 'Valid request should pass validation',
      );
    });

    test('Missing Receipt field should fail validation', () {
      final headers = {
        'Content-Type': 'application/json',
        'DeviceModelName': 'YourAppModel',
        'DeviceModelVersion': '1.0.0',
      };

      final requestBody = {'DeviceModelVersion': '1.0.0'};

      final result = ZimraRequestValidator.validateSubmitReceiptRequest(
        headers: headers,
        deviceID: 123,
        requestBody: requestBody,
      );

      expect(
        result.isValid,
        false,
        reason: 'Request without Receipt should fail',
      );
      expect(
        result.errors.contains('Missing required top-level field: Receipt'),
        true,
        reason: 'Should detect missing Receipt field',
      );
    });

    test('Missing DeviceModelVersion field should fail validation', () {
      final headers = {
        'Content-Type': 'application/json',
        'DeviceModelName': 'YourAppModel',
        'DeviceModelVersion': '1.0.0',
      };

      final receipt = {
        'receiptType': 'FiscalInvoice',
        'receiptCurrency': 'USD',
        'receiptCounter': 1,
      };

      final requestBody = {'Receipt': receipt};

      final result = ZimraRequestValidator.validateSubmitReceiptRequest(
        headers: headers,
        deviceID: 123,
        requestBody: requestBody,
      );

      expect(
        result.isValid,
        false,
        reason: 'Request without DeviceModelVersion should fail',
      );
      expect(
        result.errors.contains(
          'Missing required top-level field: DeviceModelVersion',
        ),
        true,
        reason: 'Should detect missing DeviceModelVersion field',
      );
    });

    test('Missing DeviceModelVersion header should fail validation', () {
      final headers = {
        'Content-Type': 'application/json',
        'DeviceModelName': 'YourAppModel',
      };

      final receipt = {
        'receiptType': 'FiscalInvoice',
        'receiptCurrency': 'USD',
        'receiptCounter': 1,
      };

      final requestBody = {'Receipt': receipt, 'DeviceModelVersion': '1.0.0'};

      final result = ZimraRequestValidator.validateSubmitReceiptRequest(
        headers: headers,
        deviceID: 123,
        requestBody: requestBody,
      );

      expect(
        result.isValid,
        false,
        reason: 'Request without DeviceModelVersion header should fail',
      );
      expect(
        result.errors.contains(
          'Missing required HTTP header: DeviceModelVersion',
        ),
        true,
        reason: 'Should detect missing DeviceModelVersion header',
      );
    });
  });
}
