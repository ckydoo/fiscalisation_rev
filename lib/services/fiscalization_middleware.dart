import 'dart:async';
import 'package:flutter/material.dart';
import 'database_service.dart';
import 'zimra_fiscalization_service.dart';
import 'certificate_manager.dart';
import 'laravel_api_client.dart';

class FiscalizationMiddleware {
  final DatabaseService _dbService;
  final ZimraFiscalizationService _fiscalizationService;
  final CertificateManager _certificateManager;
  final LaravelApiClient? _laravelApiClient;

  Timer? _pollingTimer;
  ValueNotifier<String> statusMessage = ValueNotifier('Initializing...');
  ValueNotifier<String> apiStatusMessage = ValueNotifier('API: Not configured');

  FiscalizationMiddleware(
    this._dbService,
    this._fiscalizationService,
    this._certificateManager, {
    LaravelApiClient? laravelApiClient,
  }) : _laravelApiClient = laravelApiClient;

  void startPolling() {
    statusMessage.value = 'Monitoring Aronium DB for new sales...';
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        final sale = await _dbService.getUnfiscalizedSaleDetails();
        if (sale == null) {
          statusMessage.value = 'No new sales to fiscalize';
          return;
        }

        // Fetch company details
        final companyDetails = await _dbService.getCompanyDetails();
        if (companyDetails == null) {
          statusMessage.value =
              'Error: Company details not found in Aronium DB.';
          return;
        }

        // Fetch currency details
        final currencies = await _dbService.getAllCurrencies();
        final currencyCode =
            currencies.isNotEmpty
                ? currencies.first['Code']
                : 'USD'; // Default to USD if not found

        // Fetch tax details
        final taxes = await _dbService.getAllTaxes();

        // Calculate subtotal from items
        final subtotal = (sale['Items'] as List<Map<String, dynamic>>).fold(
          0.0,
          (sum, item) {
            final price = (item['Price'] as num?)?.toDouble() ?? 0.0;
            final quantity = (item['Quantity'] as num?)?.toDouble() ?? 0.0;
            return sum + (price * quantity);
          },
        );
        debugPrint('Calculated subtotal: $subtotal');

        // Modify tax calculation to ensure proper amounts
        final salesTaxes =
            taxes.map((tax) {
              final taxRate = (tax['Rate'] as num?)?.toDouble() ?? 0;
              final taxAmount = subtotal * (taxRate / 100);

              debugPrint(
                'Tax Calculation - '
                'Rate: $taxRate%, '
                'Taxable Amount: $subtotal, '
                'Tax Amount: $taxAmount',
              );

              return {
                'TaxCode': tax['Code'],
                'TaxPercent': taxRate,
                'Rate': taxRate,
                'TaxID': tax['Id'],
                'Name': tax['Name'] ?? 'Unknown Tax',
                'TaxAmount': taxAmount,
              };
            }).toList();

        // Calculate total
        final totalTaxAmount = salesTaxes.fold(
          0.0,
          (sum, tax) => sum + ((tax['TaxAmount'] as num?)?.toDouble() ?? 0.0),
        );
        final totalWithTax = subtotal + totalTaxAmount;

        // Map payments
        final salesPayments =
            (sale['Payments'] as List<Map<String, dynamic>>?)?.map((payment) {
              return {
                'PaymentTypeId': payment['PaymentTypeId'],
                'Amount': payment['Amount'],
                'PaymentTypeName':
                    payment['PaymentTypeName'] ?? 'Unknown Payment',
              };
            }).toList() ??
            [];

        // Device ID (you can make this configurable)
        const deviceId = 'DEVICE001';

        // Enrich sales lines with tax information
        final enrichedSalesLines =
            (sale['Items'] as List<Map<String, dynamic>>).map((item) {
              final defaultTax = taxes.isNotEmpty ? taxes.first : null;
              final defaultTaxId = defaultTax?['Id'];
              final defaultTaxCode = defaultTax?['Code'];
              final defaultTaxRate =
                  (defaultTax?['Rate'] as num?)?.toDouble() ?? 0.0;

              debugPrint('Enriching item: ${item['ProductDetails']?['Name']}');
              debugPrint(
                'Assigning tax: ID=$defaultTaxId, Code=$defaultTaxCode, Rate=$defaultTaxRate',
              );

              return {
                ...item,
                'TaxID': defaultTaxId,
                'TaxCode': defaultTaxCode,
                'TaxPercent': defaultTaxRate,
              };
            }).toList();

        debugPrint('Total with tax: $totalWithTax');
        debugPrint('Sales payments: $salesPayments');
        debugPrint('Enriched sales lines: $enrichedSalesLines');

        // STEP 1: Fiscalize with ZIMRA
        final result = await _fiscalizationService.fiscalizeTransaction(
          sale,
          enrichedSalesLines,
          salesPayments,
          salesTaxes,
          deviceId as int,
          companyDetails,
          currencyCode,
        );

        // Handle fiscalization result
        if (result['success'] == true) {
          final recordToInsert = {
            'fiscalSignature': result['response']?['fiscalSignature'],
            'qrCode': result['response']?['qrCode'],
            'fiscalInvoiceNumber': result['response']?['fiscalInvoiceNumber'],
            'fiscalError': null,
            'TaxDetails': salesTaxes,
          };

          await _dbService.insertFiscalizedRecord(
            sale['Id'] as int,
            recordToInsert,
          );

          statusMessage.value =
              'Document #${sale['Id']} fiscalized successfully';

          // STEP 2: Send to Laravel API (if configured)
          if (_laravelApiClient != null) {
            apiStatusMessage.value = 'Sending to Laravel API...';

            final apiResult = await _laravelApiClient.sendSalesData(
              saleDocument: sale,
              saleItems: enrichedSalesLines,
              companyDetails: companyDetails,
              fiscalData: {
                'FiscalSignature': result['response']?['fiscalSignature'],
                'QrCode': result['response']?['qrCode'],
                'FiscalInvoiceNumber':
                    result['response']?['fiscalInvoiceNumber'],
                'FiscalizedDate': DateTime.now().toIso8601String(),
                'TaxDetails': salesTaxes,
              },
            );

            if (apiResult['success'] == true) {
              apiStatusMessage.value =
                  'API: Document #${sale['Id']} synced successfully';
              debugPrint('Sales data sent to Laravel API successfully');
            } else {
              apiStatusMessage.value =
                  'API: Failed to sync document #${sale['Id']}';
              debugPrint(
                'Failed to send to Laravel API: ${apiResult['message']}',
              );
              // You might want to queue this for retry later
            }
          } else {
            apiStatusMessage.value = 'API: Not configured';
          }
        } else {
          // Handle fiscalization error
          String errorDetails = result['message'] ?? 'Unknown error';

          if (result['response'] != null) {
            final response = result['response'];
            if (response is Map) {
              errorDetails += '\nDetails: ${response.toString()}';
            }
          }

          final errorRecord = {
            'fiscalSignature': null,
            'qrCode': null,
            'fiscalInvoiceNumber': null,
            'fiscalError': errorDetails,
            'TaxDetails': salesTaxes,
          };

          await _dbService.insertFiscalizedRecord(
            sale['Id'] as int,
            errorRecord,
          );

          statusMessage.value =
              'Error fiscalizing document #${sale['Id']}: $errorDetails';

          debugPrint('Fiscalization failed: $errorDetails');

          // Still try to send to Laravel API with error status (if configured)
          if (_laravelApiClient != null) {
            apiStatusMessage.value = 'Sending error status to API...';

            await _laravelApiClient.sendSalesData(
              saleDocument: {...sale, 'FiscalStatus': 'error'},
              saleItems: enrichedSalesLines,
              companyDetails: companyDetails,
              fiscalData: {
                'FiscalError': errorDetails,
                'TaxDetails': salesTaxes,
              },
            );
          }
        }
      } catch (e, stackTrace) {
        statusMessage.value = 'Error during polling: ${e.toString()}';
        debugPrint('Polling error: $e\n$stackTrace');
      }
    });
  }

  /// Manually sync a specific sale to Laravel API
  Future<Map<String, dynamic>> syncSaleToApi(int documentId) async {
    if (_laravelApiClient == null) {
      return {'success': false, 'message': 'Laravel API client not configured'};
    }

    try {
      // Get the sale details
      final allSales = await _dbService.getAllSalesDetails();
      final sale = allSales.firstWhere(
        (s) => s['Id'] == documentId,
        orElse: () => <String, dynamic>{},
      );

      if (sale.isEmpty) {
        return {'success': false, 'message': 'Sale not found'};
      }

      final companyDetails = await _dbService.getCompanyDetails();
      if (companyDetails == null) {
        return {'success': false, 'message': 'Company details not found'};
      }

      return await _laravelApiClient.sendSalesData(
        saleDocument: sale,
        saleItems: sale['Items'] as List<Map<String, dynamic>>,
        companyDetails: companyDetails,
        fiscalData:
            sale['FiscalStatus'] == 'fiscalized'
                ? {
                  'FiscalSignature': sale['FiscalSignature'],
                  'QrCode': sale['QrCode'],
                  'FiscalInvoiceNumber': sale['FiscalInvoiceNumber'],
                  'FiscalizedDate': sale['FiscalizedDate'],
                  'TaxDetails': sale['TaxDetails'],
                }
                : null,
      );
    } catch (e, stackTrace) {
      debugPrint('Error syncing sale to API: $e\n$stackTrace');
      return {
        'success': false,
        'message': 'Exception occurred: ${e.toString()}',
      };
    }
  }

  /// Test Laravel API connection
  Future<bool> testApiConnection() async {
    if (_laravelApiClient == null) {
      return false;
    }
    return await _laravelApiClient.testConnection();
  }

  void stopPolling() {
    _pollingTimer?.cancel();
    statusMessage.value = 'Polling stopped';
  }

  void dispose() {
    _pollingTimer?.cancel();
    statusMessage.dispose();
    apiStatusMessage.dispose();
  }
}
