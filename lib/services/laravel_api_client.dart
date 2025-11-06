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

      // Map document_number
      final documentNumber =
          saleDocument['DocumentNumber'] ??
          saleDocument['Number']?.toString() ??
          saleDocument['Id']?.toString() ??
          'DOC-${saleDocument['Id']}';

      // Map tax_id
      final taxId =
          companyDetails['TaxId'] ??
          companyDetails['TaxNumber'] ??
          companyDetails['Tax'] ??
          '';

      // Get or find company_id (from previous sync)
      // You'll need to implement this method to get the company_id
      int companyId = await _getCompanyId(taxId);

      // Convert tax_details to JSON string
      String? taxDetailsString;
      if (fiscalData != null && fiscalData['TaxDetails'] != null) {
        if (fiscalData['TaxDetails'] is String) {
          taxDetailsString = fiscalData['TaxDetails'];
        } else {
          taxDetailsString = jsonEncode(fiscalData['TaxDetails']);
        }
      } else if (fiscalData != null && fiscalData['tax_details'] != null) {
        if (fiscalData['tax_details'] is String) {
          taxDetailsString = fiscalData['tax_details'];
        } else {
          taxDetailsString = jsonEncode(fiscalData['tax_details']);
        }
      }

      // ✅ NEW FORMAT - Flat structure (matches fixed SalesController)
      final payload = {
        'document_id': saleDocument['Id'],
        'document_number': documentNumber,
        'company_id': companyId, // ✅ Use existing company_id
        'date_created': saleDocument['DateCreated'],
        'total': saleDocument['Total'],
        'tax': saleDocument['Tax'] ?? 0,
        'discount': saleDocument['Discount'] ?? 0.0,
        'customer_id': saleDocument['CustomerId'],
        'user_id': saleDocument['UserId'],
        'status':
            saleDocument['FiscalStatus'] ??
                    fiscalData?['fiscal_signature'] != null
                ? 'fiscalized'
                : 'error',
        'fiscal_signature':
            fiscalData?['fiscal_signature'] ?? fiscalData?['FiscalSignature'],
        'qr_code': fiscalData?['qr_code'] ?? fiscalData?['QrCode'],
        'fiscal_invoice_number':
            fiscalData?['fiscal_invoice_number'] ??
            fiscalData?['FiscalInvoiceNumber'],
        'fiscalized_at':
            fiscalData != null && fiscalData['fiscal_signature'] != null
                ? (fiscalData['fiscalized_date'] ??
                    fiscalData['FiscalizedDate'] ??
                    DateTime.now().toIso8601String())
                : null,
        'tax_details': taxDetailsString, // ✅ JSON string
        'items':
            saleItems.map((item) {
              return {
                'product_id': item['ProductId'],
                'product_name':
                    item['ProductDetails']?['Name'] ??
                    item['Name'] ??
                    'Unknown',
                'quantity': (item['Quantity'] as num?)?.toDouble() ?? 0.0,
                'price': (item['Price'] as num?)?.toDouble() ?? 0.0,
                'discount': (item['Discount'] as num?)?.toDouble() ?? 0.0,
                'tax': (item['Tax'] as num?)?.toDouble() ?? 0.0,
                'total': (item['Total'] as num?)?.toDouble() ?? 0.0,
                'tax_id': item['TaxID'] ?? item['TaxId'],
                'tax_code': item['TaxCode'],
                'tax_percent': (item['TaxPercent'] as num?)?.toDouble() ?? 0.0,
              };
            }).toList(),
      };

      debugPrint('Sending payload: ${jsonEncode(payload)}');

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

  /// Helper method to get company_id from Laravel
  /// Add this method to your LaravelApiClient class
  Future<int> _getCompanyId(String taxId) async {
    try {
      // First try to get existing company
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/companies?tax_id=$taxId'),
            headers: _headers,
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null &&
            data['data'] is List &&
            (data['data'] as List).isNotEmpty) {
          return data['data'][0]['id'];
        }
      }

      // If not found, this is an error - company should be synced first
      throw Exception('Company not found. Please sync company first.');
    } catch (e) {
      debugPrint('Error getting company_id: $e');
      rethrow;
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

      debugPrint('Update Response Status: ${response.statusCode}');

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

  /// Health check
  Future<Map<String, dynamic>> healthCheck() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/health'), headers: _headers)
          .timeout(timeout);

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        return {
          'success': true,
          'message': 'API is reachable',
          'data': responseData,
        };
      } else {
        return {
          'success': false,
          'message': 'API returned status ${response.statusCode}',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Cannot reach API: ${e.toString()}'};
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
}
