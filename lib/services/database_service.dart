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
            // Check if column already exists before adding
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
      orderBy: 'DateCreated ASC',
    );

    final unfiscalized =
        allAroniumSales.where((doc) {
          return !fiscalizedIds.contains(doc['Id']);
        }).toList();

    if (unfiscalized.isEmpty) return null;

    final document = unfiscalized.first;
    final documentId = document['Id'] as int;

    // Fetch document items
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

    // Fetch payment details for the document
    final payments = await _aroniumDatabase.query(
      'Payment',
      where: 'DocumentId = ?',
      whereArgs: [documentId],
    );

    List<Map<String, dynamic>> enrichedPayments = [];
    for (var payment in payments) {
      // Fetch payment type details if available
      final paymentType = await _aroniumDatabase.query(
        'PaymentType',
        where: 'Id = ?',
        whereArgs: [payment['PaymentTypeId']],
        limit: 1,
      );

      enrichedPayments.add({
        ...payment,
        'PaymentTypeDetails': paymentType.isNotEmpty ? paymentType.first : null,
      });
    }

    return {
      ...document,
      'Items': enrichedItems,
      'Payments': enrichedPayments,
      'FiscalStatus': 'pending',
    };
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

  // --- NEW: Fetch Company Details ---
  Future<Map<String, dynamic>?> getCompanyDetails() async {
    // Assuming there's only one company record or you want the first one
    final company = await _aroniumDatabase.query('Company', limit: 1);
    if (company.isNotEmpty) {
      return company.first;
    }
    return null;
  }

  // --- NEW: Fetch Payment Type Details (if needed for dynamic mapping) ---
  Future<List<Map<String, dynamic>>> getAllPaymentTypes() async {
    return await _aroniumDatabase.query('PaymentType');
  }

  // --- NEW: Fetch Currency Details ---
  Future<List<Map<String, dynamic>>> getAllCurrencies() async {
    return await _aroniumDatabase.query('Currency');
  }

  // --- NEW: Fetch Tax Details ---
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

  // Add these methods to your existing DatabaseService class

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
        if (product['CategoryId'] != null) {
          final category = await _aroniumDatabase.query(
            'Category',
            where: 'Id = ?',
            whereArgs: [product['CategoryId']],
            limit: 1,
          );
          if (category.isNotEmpty) {
            enriched['CategoryName'] = category.first['Name'];
          }
        }

        // Get tax if exists
        if (product['TaxId'] != null) {
          final tax = await _aroniumDatabase.query(
            'Tax',
            where: 'Id = ?',
            whereArgs: [product['TaxId']],
            limit: 1,
          );
          if (tax.isNotEmpty) {
            enriched['TaxCode'] = tax.first['Code'];
            enriched['TaxRate'] = tax.first['Rate'];
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

  /// Get all stock levels from Aronium database
  Future<List<Map<String, dynamic>>> getAllStockLevels() async {
    try {
      // Aronium may store inventory in different ways depending on version
      // This is a common structure - adjust based on your Aronium schema

      // Try to get from Inventory table first
      try {
        final inventory = await _aroniumDatabase.query('Inventory');
        if (inventory.isNotEmpty) {
          return inventory;
        }
      } catch (e) {
        debugPrint('Inventory table not found, trying Product table');
      }

      // Fallback: Get stock levels from Product table
      final products = await _aroniumDatabase.query(
        'Product',
        columns: [
          'Id as ProductId',
          'Quantity',
          'ReservedQuantity',
          'ReorderLevel',
          'ReorderQuantity',
          'Location',
        ],
        where: 'TrackInventory = ?',
        whereArgs: [1],
      );

      return products;
    } catch (e) {
      debugPrint('Error getting stock levels: $e');
      return [];
    }
  }

  /// Get all purchases from Aronium database
  Future<List<Map<String, dynamic>>> getAllPurchases() async {
    try {
      // Purchase documents typically have DocumentTypeId = 3 or 4 in Aronium
      // Adjust based on your Aronium configuration
      final purchases = await _aroniumDatabase.query(
        'Document',
        where: 'DocumentTypeId IN (?, ?)',
        whereArgs: [3, 4], // 3 = Purchase Order, 4 = Purchase Invoice
        orderBy: 'DateCreated DESC',
      );

      // Enrich with supplier information
      List<Map<String, dynamic>> enrichedPurchases = [];
      for (var purchase in purchases) {
        Map<String, dynamic> enriched = {...purchase};

        // Get supplier if exists
        if (purchase['PartnerId'] != null) {
          final supplier = await _aroniumDatabase.query(
            'Partner',
            where: 'Id = ?',
            whereArgs: [purchase['PartnerId']],
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
        } else {
          enrichedItems.add(item);
        }
      }

      return enrichedItems;
    } catch (e) {
      debugPrint('Error getting purchase items: $e');
      return [];
    }
  }

  /// Get all Z-Reports from Aronium database
  Future<List<Map<String, dynamic>>> getAllZReports() async {
    try {
      // Z-Reports might be stored in different tables depending on Aronium version
      // Common table names: ZReport, DailyReport, CashRegisterReport

      // Try ZReport table first
      try {
        final reports = await _aroniumDatabase.query(
          'ZReport',
          orderBy: 'ReportDate DESC',
        );
        if (reports.isNotEmpty) {
          return await _enrichZReports(reports);
        }
      } catch (e) {
        debugPrint('ZReport table not found: $e');
      }

      // Try DailyReport table
      try {
        final reports = await _aroniumDatabase.query(
          'DailyReport',
          orderBy: 'ReportDate DESC',
        );
        if (reports.isNotEmpty) {
          return await _enrichZReports(reports);
        }
      } catch (e) {
        debugPrint('DailyReport table not found: $e');
      }

      // Fallback: Generate Z-Reports from sales data
      return await _generateZReportsFromSales();
    } catch (e) {
      debugPrint('Error getting Z-Reports: $e');
      return [];
    }
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

  /// Generate Z-Reports from sales data if no Z-Report table exists
  Future<List<Map<String, dynamic>>> _generateZReportsFromSales() async {
    try {
      // Get all sales grouped by date
      final sales = await _aroniumDatabase.rawQuery('''
        SELECT 
          DATE(DateCreated) as ReportDate,
          COUNT(*) as TotalTransactions,
          SUM(Total) as GrossSales,
          SUM(Discount) as Discounts,
          SUM(Tax) as TotalTax,
          SUM(Total - Discount) as NetSales
        FROM Document
        WHERE DocumentTypeId = 2
        GROUP BY DATE(DateCreated)
        ORDER BY DATE(DateCreated) DESC
      ''');

      // Generate report numbers
      List<Map<String, dynamic>> reports = [];
      for (var i = 0; i < sales.length; i++) {
        final sale = sales[i];
        reports.add({
          'Id': i + 1,
          'ReportDate': sale['ReportDate'],
          'ReportNumber': 'Z-${sale['ReportDate']}',
          'TotalTransactions': sale['TotalTransactions'] ?? 0,
          'TotalItemsSold': 0, // Would need to calculate from items
          'GrossSales': sale['GrossSales'] ?? 0.0,
          'Discounts': sale['Discounts'] ?? 0.0,
          'Returns': 0.0,
          'NetSales': sale['NetSales'] ?? 0.0,
          'TotalTax': sale['TotalTax'] ?? 0.0,
        });
      }

      return reports;
    } catch (e) {
      debugPrint('Error generating Z-Reports from sales: $e');
      return [];
    }
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
}
