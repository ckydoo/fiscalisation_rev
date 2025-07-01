import 'package:flutter/foundation.dart';
import 'package:fiscalisation_rev/services/zimra_api_client.dart';
import 'package:intl/intl.dart';

class ZimraFiscalizationService {
  final ZimraApiClient _zimraApiClient;
  String?
  _lastFiscalizedReceiptHash; // Stores the hash of the last successfully fiscalized receipt

  ZimraFiscalizationService(this._zimraApiClient);

  Future<Map<String, dynamic>> fiscalizeTransaction(
    Map<String, dynamic> salesDocument,
    List<Map<String, dynamic>> salesLines,
    List<Map<String, dynamic>> salesPayments,
    List<Map<String, dynamic>> salesTaxes,
    int deviceId,
    Map<String, dynamic> companyDetails,
    String currencyCode, // NEW: Add currency code parameter
  ) async {
    try {
      // Validate input parameters
      if (deviceId <= 0) {
        return {
          'success': false,
          'message': 'Invalid deviceId: must be a positive integer',
          'errorType': 'validation_error',
        };
      }

      if (salesDocument['Id'] == null) {
        return {
          'success': false,
          'message': 'Missing required field: salesDocument[Id]',
          'errorType': 'validation_error',
        };
      }

      if (salesDocument['DateCreated'] == null) {
        return {
          'success': false,
          'message': 'Missing required field: salesDocument[DateCreated]',
          'errorType': 'validation_error',
        };
      }

      final documentId = salesDocument['Id'] as int;
      final total = (salesDocument['Total'] as num?)?.toDouble() ?? 0.0;

      // Prepare receipt lines with validation
      final List<Map<String, dynamic>> receiptLines = [];
      for (var line in salesLines) {
        if (line['ProductDetails']?['Name'] == null) {
          return {
            'success': false,
            'message':
                'Missing required field: ProductDetails.Name in salesLines',
            'errorType': 'validation_error',
          };
        }

        final lineTotal = (line['Total'] as num?)?.toDouble() ?? 0.0;
        if (lineTotal < 0) {
          return {
            'success': false,
            'message': 'Invalid line total: must be non-negative',
            'errorType': 'validation_error',
          };
        }

        receiptLines.add({
          'receiptLineType': line['LineType'] == 0 ? 'Sale' : 'Discount',
          'receiptLineNo': line['Id'] ?? 1,
          'receiptLineHSCode': line['HSCode'] ?? '',
          'receiptLineName': line['ProductDetails']?['Name'] ?? 'Unknown Item',
          'receiptLinePrice': (line['Price'] as num?)?.toDouble() ?? 0.0,
          'receiptLineQuantity': (line['Quantity'] as num?)?.toDouble() ?? 0.0,
          'receiptLineTotal': lineTotal,
          'taxCode': line['TaxCode'],
          'taxPercent': line['TaxPercent'],
          'taxID': line['TaxID'],
        });
      }

      // Validate receipt lines
      if (receiptLines.isEmpty) {
        return {
          'success': false,
          'message': 'At least one receipt line is required (RCPT016)',
          'errorType': 'validation_error',
        };
      }

      // Prepare receipt taxes with validation
      final List<Map<String, dynamic>> receiptTaxes = [];
      for (var tax in salesTaxes) {
        if (tax['TaxID'] == null) {
          return {
            'success': false,
            'message': 'Missing required field: TaxID in salesTaxes',
            'errorType': 'validation_error',
          };
        }

        receiptTaxes.add({
          'taxCode': tax['TaxCode'],
          'taxPercent': tax['TaxPercent'],
          'taxID': tax['TaxID'],
          'taxAmount': tax['TaxAmount'],
          'salesAmountWithTax': tax['SalesAmountWithTax'],
        });
      }

      // Validate receipt taxes
      if (receiptTaxes.isEmpty) {
        return {
          'success': false,
          'message': 'At least one tax entry is required (RCPT017)',
          'errorType': 'validation_error',
        };
      }

      // Prepare receipt payments with validation
      final List<Map<String, dynamic>> receiptPayments = [];
      for (var payment in salesPayments) {
        if (payment['PaymentType'] == null) {
          return {
            'success': false,
            'message': 'Missing required field: PaymentType in salesPayments',
            'errorType': 'validation_error',
          };
        }

        receiptPayments.add({
          'moneyTypeCode': _mapPaymentType(payment['PaymentType']),
          'paymentAmount': payment['Amount'],
        });
      }

      // Validate receipt payments
      if (receiptPayments.isEmpty) {
        return {
          'success': false,
          'message': 'At least one payment entry is required (RCPT018)',
          'errorType': 'validation_error',
        };
      }

      // Build device signature
      final deviceSignature = _zimraApiClient.buildReceiptDeviceSignature(
        deviceID: deviceId,
        receiptType: 'FiscalInvoice',
        receiptCurrency: currencyCode,
        receiptGlobalNo: documentId,
        receiptDate: DateTime.parse(salesDocument['DateCreated']),
        receiptTotal: total,
        receiptTaxes: receiptTaxes,
        previousReceiptHash: _lastFiscalizedReceiptHash,
      );

      // Validate company details
      if (companyDetails['TaxNumber']?.isEmpty ?? true) {
        return {
          'success': false,
          'message': 'Missing required field: TaxNumber in companyDetails',
          'errorType': 'validation_error',
        };
      }

      // Build receipt payload
      final receiptPayload = {
        'receiptType': 'FiscalInvoice',
        'receiptCurrency': currencyCode,
        'receiptCounter': _ensureIntegerValue(
          salesDocument['Number'] ?? documentId,
        ),
        'invoiceNo':
            (salesDocument['Number'] ?? documentId.toString()).toString(),
        'receiptGlobalNo': documentId,
        'receiptDate': DateFormat(
          "yyyy-MM-dd'T'HH:mm:ss",
        ).format(DateTime.parse(salesDocument['DateCreated'])),
        'receiptLinesTaxInclusive': true,
        'receiptLines': receiptLines,
        'receiptTaxes': receiptTaxes,
        'receiptPayments': receiptPayments,
        'receiptTotal': total,
        'receiptPrintForm': 'Receipt48',
        'receiptDeviceSignature': deviceSignature,
        'buyerData': {
          'taxpayerID': companyDetails['TaxNumber'],
          'taxpayerName': companyDetails['Name'],
          'taxpayerAddress': {
            'streetName': companyDetails['StreetName'],
            'additionalStreetName': companyDetails['AdditionalStreetName'],
            'buildingNumber': companyDetails['BuildingNumber'],
            'plotIdentification': companyDetails['PlotIdentification'],
            'citySubdivisionName': companyDetails['CitySubdivisionName'],
            'cityName': companyDetails['City'],
            'postalCode': companyDetails['PostalCode'],
            'countrySubentity': companyDetails['CountrySubentity'],
          },
          'taxpayerEmail': companyDetails['Email'],
          'taxpayerPhoneNumber': companyDetails['PhoneNumber'],
        },
      };

      debugPrint('Submitting receipt for DocumentNumber: $documentId');
      debugPrint('Receipt Payload: $receiptPayload');

      final response = await _zimraApiClient.submitReceipt(
        deviceID: deviceId,
        receipt: receiptPayload,
      );

      if (response != null && response['operationID'] != null) {
        debugPrint('Fiscalization successful for DocumentNumber: $documentId');
        _lastFiscalizedReceiptHash = deviceSignature['hash'];
        return {
          'success': true,
          'message': 'Fiscalized successfully',
          'response': response,
        };
      } else {
        final errorMessage = response?['message'] ?? 'Unknown error';
        debugPrint(
          'Fiscalization failed for DocumentNumber: $documentId: $errorMessage',
        );

        // Enhanced error handling for validation and bad request errors
        if (response?['errorType'] == 'validation_error' ||
            response?['errorType'] == 'bad_request') {
          return {
            'success': false,
            'message': errorMessage,
            'errorType': response?['errorType'],
            'validationErrors': response?['validationErrors'],
            'detailedError': response?['detailedError'],
            'troubleshooting': response?['troubleshooting'],
          };
        }

        return {
          'success': false,
          'message': errorMessage,
          'response': response,
        };
      }
    } catch (e, st) {
      debugPrint(
        'Error during fiscalization for Document ID: ${salesDocument['Id']}: $e\n$st',
      );
      return {
        'success': false,
        'message': 'Exception during fiscalization: $e',
        'errorType': 'system_error',
        'stackTrace': st.toString(),
      };
    }
  }

  /// Helper method to ensure a value is converted to an integer
  int _ensureIntegerValue(dynamic value) {
    if (value == null) {
      return 0;
    }
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    if (value is double) {
      return value.toInt();
    }
    // For any other type, try to convert to string first, then to int
    return int.tryParse(value.toString()) ?? 0;
  }

  String _mapPaymentType(int aroniumPaymentType) {
    switch (aroniumPaymentType) {
      case 0:
        return 'Cash';
      case 1:
        return 'Card';
      case 2:
        return 'MobileWallet';
      case 3:
        return 'BankTransfer';
      case 4:
        return 'Credit';
      case 5:
        return 'Coupon';
      default:
        return 'Other';
    }
  }
}
