import 'dart:async';
import 'package:flutter/material.dart';
import 'database_service.dart';
import 'zimra_fiscalization_service.dart';
import 'certificate_manager.dart';

class FiscalizationMiddleware {
  final DatabaseService _dbService;
  final ZimraFiscalizationService _fiscalizationService;
  final CertificateManager _certificateManager;
  Timer? _pollingTimer;
  ValueNotifier<String> statusMessage = ValueNotifier('Initializing...');

  FiscalizationMiddleware(
    this._dbService,
    this._fiscalizationService,
    this._certificateManager,
  );
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
                'Rate': taxRate, // Add Rate field for display compatibility
                'TaxID': tax['Id'],
                'Name': tax['Name'] ?? 'Tax',
                'TaxAmount': taxAmount,
                'SalesAmountWithTax': subtotal + taxAmount,
              };
            }).toList();

        statusMessage.value = 'Processing document #${sale['Id']}';

        // Allow API calls to proceed even without certificates to see 401 errors
        final deviceId =
            12345; // Use a test device ID since we don't have real certificates

        // Calculate total amount including taxes
        final totalWithTax = salesTaxes.fold(
          subtotal,
          (sum, tax) => sum + (tax['TaxAmount'] as num).toDouble(),
        );

        // Use actual payment data from the sales document or create default if none exists
        List<Map<String, dynamic>> salesPayments = [];

        if (sale['Payments'] != null && (sale['Payments'] as List).isNotEmpty) {
          // Use actual payments from the database
          for (var payment in sale['Payments'] as List<Map<String, dynamic>>) {
            final paymentAmount =
                (payment['Amount'] as num?)?.toDouble() ?? 0.0;
            final paymentTypeId = payment['PaymentTypeId'] as int? ?? 0;

            salesPayments.add({
              'PaymentType': paymentTypeId,
              'Amount': paymentAmount,
              'PaymentMethodName':
                  payment['PaymentTypeDetails']?['Name'] ?? 'Unknown',
            });
          }
        } else {
          // Create a default cash payment for the total amount if no payments exist
          salesPayments = [
            {
              'PaymentType': 0, // Cash payment type
              'Amount': totalWithTax,
              'PaymentMethodName': 'Cash',
            },
          ];
        }

        // Enrich sales lines with tax information
        final enrichedSalesLines =
            (sale['Items'] as List<Map<String, dynamic>>).map((item) {
              // Get the default tax from the first available tax
              final defaultTax = taxes.first;
              final defaultTaxId = defaultTax['Id'] as int;
              final defaultTaxCode = defaultTax['Code'] as String;
              final defaultTaxRate = (defaultTax['Rate'] as num).toDouble();

              debugPrint('Processing item: ${item['ProductDetails']?['Name']}');
              debugPrint(
                'Assigning tax: ID=$defaultTaxId, Code=$defaultTaxCode, Rate=$defaultTaxRate',
              );

              return {
                ...item,
                'TaxID':
                    defaultTaxId, // Use uppercase to match fiscalization service
                'TaxCode': defaultTaxCode,
                'TaxPercent': defaultTaxRate,
              };
            }).toList();

        debugPrint('Total with tax: $totalWithTax');
        debugPrint('Sales payments: $salesPayments');
        debugPrint('Enriched sales lines: $enrichedSalesLines');

        final result = await _fiscalizationService.fiscalizeTransaction(
          sale, // Pass the entire sales document map
          enrichedSalesLines, // Pass the enriched sales lines with tax information
          salesPayments, // Pass the payment details
          salesTaxes, // Pass the calculated sales taxes
          deviceId, // Use test device ID
          companyDetails, // Pass company details
          currencyCode, // Pass currency code
        );

        // Enhanced error handling and logging
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
        } else {
          // Handle different types of errors
          String errorDetails = result['message'] ?? 'Unknown error';

          if (result['errorType'] == 'validation_error') {
            debugPrint('=== VALIDATION ERROR ===');
            debugPrint('Document #${sale['Id']}: $errorDetails');
            if (result['validationErrors'] != null) {
              debugPrint('Validation errors: ${result['validationErrors']}');
            }
            if (result['detailedError'] != null) {
              debugPrint('Detailed error: ${result['detailedError']}');
            }
            debugPrint('========================');
            errorDetails = 'Validation failed: $errorDetails';
          } else if (result['errorType'] == 'bad_request') {
            debugPrint('=== 400 BAD REQUEST ERROR ===');
            debugPrint('Document #${sale['Id']}: $errorDetails');
            if (result['troubleshooting'] != null) {
              debugPrint('Troubleshooting tips:');
              for (String tip in result['troubleshooting']) {
                debugPrint('• $tip');
              }
            }
            debugPrint('============================');
            errorDetails = '400 Bad Request: $errorDetails';
          } else if (result['errorType'] == 'system_error') {
            debugPrint('=== SYSTEM ERROR ===');
            debugPrint('Document #${sale['Id']}: $errorDetails');
            if (result['stackTrace'] != null) {
              debugPrint('Stack trace: ${result['stackTrace']}');
            }
            debugPrint('===================');
            errorDetails = 'System error: $errorDetails';
          }

          final recordToInsert = {
            'fiscalSignature': null,
            'qrCode': null,
            'fiscalInvoiceNumber': null,
            'fiscalError': errorDetails,
            'TaxDetails': salesTaxes,
            'errorType': result['errorType'],
            'validationErrors': result['validationErrors'],
          };
          await _dbService.insertFiscalizedRecord(
            sale['Id'] as int,
            recordToInsert,
          );
          statusMessage.value =
              'Error fiscalizing document #${sale['Id']}: $errorDetails';
        }
      } catch (e) {
        statusMessage.value = 'Error: ${e.toString()}';
      }
    });
  }

  void stopPolling() {
    _pollingTimer?.cancel();
    statusMessage.value = 'Middleware stopped';
  }
}
