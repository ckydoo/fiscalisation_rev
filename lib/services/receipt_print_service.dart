import 'dart:typed_data';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ReceiptPrintService {
  static Future<void> printReceipt({
    required Map<String, dynamic> receipt,
    required Map<String, dynamic> companyDetails,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  companyDetails['Name'] ?? 'Company Name',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 5),
              if (companyDetails['TaxNumber'] != null)
                pw.Text('Tax Number: ${companyDetails['TaxNumber']}'),
              if (companyDetails['Address'] != null)
                pw.Text('Address: ${companyDetails['Address']}'),
              pw.Divider(),
              pw.SizedBox(height: 10),
              pw.Text(
                'Receipt #${receipt['Number'] ?? 'N/A'}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                receipt['DateCreated'] ?? '',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 10),
              ...(receipt['Items'] as List<dynamic>? ?? []).map(
                (item) => pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        '${item['Quantity']} x ${item['ProductDetails']?['Name'] ?? 'Item'}',
                      ),
                    ),
                    pw.Text(
                      '\$${(((item['Price'] as num?)?.toDouble() ?? 0.0) * ((item['Quantity'] as num?)?.toDouble() ?? 0.0)).toStringAsFixed(2)}',
                    ),
                  ],
                ),
              ),
              pw.Divider(),
              pw.SizedBox(height: 10),
              ...(receipt['TaxDetails'] as List<dynamic>? ?? []).map(
                (tax) => pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '${tax['Name'] ?? 'Tax'} (${(tax['Rate'] as num?)?.toStringAsFixed(0) ?? '0'}%)',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    pw.Text(
                      '\$${(tax['TaxAmount'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total:'),
                  pw.Text(
                    '\$${receipt['TotalAmount']?.toStringAsFixed(2) ?? '0.00'}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              if (receipt['QrCode'] != null) ...[
                pw.Center(
                  child: pw.BarcodeWidget(
                    data: receipt['QrCode'],
                    barcode: pw.Barcode.qrCode(),
                    width: 100,
                    height: 100,
                  ),
                ),
                pw.SizedBox(height: 10),
              ],
              if (receipt['FiscalInvoiceNumber'] != null)
                pw.Center(
                  child: pw.Text(
                    'Invoice: ${receipt['FiscalInvoiceNumber']}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ),
              if (receipt['FiscalSignature'] != null) ...[
                pw.SizedBox(height: 10),
                pw.Text(
                  'Fiscal Signature:',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  receipt['FiscalSignature'],
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name:
          'Receipt_${receipt['Number'] ?? DateTime.now().millisecondsSinceEpoch}',
    );
  }
}
