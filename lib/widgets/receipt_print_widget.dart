import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';

class ReceiptPrintWidget extends StatelessWidget {
  final Map<String, dynamic> receipt;
  final Map<String, dynamic> companyDetails;

  const ReceiptPrintWidget({
    Key? key,
    required this.receipt,
    required this.companyDetails,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final items = (receipt['Items'] as List<dynamic>?) ?? [];
    final qrCode = receipt['QrCode'] as String?;
    final fiscalSignature = receipt['FiscalSignature'] as String?;
    final fiscalInvoiceNumber = receipt['FiscalInvoiceNumber'] as String?;
    final taxDetails =
        (receipt['TaxDetails'] as List<dynamic>?)
            ?.map((tax) => tax as Map<String, dynamic>)
            .toList() ??
        [];

    double subtotal = 0.0;
    double totalTax = 0.0;

    if (items.isNotEmpty) {
      subtotal = items.fold(0.0, (sum, item) {
        final price = (item['Price'] as num?)?.toDouble() ?? 0.0;
        final quantity = (item['Quantity'] as num?)?.toDouble() ?? 0.0;
        return sum + (price * quantity);
      });
    }

    if (taxDetails.isNotEmpty) {
      totalTax = taxDetails.fold(0.0, (sum, tax) {
        final taxAmount = (tax['TaxAmount'] as num?)?.toDouble() ?? 0.0;
        return sum + taxAmount;
      });
    }

    final calculatedTotal = subtotal + totalTax;

    final date =
        receipt['DateCreated'] != null
            ? DateFormat(
              'dd MMM yyyy HH:mm',
            ).format(DateTime.parse(receipt['DateCreated']))
            : '';

    return Scaffold(
      appBar: AppBar(title: const Text('Print Receipt')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Company Header
            Center(
              child: Text(
                companyDetails['Name'] ?? 'Company Name',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
            if (companyDetails['TaxNumber'] != null)
              Center(child: Text('Tax Number: ${companyDetails['TaxNumber']}')),
            if (companyDetails['Address'] != null)
              Center(child: Text('Address: ${companyDetails['Address']}')),
            if (companyDetails['City'] != null)
              Center(child: Text('City: ${companyDetails['City']}')),
            if (companyDetails['PostalCode'] != null &&
                companyDetails['CountrySubentity'] != null)
              Center(
                child: Text(
                  '${companyDetails['PostalCode']}, ${companyDetails['CountrySubentity']}',
                ),
              ),
            const Divider(height: 32),

            // Receipt Info
            Text(
              'Receipt #${receipt['Number'] ?? 'N/A'}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (date.isNotEmpty)
              Text(
                date,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            const SizedBox(height: 16),

            // Items List
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${item['Quantity']} x ${item['ProductDetails']?['Name'] ?? 'Item'}',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    Text(
                      NumberFormat.currency(symbol: '\$').format(
                        ((item['Price'] as num?)?.toDouble() ?? 0.0) *
                            ((item['Quantity'] as num?)?.toDouble() ?? 0.0),
                      ),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 32),

            // Tax Breakdown
            if (taxDetails.isNotEmpty)
              ...taxDetails.map(
                (tax) => Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${tax['Name'] ?? 'Tax'} (${(tax['Rate'] as num?)?.toStringAsFixed(0) ?? '0'}%)',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        NumberFormat.currency(
                          symbol: '\$',
                        ).format((tax['TaxAmount'] as num?)?.toDouble() ?? 0.0),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Totals
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Subtotal:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  NumberFormat.currency(symbol: '\$').format(subtotal),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Tax:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  NumberFormat.currency(symbol: '\$').format(totalTax),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                Text(
                  NumberFormat.currency(symbol: '\$').format(calculatedTotal),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // QR Code
            if (qrCode != null) ...[
              Center(
                child: Column(
                  children: [
                    const Text(
                      'Fiscal Receipt QR Code',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    QrImageView(
                      data: qrCode,
                      version: QrVersions.auto,
                      size: 150.0,
                      backgroundColor: Colors.white,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Fiscal Signature
            if (fiscalSignature != null) ...[
              const Text(
                'Fiscal Signature:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              SelectableText(
                fiscalSignature,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
