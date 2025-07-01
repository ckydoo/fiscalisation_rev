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
}
