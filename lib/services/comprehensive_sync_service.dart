import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'database_service.dart';

class ComprehensiveSyncService {
  final DatabaseService _dbService;
  final String baseUrl;
  final String? apiToken;
  final Duration timeout;

  // Track last sync times
  DateTime? lastProductSync;
  DateTime? lastStockSync;
  DateTime? lastPurchaseSync;
  DateTime? lastSaleSync;
  DateTime? lastZReportSync;

  ComprehensiveSyncService({
    required DatabaseService dbService,
    required this.baseUrl,
    this.apiToken,
    this.timeout = const Duration(seconds: 30),
  }) : _dbService = dbService;

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

  /// Generic POST request
  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl$endpoint'),
            headers: _headers,
            body: jsonEncode(data),
          )
          .timeout(timeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      } else {
        throw Exception('API Error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('POST Error to $endpoint: $e');
      rethrow;
    }
  }

  /// Generic GET request
  Future<Map<String, dynamic>> _get(
    String endpoint, {
    Map<String, dynamic>? queryParams,
  }) async {
    try {
      var uri = Uri.parse('$baseUrl$endpoint');
      if (queryParams != null) {
        uri = uri.replace(
          queryParameters: queryParams.map((k, v) => MapEntry(k, v.toString())),
        );
      }

      final response = await http.get(uri, headers: _headers).timeout(timeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      } else {
        throw Exception('API Error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('GET Error from $endpoint: $e');
      rethrow;
    }
  }

  /// Get or create company in Laravel

  Future<int> getOrCreateCompany(Map<String, dynamic> companyDetails) async {
    try {
      // Extract tax_id from different possible field names
      final taxId =
          companyDetails['TaxId'] ??
          companyDetails['TaxNumber'] ??
          companyDetails['tax_id'];

      if (taxId == null || taxId.toString().isEmpty) {
        throw Exception('Company tax_id is required');
      }

      // Prepare company data
      final companyData = {
        'name': companyDetails['Name'] ?? 'Unknown Company',
        'tax_id': taxId.toString(),
        'vat_number':
            companyDetails['VatNumber'] ?? companyDetails['TaxNumber'],
        'address': companyDetails['Address'],
        'phone': companyDetails['PhoneNumber'] ?? companyDetails['Phone'],
        'email': companyDetails['Email'],
      };

      debugPrint('Getting or creating company with tax_id: $taxId');

      // Use the atomic getOrCreate endpoint
      final response = await _post('/api/companies/get-or-create', companyData);

      final companyId = response['data']['id'];
      final wasCreated = response['created'] ?? false;

      debugPrint(
        wasCreated
            ? '✓ Created new company: $companyId - ${companyData['name']}'
            : '✓ Found existing company: $companyId - ${companyData['name']}',
      );

      return companyId;
    } catch (e) {
      debugPrint('Error getting/creating company: $e');
      rethrow;
    }
  }

  /// Sync all entities in sequence
  Future<Map<String, dynamic>> syncAll({
    int? companyId,
    Map<String, dynamic>? companyDetails,
    bool forceSync = false,
  }) async {
    final results = <String, dynamic>{
      'success': true,
      'synced': {},
      'errors': {},
    };

    try {
      // 0. Get or create company if needed
      int actualCompanyId;
      if (companyId != null) {
        actualCompanyId = companyId;
      } else if (companyDetails != null) {
        actualCompanyId = await getOrCreateCompany(companyDetails);
      } else {
        throw Exception('Either companyId or companyDetails must be provided');
      }

      debugPrint('Using company ID: $actualCompanyId');

      // 1. Sync Products first (other entities depend on products)
      final productResult = await syncProducts(
        companyId: actualCompanyId,
        forceSync: forceSync,
      );
      results['synced']['products'] = productResult;

      // 2. Sync Stock levels
      final stockResult = await syncStocks(
        companyId: actualCompanyId,
        forceSync: forceSync,
      );
      results['synced']['stocks'] = stockResult;

      // 3. Sync Purchases
      final purchaseResult = await syncPurchases(
        companyId: actualCompanyId,
        forceSync: forceSync,
      );
      results['synced']['purchases'] = purchaseResult;

      // 4. Sync Sales
      final saleResult = await syncSales(
        companyId: actualCompanyId,
        forceSync: forceSync,
      );
      results['synced']['sales'] = saleResult;

      // 5. Sync Z-Reports
      final zReportResult = await syncZReports(
        companyId: actualCompanyId,
        forceSync: forceSync,
      );
      results['synced']['z_reports'] = zReportResult;
    } catch (e) {
      results['success'] = false;
      results['errors']['general'] = e.toString();
    }

    return results;
  }

  /// Sync products from Aronium to Laravel
  Future<Map<String, dynamic>> syncProducts({
    required int companyId,
    bool forceSync = false,
  }) async {
    try {
      // Get all products from Aronium
      final aroniumProducts = await _dbService.getAllProducts();

      if (aroniumProducts.isEmpty) {
        return {'count': 0, 'message': 'No products to sync'};
      }

      // Transform products for Laravel API
      final productsToSync =
          aroniumProducts.map((product) {
            return {
              'aronium_product_id': product['Id'],
              'company_id': companyId,
              'name': product['Name'] ?? 'Unnamed Product',
              'code': product['Code'],
              'barcode': product['Barcode'],
              'description': product['Description'],
              'price': (product['Price'] as num?)?.toDouble() ?? 0.0,
              'cost': (product['Cost'] as num?)?.toDouble(),
              'category_id': product['CategoryId'],
              'category_name': product['CategoryName'],
              'tax_id': product['TaxId'],
              'tax_code': product['TaxCode'],
              'tax_percent': (product['TaxRate'] as num?)?.toDouble() ?? 0.0,
              'unit': product['Unit'],
              'is_active': (product['IsEnabled'] ?? 1) == 1,
              'track_inventory': (product['TrackInventory'] ?? 1) == 1,
            };
          }).toList();

      // Sync to Laravel API in batches
      final response = await _post('/api/products/sync-batch', {
        'products': productsToSync,
      });

      lastProductSync = DateTime.now();

      return {
        'count': response['synced_count'] ?? 0,
        'synced_ids': response['synced_ids'] ?? [],
        'errors': response['errors'] ?? [],
      };
    } catch (e) {
      debugPrint('Error syncing products: $e');
      rethrow;
    }
  }

  /// Sync stock levels from Aronium to Laravel
  Future<Map<String, dynamic>> syncStocks({
    required int companyId,
    bool forceSync = false,
  }) async {
    try {
      final aroniumStocks = await _dbService.getAllStockLevels();

      // ✅ ADD THIS DEBUG
      debugPrint('=== STOCK SYNC DEBUG ===');
      debugPrint('Aronium stocks retrieved: ${aroniumStocks.length}');

      if (aroniumStocks.isEmpty) {
        return {'count': 0, 'message': 'No stock data to sync'};
      }

      final productsResponse = await _get(
        '/api/products',
        queryParams: {'company_id': companyId, 'per_page': 1000},
      );

      final productMap = <int, int>{};
      for (var product in productsResponse['data']) {
        productMap[product['aronium_product_id']] = product['id'];
      }

      debugPrint('Product mapping created: ${productMap.length} products');

      final stocksToSync =
          aroniumStocks
              .where((stock) => productMap.containsKey(stock['ProductId']))
              .map((stock) {
                final quantity = (stock['Quantity'] as num?)?.toDouble() ?? 0.0;

                // ✅ ADD THIS DEBUG
                if (quantity > 0) {
                  debugPrint(
                    'Stock for Product ${stock['ProductId']}: $quantity',
                  );
                }

                return {
                  'product_id': productMap[stock['ProductId']],
                  'company_id': companyId,
                  'quantity': quantity,
                  'available_quantity': quantity, // ← Should equal quantity
                  'reserved_quantity':
                      (stock['ReservedQuantity'] as num?)?.toDouble() ?? 0.0,
                  'reorder_level': (stock['ReorderLevel'] as num?)?.toDouble(),
                  'reorder_quantity':
                      (stock['ReorderQuantity'] as num?)?.toDouble(),
                  'location': stock['Location'],
                };
              })
              .toList();

      debugPrint('Stocks to sync: ${stocksToSync.length}');
      debugPrint(
        'First stock to sync: ${stocksToSync.isNotEmpty ? stocksToSync.first : "none"}',
      );
      debugPrint('=== END STOCK SYNC DEBUG ===');
      if (stocksToSync.isEmpty) {
        return {'count': 0, 'message': 'No matching products for stock sync'};
      }

      // Sync to Laravel API
      final response = await _post('/api/stocks/sync-batch', {
        'stocks': stocksToSync,
      });

      lastStockSync = DateTime.now();

      return {
        'count': response['synced_count'] ?? 0,
        'synced_ids': response['synced_ids'] ?? [],
      };
    } catch (e) {
      debugPrint('Error syncing stocks: $e');
      rethrow;
    }
  }

  /// Sync purchases from Aronium to Laravel
  Future<Map<String, dynamic>> syncPurchases({
    required int companyId,
    bool forceSync = false,
  }) async {
    try {
      // Get all purchase documents from Aronium
      final aroniumPurchases = await _dbService.getAllPurchases();

      if (aroniumPurchases.isEmpty) {
        return {'count': 0, 'message': 'No purchases to sync'};
      }

      // Transform purchases for Laravel API
      final purchasesToSync = await Future.wait(
        aroniumPurchases.map((purchase) async {
          // Get purchase items
          final items = await _dbService.getPurchaseItems(purchase['Id']);

          return {
            'aronium_document_id': purchase['Id'],
            'document_number':
                purchase['DocumentNumber'] ?? 'PO-${purchase['Id']}',
            'company_id': companyId,
            'date_created':
                purchase['DateCreated'] ?? DateTime.now().toIso8601String(),
            'supplier_id': purchase['SupplierId'],
            'supplier_name': purchase['SupplierName'],
            'subtotal': (purchase['Subtotal'] as num?)?.toDouble() ?? 0.0,
            'tax': (purchase['Tax'] as num?)?.toDouble() ?? 0.0,
            'discount': (purchase['Discount'] as num?)?.toDouble() ?? 0.0,
            'total': (purchase['Total'] as num?)?.toDouble() ?? 0.0,
            'user_id': purchase['UserId'],
            'status': _mapPurchaseStatus(purchase['StatusId']),
            'notes': purchase['Notes'],
            'items':
                items.map((item) {
                  return {
                    'aronium_product_id': item['ProductId'],
                    'product_name': item['ProductName'] ?? 'Unknown',
                    'product_code': item['ProductCode'],
                    'quantity': (item['Quantity'] as num?)?.toDouble() ?? 0.0,
                    'cost': (item['Cost'] as num?)?.toDouble() ?? 0.0,
                    'discount': (item['Discount'] as num?)?.toDouble() ?? 0.0,
                    'tax': (item['Tax'] as num?)?.toDouble() ?? 0.0,
                    'total': (item['Total'] as num?)?.toDouble() ?? 0.0,
                  };
                }).toList(),
          };
        }),
      );

      // Sync to Laravel API
      final response = await _post('/api/purchases/sync-batch', {
        'purchases': purchasesToSync,
      });

      lastPurchaseSync = DateTime.now();

      return {
        'count': response['synced_count'] ?? 0,
        'synced_ids': response['synced_ids'] ?? [],
        'errors': response['errors'] ?? [],
      };
    } catch (e) {
      debugPrint('Error syncing purchases: $e');
      rethrow;
    }
  }

  /// Sync sales (already implemented, but included here for completeness)
  Future<Map<String, dynamic>> syncSales({
    required int companyId,
    bool forceSync = false,
  }) async {
    try {
      // This should use your existing syncSale method
      // but adapted for batch syncing if needed
      final allSales = await _dbService.getAllSalesDetails();

      if (allSales.isEmpty) {
        return {'count': 0, 'message': 'No sales to sync'};
      }

      // Only sync fiscalized sales
      final fiscalizedSales =
          allSales.where((sale) {
            return sale['FiscalStatus'] == 'fiscalized';
          }).toList();

      int syncedCount = 0;
      final errors = [];

      for (var sale in fiscalizedSales) {
        try {
          await _syncSingleSale(sale, companyId);
          syncedCount++;
        } catch (e) {
          errors.add({'document_id': sale['Id'], 'error': e.toString()});
        }
      }

      lastSaleSync = DateTime.now();

      return {'count': syncedCount, 'errors': errors};
    } catch (e) {
      debugPrint('Error syncing sales: $e');
      rethrow;
    }
  }

  /// Sync Z-Reports from Aronium to Laravel
  Future<Map<String, dynamic>> syncZReports({
    required int companyId,
    bool forceSync = false,
  }) async {
    try {
      // Get Z-Reports from Aronium
      final aroniumReports = await _dbService.getAllZReports();

      if (aroniumReports.isEmpty) {
        return {'count': 0, 'message': 'No Z-Reports to sync'};
      }

      // Transform Z-Reports for Laravel API
      final reportsToSync =
          aroniumReports.map((report) {
            // Parse payment breakdown if available
            Map<String, dynamic>? paymentBreakdown;
            if (report['PaymentBreakdown'] != null) {
              try {
                paymentBreakdown = jsonDecode(report['PaymentBreakdown']);
              } catch (e) {
                debugPrint('Error parsing payment breakdown: $e');
              }
            }

            // Parse tax breakdown if available
            List<dynamic>? taxBreakdown;
            if (report['TaxBreakdown'] != null) {
              try {
                taxBreakdown = jsonDecode(report['TaxBreakdown']);
              } catch (e) {
                debugPrint('Error parsing tax breakdown: $e');
              }
            }

            return {
              'aronium_report_id': report['Id'],
              'company_id': companyId,
              'report_date':
                  report['ReportDate'] ?? DateTime.now().toIso8601String(),
              'report_number': report['ReportNumber'] ?? 'Z-${report['Id']}',
              'device_id': report['DeviceId'],
              'device_name': report['DeviceName'],
              'total_transactions': report['TotalTransactions'] ?? 0,
              'total_items_sold': report['TotalItemsSold'] ?? 0,
              'gross_sales': (report['GrossSales'] as num?)?.toDouble() ?? 0.0,
              'discounts': (report['Discounts'] as num?)?.toDouble() ?? 0.0,
              'returns': (report['Returns'] as num?)?.toDouble() ?? 0.0,
              'net_sales': (report['NetSales'] as num?)?.toDouble() ?? 0.0,
              'total_tax': (report['TotalTax'] as num?)?.toDouble() ?? 0.0,
              'payment_breakdown': paymentBreakdown,
              'tax_breakdown': taxBreakdown,
              'opening_cash': (report['OpeningCash'] as num?)?.toDouble(),
              'closing_cash': (report['ClosingCash'] as num?)?.toDouble(),
              'expected_cash': (report['ExpectedCash'] as num?)?.toDouble(),
              'cash_difference': (report['CashDifference'] as num?)?.toDouble(),
              'opened_at': report['OpenedAt'],
              'closed_at': report['ClosedAt'],
              'opened_by': report['OpenedBy'],
              'closed_by': report['ClosedBy'],
            };
          }).toList();

      // Sync to Laravel API
      final response = await _post('/api/z-reports/sync-batch', {
        'reports': reportsToSync,
      });

      lastZReportSync = DateTime.now();

      return {
        'count': response['synced_count'] ?? 0,
        'synced_ids': response['synced_ids'] ?? [],
        'errors': response['errors'] ?? [],
      };
    } catch (e) {
      debugPrint('Error syncing Z-Reports: $e');
      rethrow;
    }
  }

  /// Helper method to sync a single sale (from existing implementation)
  Future<void> _syncSingleSale(Map<String, dynamic> sale, int companyId) async {
    // Convert tax_details to JSON string if it's an object/array
    String? taxDetailsString;
    if (sale['TaxDetails'] != null) {
      if (sale['TaxDetails'] is String) {
        taxDetailsString = sale['TaxDetails'];
      } else {
        // Convert object/array to JSON string
        taxDetailsString = jsonEncode(sale['TaxDetails']);
      }
    }

    // Transform sale for Laravel API
    final saleData = {
      'document_id': sale['Id'],
      'document_number': sale['DocumentNumber'] ?? 'INV-${sale['Id']}',
      'company_id': companyId,
      'date_created': sale['DateCreated'] ?? DateTime.now().toIso8601String(),
      'total': (sale['Total'] as num?)?.toDouble() ?? 0.0,
      'tax': (sale['Tax'] as num?)?.toDouble() ?? 0.0,
      'discount': (sale['Discount'] as num?)?.toDouble() ?? 0.0,
      'customer_id': sale['CustomerId'],
      'user_id': sale['UserId'],
      'status': sale['FiscalStatus'] ?? 'fiscalized',
      'fiscal_signature': sale['FiscalSignature'],
      'qr_code': sale['QrCode'],
      'fiscal_invoice_number': sale['FiscalInvoiceNumber'],
      'fiscalized_at': sale['FiscalizedAt'] ?? DateTime.now().toIso8601String(),
      'tax_details': taxDetailsString, // ✅ Now a JSON string
      'items':
          (sale['Items'] as List<dynamic>?)?.map((item) {
            return {
              'product_id': item['ProductId'],
              'product_name':
                  item['ProductDetails']?['Name'] ?? item['Name'] ?? 'Unknown',
              'quantity': (item['Quantity'] as num?)?.toDouble() ?? 0.0,
              'price': (item['Price'] as num?)?.toDouble() ?? 0.0,
              'discount': (item['Discount'] as num?)?.toDouble() ?? 0.0,
              'tax': (item['Tax'] as num?)?.toDouble() ?? 0.0,
              'total': (item['Total'] as num?)?.toDouble() ?? 0.0,
              'tax_id': item['TaxId'],
              'tax_code': item['TaxCode'],
              'tax_percent': (item['TaxPercent'] as num?)?.toDouble() ?? 0.0,
            };
          }).toList() ??
          [],
    };

    debugPrint('Syncing sale: ${saleData['document_number']}');

    await _post('/api/sales', saleData);
  }

  /// Helper method to map purchase status
  String _mapPurchaseStatus(int? statusId) {
    switch (statusId) {
      case 1:
        return 'pending';
      case 2:
        return 'received';
      case 3:
        return 'cancelled';
      default:
        return 'pending';
    }
  }
}
