import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class LaravelApiClient {
  final String baseUrl;
  final String? apiToken;
  final Duration timeout;

  LaravelApiClient({
    required this.baseUrl,
    this.apiToken,
    this.timeout = const Duration(seconds: 30),
  });

  /// Headers for API requests
  Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (apiToken != null && apiToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiToken';
    }

    return headers;
  }

  /// Send sales data to Laravel API
  Future<Map<String, dynamic>> sendSalesData({
    required Map<String, dynamic> saleDocument,
    required List<Map<String, dynamic>> saleItems,
    required Map<String, dynamic> companyDetails,
    Map<String, dynamic>? fiscalData,
  }) async {
    try {
      debugPrint('Sending sales data to Laravel API...');

      // Prepare the payload
      final payload = {
        'sale': {
          'document_id': saleDocument['Id'],
          'document_number': saleDocument['DocumentNumber'],
          'date_created': saleDocument['DateCreated'],
          'total': saleDocument['Total'],
          'tax': saleDocument['Tax'],
          'discount': saleDocument['Discount'],
          'customer_id': saleDocument['CustomerId'],
          'user_id': saleDocument['UserId'],
          'status': saleDocument['FiscalStatus'] ?? 'pending',
        },
        'items':
            saleItems.map((item) {
              return {
                'product_id': item['ProductId'],
                'product_name': item['ProductDetails']?['Name'] ?? 'Unknown',
                'quantity': item['Quantity'],
                'price': item['Price'],
                'discount': item['Discount'],
                'tax': item['Tax'],
                'total': item['Total'],
                'tax_id': item['TaxID'],
                'tax_code': item['TaxCode'],
                'tax_percent': item['TaxPercent'],
              };
            }).toList(),
        'company': {
          'name': companyDetails['Name'],
          'address': companyDetails['Address'],
          'phone': companyDetails['Phone'],
          'email': companyDetails['Email'],
          'tax_id': companyDetails['TaxId'],
          'vat_number': companyDetails['VatNumber'],
        },
        'fiscal_data':
            fiscalData != null
                ? {
                  'fiscal_signature': fiscalData['FiscalSignature'],
                  'qr_code': fiscalData['QrCode'],
                  'fiscal_invoice_number': fiscalData['FiscalInvoiceNumber'],
                  'fiscalized_date': fiscalData['FiscalizedDate'],
                  'tax_details': fiscalData['TaxDetails'],
                }
                : null,
        'timestamp': DateTime.now().toIso8601String(),
      };

      debugPrint('Payload: ${jsonEncode(payload)}');

      // Make the API request
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/sales'),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(timeout);

      debugPrint('API Response Status: ${response.statusCode}');
      debugPrint('API Response Body: ${response.body}');

      // Parse response
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final responseData = jsonDecode(response.body);
        return {
          'success': true,
          'message': 'Sales data sent successfully',
          'data': responseData,
        };
      } else {
        final errorData = jsonDecode(response.body);
        return {
          'success': false,
          'message': errorData['message'] ?? 'Failed to send sales data',
          'error': errorData,
          'status_code': response.statusCode,
        };
      }
    } catch (e, stackTrace) {
      debugPrint('Error sending sales data to Laravel API: $e');
      debugPrint('Stack trace: $stackTrace');
      return {
        'success': false,
        'message': 'Exception occurred: ${e.toString()}',
        'error': e.toString(),
      };
    }
  }

  /// Send batch sales data
  Future<Map<String, dynamic>> sendBatchSalesData({
    required List<Map<String, dynamic>> salesData,
  }) async {
    try {
      debugPrint('Sending batch sales data to Laravel API...');

      final payload = {
        'sales': salesData,
        'timestamp': DateTime.now().toIso8601String(),
      };

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/sales/batch'),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(timeout);

      debugPrint('Batch API Response Status: ${response.statusCode}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final responseData = jsonDecode(response.body);
        return {
          'success': true,
          'message': 'Batch sales data sent successfully',
          'data': responseData,
        };
      } else {
        final errorData = jsonDecode(response.body);
        return {
          'success': false,
          'message': errorData['message'] ?? 'Failed to send batch sales data',
          'error': errorData,
          'status_code': response.statusCode,
        };
      }
    } catch (e, stackTrace) {
      debugPrint('Error sending batch sales data: $e');
      debugPrint('Stack trace: $stackTrace');
      return {
        'success': false,
        'message': 'Exception occurred: ${e.toString()}',
        'error': e.toString(),
      };
    }
  }

  /// Update fiscal data for a sale
  Future<Map<String, dynamic>> updateFiscalData({
    required int documentId,
    required Map<String, dynamic> fiscalData,
  }) async {
    try {
      debugPrint('Updating fiscal data for document $documentId...');

      final payload = {
        'document_id': documentId,
        'fiscal_data': fiscalData,
        'timestamp': DateTime.now().toIso8601String(),
      };

      final response = await http
          .put(
            Uri.parse('$baseUrl/api/sales/$documentId/fiscal'),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(timeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final responseData = jsonDecode(response.body);
        return {
          'success': true,
          'message': 'Fiscal data updated successfully',
          'data': responseData,
        };
      } else {
        final errorData = jsonDecode(response.body);
        return {
          'success': false,
          'message': errorData['message'] ?? 'Failed to update fiscal data',
          'error': errorData,
          'status_code': response.statusCode,
        };
      }
    } catch (e, stackTrace) {
      debugPrint('Error updating fiscal data: $e');
      debugPrint('Stack trace: $stackTrace');
      return {
        'success': false,
        'message': 'Exception occurred: ${e.toString()}',
        'error': e.toString(),
      };
    }
  }

  /// Test API connection
  Future<bool> testConnection() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/health'), headers: _headers)
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API connection test failed: $e');
      return false;
    }
  }

  /// Sync all unsynchronized sales
  Future<Map<String, dynamic>> syncUnsyncedSales({
    required List<Map<String, dynamic>> unsyncedSales,
  }) async {
    try {
      debugPrint('Syncing ${unsyncedSales.length} unsynced sales...');

      final results = <Map<String, dynamic>>[];
      int successCount = 0;
      int failureCount = 0;

      for (var sale in unsyncedSales) {
        final result = await sendSalesData(
          saleDocument: sale['document'],
          saleItems: sale['items'],
          companyDetails: sale['company'],
          fiscalData: sale['fiscal_data'],
        );

        results.add({'document_id': sale['document']['Id'], 'result': result});

        if (result['success'] == true) {
          successCount++;
        } else {
          failureCount++;
        }
      }

      return {
        'success': failureCount == 0,
        'message': 'Synced $successCount of ${unsyncedSales.length} sales',
        'success_count': successCount,
        'failure_count': failureCount,
        'results': results,
      };
    } catch (e, stackTrace) {
      debugPrint('Error syncing sales: $e');
      debugPrint('Stack trace: $stackTrace');
      return {
        'success': false,
        'message': 'Exception occurred during sync: ${e.toString()}',
        'error': e.toString(),
      };
    }
  }
}
