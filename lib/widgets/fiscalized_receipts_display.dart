import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';
import '../services/receipt_print_service.dart';

class FiscalizedReceiptsDisplay extends StatelessWidget {
  final Stream<List<Map<String, dynamic>>> salesStream;
  final Map<String, dynamic> companyDetails;

  const FiscalizedReceiptsDisplay({
    super.key,
    required this.salesStream,
    required this.companyDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Company Header
            _buildCompanyHeader(context),
            const SizedBox(height: 20),

            // Receipts List Title
            Text(
              'Recent Fiscalized Receipts',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),

            // Receipts List
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: salesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No receipts found'));
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    final receipt = snapshot.data![index];
                    return _buildReceiptCard(context, receipt);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompanyHeader(BuildContext context) {
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                companyDetails['Name'] ?? 'Company Name',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[800],
                ),
              ),
            ),
            const Divider(),
            if (companyDetails['TaxNumber'] != null)
              Text('Tax Number: ${companyDetails['TaxNumber']}'),
            if (companyDetails['Address'] != null)
              Text('Address: ${companyDetails['Address']}'),
            if (companyDetails['City'] != null)
              Text('City: ${companyDetails['City']}'),
            if (companyDetails['PostalCode'] != null &&
                companyDetails['CountrySubentity'] != null)
              Text(
                '${companyDetails['PostalCode']}, ${companyDetails['CountrySubentity']}',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptCard(BuildContext context, Map<String, dynamic> receipt) {
    final isFiscalized = receipt['FiscalStatus'] == 'fiscalized';
    final isError = receipt['FiscalStatus'] == 'error';
    final total = (receipt['TotalAmount'] as num?)?.toDouble() ?? 0.0;
    final items = (receipt['Items'] as List<dynamic>?) ?? [];
    final qrCode = receipt['QrCode'] as String?;
    final taxDetails =
        (receipt['TaxDetails'] as List<dynamic>?)
            ?.map((tax) => tax as Map<String, dynamic>)
            .toList() ??
        [];

    // Calculate tax amounts
    double subtotal = 0.0;
    double totalTax = 0.0;

    // Calculate from items if available
    if (items.isNotEmpty) {
      subtotal = items.fold(0.0, (sum, item) {
        final price = (item['Price'] as num?)?.toDouble() ?? 0.0;
        final quantity = (item['Quantity'] as num?)?.toDouble() ?? 0.0;
        return sum + (price * quantity);
      });

      // Calculate tax from items if tax details are not available
      if (taxDetails.isEmpty) {
        // For pending receipts, calculate tax based on the default tax rate
        // Since we know from debug logs that there's a 15% tax rate
        const defaultTaxRate =
            15.0; // This should ideally come from a configuration
        totalTax = subtotal * (defaultTaxRate / 100);
        debugPrint(
          'Calculated tax for pending receipt: $totalTax (${defaultTaxRate}% of $subtotal)',
        );
      }
    }

    // Use tax details if available
    if (taxDetails.isNotEmpty) {
      totalTax = taxDetails.fold(0.0, (sum, tax) {
        final taxAmount = (tax['TaxAmount'] as num?)?.toDouble() ?? 0.0;
        return sum + taxAmount;
      });
    }

    // Calculate total from subtotal and tax
    final calculatedTotal = subtotal + totalTax;

    final date =
        receipt['DateCreated'] != null
            ? DateFormat(
              'dd MMM yyyy HH:mm',
            ).format(DateTime.parse(receipt['DateCreated']))
            : '';

    return Card(
      color:
          isFiscalized
              ? Colors.green.shade50
              : isError
              ? Colors.red.shade50
              : null,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Receipt header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Receipt #${receipt['Number'] ?? 'N/A'}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (date.isNotEmpty)
                      Text(
                        date,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                  ],
                ),
                Chip(
                  label: Text(
                    receipt['FiscalStatus'].toString().toUpperCase(),
                    style: TextStyle(
                      color:
                          isFiscalized
                              ? Colors.green.shade800
                              : isError
                              ? Colors.red.shade800
                              : Colors.orange.shade800,
                      fontSize: 12,
                    ),
                  ),
                  backgroundColor:
                      isFiscalized
                          ? Colors.green.shade100
                          : isError
                          ? Colors.red.shade100
                          : Colors.orange.shade100,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Items list
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${item['Quantity']} x ${item['ProductDetails']?['Name'] ?? 'Item'}',
                      ),
                    ),
                    Text(
                      NumberFormat.currency(symbol: '\$').format(
                        ((item['Price'] as num?)?.toDouble() ?? 0.0) *
                            ((item['Quantity'] as num?)?.toDouble() ?? 0.0),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 20),

            // Tax breakdown
            if (taxDetails.isNotEmpty) ...[
              ...taxDetails.map(
                (tax) => Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${tax['Name'] ?? 'Tax'} (${(tax['Rate'] as num?)?.toStringAsFixed(0) ?? '0'}%)',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      Text(
                        NumberFormat.currency(
                          symbol: '\$',
                        ).format((tax['TaxAmount'] as num?)?.toDouble() ?? 0.0),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ] else if (!isFiscalized) ...[
              // Show pending tax calculation
              Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'VAT (15%)',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    Text(
                      NumberFormat.currency(symbol: '\$').format(totalTax),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Totals
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Subtotal:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  NumberFormat.currency(symbol: '\$').format(subtotal),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Tax:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  NumberFormat.currency(symbol: '\$').format(totalTax),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  NumberFormat.currency(symbol: '\$').format(calculatedTotal),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),

            // QR Code section
            if (isFiscalized && qrCode != null) ...[
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    const Text(
                      'Fiscal Receipt QR Code',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    QrImageView(
                      data: qrCode,
                      version: QrVersions.auto,
                      size: 120.0,
                      backgroundColor: Colors.white,
                    ),
                    if (receipt['FiscalInvoiceNumber'] != null)
                      Text(
                        'Invoice: ${receipt['FiscalInvoiceNumber']}',
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],

            // Print Button (always shown)
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton.icon(
                onPressed: () async {
                  try {
                    await ReceiptPrintService.printReceipt(
                      receipt: receipt,
                      companyDetails: companyDetails,
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Error printing receipt: ${e.toString()}',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.print),
                label: const Text('Print Receipt'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isError ? Colors.red.shade100 : Colors.green.shade100,
                  foregroundColor:
                      isError ? Colors.red.shade900 : Colors.green.shade900,
                ),
              ),
            ),

            // Error message if fiscalization failed
            if (isError) ...[
              const SizedBox(height: 8),
              Text(
                'Error: ${receipt['FiscalError'] ?? 'Unknown error'}',
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
