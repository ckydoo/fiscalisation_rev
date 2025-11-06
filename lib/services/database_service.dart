import 'dart:convert';
import 'dart:io';
import 'dart:convert' as convert;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseService {
  late Database _aroniumDatabase;
  late Database _fiscalTrackerDatabase;
  String? aroniumDbPath;
  String? fiscalTrackerDbPath;

  DatabaseService({required this.aroniumDbPath});

  Future<void> initDatabases() async {
    // Initialize fiscal tracker database
    final directory = await getApplicationSupportDirectory();
    fiscalTrackerDbPath = p.join(directory.path, 'sim_pos_fiscal_tracker.db');

    _fiscalTrackerDatabase = await databaseFactoryFfi.openDatabase(
      fiscalTrackerDbPath!,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE FiscalizedDocuments (
              AroniumDocumentId INTEGER PRIMARY KEY NOT NULL,
              FiscalSignature TEXT,
              QrCode TEXT,
              FiscalInvoiceNumber TEXT,
              FiscalError TEXT,
              TaxDetails TEXT,
              FiscalizedDate TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            final columns = await db.rawQuery(
              "PRAGMA table_info(FiscalizedDocuments)",
            );
            final columnNames =
                columns.map((col) => col['name'] as String).toList();
            if (!columnNames.contains('TaxDetails')) {
              await db.execute(
                'ALTER TABLE FiscalizedDocuments ADD COLUMN TaxDetails TEXT',
              );
            }
          }
        },
      ),
    );

    // Open Aronium's database (read-only)
    if (!await databaseFactoryFfi.databaseExists(aroniumDbPath!)) {
      throw Exception('Aronium POS database not found at: $aroniumDbPath');
    }
    _aroniumDatabase = await databaseFactoryFfi.openDatabase(
      aroniumDbPath!,
      options: OpenDatabaseOptions(readOnly: true),
    );
  }

  Future<void> insertFiscalizedRecord(
    int aroniumDocumentId,
    Map<String, dynamic> fiscalDetails,
  ) async {
    final taxDetailsJson =
        fiscalDetails['TaxDetails'] != null
            ? jsonEncode(fiscalDetails['TaxDetails'])
            : null;

    await _fiscalTrackerDatabase.insert('FiscalizedDocuments', {
      'AroniumDocumentId': aroniumDocumentId,
      'FiscalSignature': fiscalDetails['fiscalSignature'],
      'QrCode': fiscalDetails['qrCode'],
      'FiscalInvoiceNumber': fiscalDetails['fiscalInvoiceNumber'],
      'FiscalError': fiscalDetails['fiscalError'],
      'TaxDetails': taxDetailsJson,
    });
  }

  Future<List<Map<String, dynamic>>> getAllSalesDetails() async {
    final salesDocs = await _aroniumDatabase.query(
      'Document',
      where: 'DocumentTypeId = ?',
      whereArgs: [2],
      orderBy: 'DateCreated DESC',
    );

    final fiscalizedRecords = await _fiscalTrackerDatabase.query(
      'FiscalizedDocuments',
    );
    final fiscalizedMap = {
      for (var rec in fiscalizedRecords) rec['AroniumDocumentId'] as int: rec,
    };

    List<Map<String, dynamic>> allSalesDetails = [];
    for (var document in salesDocs) {
      final documentId = document['Id'] as int;
      final items = await _aroniumDatabase.query(
        'DocumentItem',
        where: 'DocumentId = ?',
        whereArgs: [documentId],
      );

      List<Map<String, dynamic>> enrichedItems = [];
      for (var item in items) {
        final product = await _aroniumDatabase.query(
          'Product',
          where: 'Id = ?',
          whereArgs: [item['ProductId']],
          limit: 1,
        );
        if (product.isNotEmpty) {
          enrichedItems.add({...item, 'ProductDetails': product.first});
        }
      }
      final payments = await _aroniumDatabase.query(
        'Payment',
        where: 'DocumentId = ?',
        whereArgs: [documentId],
      ); // Enrich payments with payment type details
      final enrichedPayments = <Map<String, dynamic>>[];
      for (var payment in payments) {
        final paymentTypeId = payment['PaymentTypeId'];

        // Get payment type details
        final paymentType = await _aroniumDatabase.query(
          'PaymentType',
          where: 'Id = ?',
          whereArgs: [paymentTypeId],
          limit: 1,
        );

        enrichedPayments.add({
          'PaymentTypeId': paymentTypeId,
          'Amount': (payment['Amount'] as num?)?.toDouble() ?? 0.0,
          'Date': payment['Date'],
          'PaymentTypeName':
              paymentType.isNotEmpty ? paymentType.first['Name'] : 'Unknown',
          'PaymentTypeCode':
              paymentType.isNotEmpty ? paymentType.first['Code'] : null,
        });
      }

      Map<String, dynamic> mergedDocument = {...document};
      if (fiscalizedMap.containsKey(documentId)) {
        final fiscalData = fiscalizedMap[documentId]!;
        mergedDocument['FiscalStatus'] =
            fiscalData['FiscalError'] != null ? 'error' : 'fiscalized';
        mergedDocument['FiscalSignature'] = fiscalData['FiscalSignature'];
        mergedDocument['QrCode'] = fiscalData['QrCode'];
        mergedDocument['FiscalInvoiceNumber'] =
            fiscalData['FiscalInvoiceNumber'];
        mergedDocument['FiscalError'] = fiscalData['FiscalError'];

        // Parse and include tax details if available
        if (fiscalData['TaxDetails'] != null) {
          try {
            final decodedTaxDetails =
                jsonDecode(fiscalData['TaxDetails'] as String) as List;
            mergedDocument['TaxDetails'] =
                decodedTaxDetails
                    .map((tax) => Map<String, dynamic>.from(tax))
                    .toList();
          } catch (e) {
            mergedDocument['TaxDetails'] = <Map<String, dynamic>>[];
          }
        } else {
          mergedDocument['TaxDetails'] = <Map<String, dynamic>>[];
        }
      } else {
        mergedDocument['FiscalStatus'] = 'pending';
        mergedDocument['TaxDetails'] = [];
      }

      allSalesDetails.add({...mergedDocument, 'Items': enrichedItems});
    }
    return allSalesDetails;
  }

  // --- NEW: Fetch Payment Type Details (if needed for dynamic mapping) ---
  Future<List<Map<String, dynamic>>> getAllPaymentTypes() async {
    return await _aroniumDatabase.query('PaymentType');
  }

  /// Enrich Z-Reports with additional data
  Future<List<Map<String, dynamic>>> _enrichZReports(
    List<Map<String, dynamic>> reports,
  ) async {
    List<Map<String, dynamic>> enriched = [];

    for (var report in reports) {
      Map<String, dynamic> enrichedReport = {...report};

      // Get device information if DeviceId exists
      if (report['DeviceId'] != null) {
        try {
          final device = await _aroniumDatabase.query(
            'Device',
            where: 'Id = ?',
            whereArgs: [report['DeviceId']],
            limit: 1,
          );
          if (device.isNotEmpty) {
            enrichedReport['DeviceName'] = device.first['Name'];
          }
        } catch (e) {
          debugPrint('Error getting device info: $e');
        }
      }

      enriched.add(enrichedReport);
    }

    return enriched;
  }

  /// Get Z-Report for a specific date
  Future<Map<String, dynamic>?> getZReportForDate(DateTime date) async {
    try {
      final dateStr = date.toIso8601String().split('T')[0];

      try {
        final report = await _aroniumDatabase.query(
          'ZReport',
          where: 'DATE(ReportDate) = ?',
          whereArgs: [dateStr],
          limit: 1,
        );

        if (report.isNotEmpty) {
          return report.first;
        }
      } catch (e) {
        debugPrint('ZReport table query failed: $e');
      }

      // Fallback: Generate from sales
      final sales = await _aroniumDatabase.rawQuery(
        '''
        SELECT 
          COUNT(*) as TotalTransactions,
          SUM(Total) as GrossSales,
          SUM(Discount) as Discounts,
          SUM(Tax) as TotalTax,
          SUM(Total - Discount) as NetSales
        FROM Document
        WHERE DocumentTypeId = 2 AND DATE(DateCreated) = ?
      ''',
        [dateStr],
      );

      if (sales.isNotEmpty && sales.first['TotalTransactions'] != null) {
        return {
          'ReportDate': dateStr,
          'ReportNumber': 'Z-$dateStr',
          'TotalTransactions': sales.first['TotalTransactions'] ?? 0,
          'GrossSales': sales.first['GrossSales'] ?? 0.0,
          'Discounts': sales.first['Discounts'] ?? 0.0,
          'NetSales': sales.first['NetSales'] ?? 0.0,
          'TotalTax': sales.first['TotalTax'] ?? 0.0,
        };
      }

      return null;
    } catch (e) {
      debugPrint('Error getting Z-Report for date: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getUnfiscalizedSaleDetails() async {
    final fiscalizedIds =
        (await _fiscalTrackerDatabase.query(
          'FiscalizedDocuments',
          columns: ['AroniumDocumentId'],
        )).map((e) => e['AroniumDocumentId']).toList();

    final allAroniumSales = await _aroniumDatabase.query(
      'Document',
      where: 'DocumentTypeId = ?',
      whereArgs: [2],
    );

    final unfiscalizedSales =
        allAroniumSales
            .where((sale) => !fiscalizedIds.contains(sale['Id']))
            .toList();

    if (unfiscalizedSales.isEmpty) {
      return null;
    }

    final sale = unfiscalizedSales.first;
    final saleId = sale['Id'] as int;

    final items = await _aroniumDatabase.query(
      'DocumentItem',
      where: 'DocumentId = ?',
      whereArgs: [saleId],
    );

    final detailedItems = <Map<String, dynamic>>[];
    for (var item in items) {
      final productId = item['ProductId'];
      final productDetails = await _aroniumDatabase.query(
        'Product',
        where: 'Id = ?',
        whereArgs: [productId],
        limit: 1,
      );

      if (productDetails.isNotEmpty) {
        final product = productDetails.first;

        // Get tax information for the product
        final productTaxes = await _aroniumDatabase.query(
          'ProductTax',
          where: 'ProductId = ?',
          whereArgs: [productId],
        );

        double taxRate = 0.0;
        String taxCode = 'A';

        if (productTaxes.isNotEmpty) {
          final taxId = productTaxes.first['TaxId'];
          final taxDetails = await _aroniumDatabase.query(
            'Tax',
            where: 'Id = ?',
            whereArgs: [taxId],
            limit: 1,
          );

          if (taxDetails.isNotEmpty) {
            taxRate = (taxDetails.first['Rate'] as num?)?.toDouble() ?? 0.0;
            taxCode = taxDetails.first['Code']?.toString() ?? 'A';
          }
        }

        detailedItems.add({
          'ProductId': productId,
          'ProductDetails': product,
          'Name': product['Name'] ?? 'Unknown Product',
          'Quantity': (item['Quantity'] as num?)?.toDouble() ?? 0.0,
          'Price': (item['Price'] as num?)?.toDouble() ?? 0.0,
          'Discount': (item['Discount'] as num?)?.toDouble() ?? 0.0,
          'Total': (item['Total'] as num?)?.toDouble() ?? 0.0,
          'TaxRate': taxRate,
          'TaxCode': taxCode,
        });
      }
    }
    final payments = await _aroniumDatabase.query(
      'Payment',
      where: 'DocumentId = ?',
      whereArgs: [saleId],
    );
    final enrichedPayments = <Map<String, dynamic>>[];
    for (var payment in payments) {
      final paymentTypeId = payment['PaymentTypeId'];

      // Get payment type details
      final paymentType = await _aroniumDatabase.query(
        'PaymentType',
        where: 'Id = ?',
        whereArgs: [paymentTypeId],
        limit: 1,
      );

      enrichedPayments.add({
        'PaymentTypeId': paymentTypeId,
        'Amount': (payment['Amount'] as num?)?.toDouble() ?? 0.0,
        'Date': payment['Date'],
        'PaymentTypeName':
            paymentType.isNotEmpty ? paymentType.first['Name'] : 'Unknown',
        'PaymentTypeCode':
            paymentType.isNotEmpty ? paymentType.first['Code'] : null,
      });
    }

    return {
      'Id': saleId,
      'Number': sale['Number'],
      'Date': sale['Date'],
      'DateCreated': sale['DateCreated'],
      'Total': (sale['Total'] as num?)?.toDouble() ?? 0.0,
      'Discount': (sale['Discount'] as num?)?.toDouble() ?? 0.0,
      'CustomerId': sale['CustomerId'],
      'UserId': sale['UserId'],
      'Items': detailedItems,
      'Payments': enrichedPayments,
    };
  }

  Future<void> saveFiscalizationResult({
    required int aroniumDocumentId,
    required String fiscalSignature,
    required String qrCode,
    required String fiscalInvoiceNumber,
    String? taxDetails,
  }) async {
    await _fiscalTrackerDatabase.insert('FiscalizedDocuments', {
      'AroniumDocumentId': aroniumDocumentId,
      'FiscalSignature': fiscalSignature,
      'QrCode': qrCode,
      'FiscalInvoiceNumber': fiscalInvoiceNumber,
      'TaxDetails': taxDetails,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveFiscalizationError({
    required int aroniumDocumentId,
    required String error,
  }) async {
    await _fiscalTrackerDatabase.insert('FiscalizedDocuments', {
      'AroniumDocumentId': aroniumDocumentId,
      'FiscalError': error,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getCompanyDetails() async {
    final companies = await _aroniumDatabase.query('Company', limit: 1);
    return companies.isEmpty ? null : companies.first;
  }

  Future<List<Map<String, dynamic>>> getAllCurrencies() async {
    return await _aroniumDatabase.query('Currency');
  }

  Future<List<Map<String, dynamic>>> getAllTaxes() async {
    final taxes = await _aroniumDatabase.query(
      'Tax',
      where: 'IsEnabled = ?',
      whereArgs: [1],
    );
    return taxes;
  }

  Future<void> close() async {
    await _aroniumDatabase.close();
    await _fiscalTrackerDatabase.close();
  }

  /// Get all products from Aronium database
  Future<List<Map<String, dynamic>>> getAllProducts() async {
    try {
      final products = await _aroniumDatabase.query(
        'Product',
        orderBy: 'Name ASC',
      );

      // Enrich with category and tax information
      List<Map<String, dynamic>> enrichedProducts = [];
      for (var product in products) {
        Map<String, dynamic> enriched = {...product};

        // Get category if exists
        if (product['ProductGroupId'] != null) {
          final category = await _aroniumDatabase.query(
            'ProductGroup',
            where: 'Id = ?',
            whereArgs: [product['ProductGroupId']],
            limit: 1,
          );
          if (category.isNotEmpty) {
            enriched['CategoryName'] = category.first['Name'];
          }
        }

        // Get tax if exists - using ProductTax junction table
        final productTaxes = await _aroniumDatabase.query(
          'ProductTax',
          where: 'ProductId = ?',
          whereArgs: [product['Id']],
          limit: 1,
        );

        if (productTaxes.isNotEmpty) {
          final taxId = productTaxes.first['TaxId'];
          final tax = await _aroniumDatabase.query(
            'Tax',
            where: 'Id = ?',
            whereArgs: [taxId],
            limit: 1,
          );
          if (tax.isNotEmpty) {
            enriched['TaxCode'] = tax.first['Code'];
            enriched['TaxRate'] = tax.first['Rate'];
            enriched['TaxId'] = tax.first['Id'];
          }
        }

        enrichedProducts.add(enriched);
      }

      return enrichedProducts;
    } catch (e) {
      debugPrint('Error getting products: $e');
      return [];
    }
  }

  /// Get all stock levels from Aronium database using the Stock table
  Future<List<Map<String, dynamic>>> getAllStockLevels() async {
    try {
      final stockQuery = '''
      SELECT 
        s.ProductId,
        s.WarehouseId,
        COALESCE(s.Quantity, 0) as Quantity,
        COALESCE(sc.ReorderPoint, 0) as ReorderLevel,
        COALESCE(sc.PreferredQuantity, 0) as ReorderQuantity,
        0 as ReservedQuantity,
        NULL as Location
      FROM Stock s
      LEFT JOIN StockControl sc ON sc.ProductId = s.ProductId
      WHERE s.Quantity IS NOT NULL
    ''';

      final stocks = await _aroniumDatabase.rawQuery(stockQuery);

      debugPrint('Stock records from Aronium: ${stocks.length}');
      if (stocks.isNotEmpty) {
        final totalQty = stocks.fold<double>(
          0,
          (sum, s) => sum + ((s['Quantity'] as num?)?.toDouble() ?? 0),
        );
        debugPrint('Total quantity across all products: $totalQty');

        // Show first 5 non-zero stocks
        final nonZero = stocks
            .where((s) => ((s['Quantity'] as num?)?.toDouble() ?? 0) > 0)
            .take(5);

        if (nonZero.isNotEmpty) {
          debugPrint('Sample non-zero stocks:');
          nonZero.forEach((s) {
            debugPrint('  Product ${s['ProductId']}: ${s['Quantity']}');
          });
        } else {
          debugPrint('⚠️ WARNING: All stock quantities are zero!');
        }
      }

      return stocks;
    } catch (e) {
      debugPrint('Error getting stock levels: $e');

      // Fallback query
      try {
        final basicStocks = await _aroniumDatabase.query('Stock');
        debugPrint('Fallback: Retrieved ${basicStocks.length} stock records');

        return basicStocks.map((stock) {
          return {
            'ProductId': stock['ProductId'],
            'WarehouseId': stock['WarehouseId'],
            'Quantity': stock['Quantity'] ?? 0,
            'ReorderLevel': null,
            'ReorderQuantity': null,
            'ReservedQuantity': 0,
            'Location': null,
          };
        }).toList();
      } catch (e2) {
        debugPrint('Fallback also failed: $e2');
        return [];
      }
    }
  }

  /// Get all purchases from Aronium database
  Future<List<Map<String, dynamic>>> getAllPurchases() async {
    try {
      // Purchase documents - check your DocumentType table for exact IDs
      // Common: 1=Sales, 2=Sales Invoice, 3=Purchase Order, 4=Purchase Invoice
      final purchases = await _aroniumDatabase.query(
        'Document',
        where: 'DocumentTypeId IN (3, 4)',
        orderBy: 'DateCreated DESC',
      );

      // Enrich with supplier information
      List<Map<String, dynamic>> enrichedPurchases = [];
      for (var purchase in purchases) {
        Map<String, dynamic> enriched = {...purchase};

        // Get supplier if exists (Customer table is used for both customers and suppliers)
        if (purchase['CustomerId'] != null) {
          final supplier = await _aroniumDatabase.query(
            'Customer',
            where: 'Id = ?',
            whereArgs: [purchase['CustomerId']],
            limit: 1,
          );
          if (supplier.isNotEmpty) {
            enriched['SupplierId'] = supplier.first['Id'];
            enriched['SupplierName'] = supplier.first['Name'];
          }
        }

        enrichedPurchases.add(enriched);
      }

      return enrichedPurchases;
    } catch (e) {
      debugPrint('Error getting purchases: $e');
      return [];
    }
  }

  /// Get purchase items for a specific purchase document
  Future<List<Map<String, dynamic>>> getPurchaseItems(int documentId) async {
    try {
      final items = await _aroniumDatabase.query(
        'DocumentItem',
        where: 'DocumentId = ?',
        whereArgs: [documentId],
      );

      // Enrich with product information
      List<Map<String, dynamic>> enrichedItems = [];
      for (var item in items) {
        final product = await _aroniumDatabase.query(
          'Product',
          where: 'Id = ?',
          whereArgs: [item['ProductId']],
          limit: 1,
        );

        if (product.isNotEmpty) {
          enrichedItems.add({
            ...item,
            'ProductName': product.first['Name'],
            'ProductCode': product.first['Code'],
          });
        }
      }

      return enrichedItems;
    } catch (e) {
      debugPrint('Error getting purchase items: $e');
      return [];
    }
  }

  /// Get Z-Reports from Aronium database (fixed to use correct column names)
  Future<List<Map<String, dynamic>>> getAllZReports() async {
    try {
      // First try the ZReport table with correct column name
      try {
        final zReports = await _aroniumDatabase.query(
          'ZReport',
          orderBy: 'DateCreated DESC',
        );

        if (zReports.isNotEmpty) {
          // Enrich with calculated totals from associated documents
          List<Map<String, dynamic>> enrichedReports = [];

          for (var report in zReports) {
            final fromDocId = report['FromDocumentId'] as int;
            final toDocId = report['ToDocumentId'] as int;

            // Get all sales in this Z-Report range
            final salesQuery = '''
              SELECT 
                COUNT(*) as TotalTransactions,
                SUM(Total) as GrossSales,
                SUM(Discount) as Discounts,
                SUM(Total - Discount) as NetSales
              FROM Document
              WHERE DocumentTypeId = 2
              AND Id >= ? AND Id <= ?
            ''';

            final totals = await _aroniumDatabase.rawQuery(salesQuery, [
              fromDocId,
              toDocId,
            ]);

            // Get tax totals from DocumentItemTax
            final taxQuery = '''
              SELECT SUM(dit.Amount) as TotalTax
              FROM DocumentItemTax dit
              INNER JOIN DocumentItem di ON di.Id = dit.DocumentItemId
              INNER JOIN Document d ON d.Id = di.DocumentId
              WHERE d.DocumentTypeId = 2
              AND d.Id >= ? AND d.Id <= ?
            ''';

            final taxTotals = await _aroniumDatabase.rawQuery(taxQuery, [
              fromDocId,
              toDocId,
            ]);

            enrichedReports.add({
              'Id': report['Id'],
              'Number': report['Number'],
              'ReportDate':
                  report['DateCreated'], // Note: using DateCreated as ReportDate
              'FromDocumentId': fromDocId,
              'ToDocumentId': toDocId,
              'TotalTransactions': totals.first['TotalTransactions'] ?? 0,
              'GrossSales':
                  (totals.first['GrossSales'] as num?)?.toDouble() ?? 0.0,
              'Discounts':
                  (totals.first['Discounts'] as num?)?.toDouble() ?? 0.0,
              'TotalTax':
                  (taxTotals.first['TotalTax'] as num?)?.toDouble() ?? 0.0,
              'NetSales': (totals.first['NetSales'] as num?)?.toDouble() ?? 0.0,
            });
          }

          return enrichedReports;
        }
      } catch (e) {
        debugPrint('ZReport table query failed: $e');
      }

      // Fallback: Generate Z-Reports from sales data
      debugPrint('Generating Z-Reports from sales data...');
      return await _generateZReportsFromSales();
    } catch (e) {
      debugPrint('Error getting Z-Reports: $e');
      return [];
    }
  }

  /// Generate Z-Reports from sales data (fixed to calculate tax correctly)
  Future<List<Map<String, dynamic>>> _generateZReportsFromSales() async {
    try {
      final salesQuery = '''
        SELECT 
          DATE(DateCreated) as ReportDate,
          COUNT(*) as TotalTransactions,
          SUM(Total) as GrossSales,
          SUM(Discount) as Discounts,
          SUM(Total - Discount) as NetSales
        FROM Document
        WHERE DocumentTypeId = 2
        GROUP BY DATE(DateCreated)
        ORDER BY DATE(DateCreated) DESC
      ''';

      final dailyTotals = await _aroniumDatabase.rawQuery(salesQuery);

      // For each day, calculate tax from DocumentItemTax table
      List<Map<String, dynamic>> reports = [];
      for (var day in dailyTotals) {
        final date = day['ReportDate'];

        // Get tax totals for this day
        final taxQuery = '''
          SELECT SUM(dit.Amount) as TotalTax
          FROM DocumentItemTax dit
          INNER JOIN DocumentItem di ON di.Id = dit.DocumentItemId
          INNER JOIN Document d ON d.Id = di.DocumentId
          WHERE d.DocumentTypeId = 2
          AND DATE(d.DateCreated) = ?
        ''';

        final taxTotals = await _aroniumDatabase.rawQuery(taxQuery, [date]);

        reports.add({
          'ReportDate': date,
          'TotalTransactions': day['TotalTransactions'],
          'GrossSales': (day['GrossSales'] as num?)?.toDouble() ?? 0.0,
          'Discounts': (day['Discounts'] as num?)?.toDouble() ?? 0.0,
          'TotalTax': (taxTotals.first['TotalTax'] as num?)?.toDouble() ?? 0.0,
          'NetSales': (day['NetSales'] as num?)?.toDouble() ?? 0.0,
        });
      }

      return reports;
    } catch (e) {
      debugPrint('Error generating Z-Reports from sales: $e');
      return [];
    }
  }
}
