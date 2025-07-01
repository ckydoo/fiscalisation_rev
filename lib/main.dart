import 'package:fiscalisation_rev/services/fiscalization_middleware.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// import 'package:pointycastle/api.dart'; // Keep this if you still use AsymmetricKey elsewhere

import 'services/certificate_manager.dart';
import 'services/zimra_api_client.dart';
import 'services/zimra_fiscalization_service.dart';
import 'widgets/aronium_pos_simulator.dart';
// import 'widgets/certificate_setup_dialog.dart'; // We won't show this for now
import 'widgets/fiscalized_receipts_display.dart';
import 'services/database_service.dart';

void main() async {
  // Initialize FFI for Sqflite on Windows
  sqfliteFfiInit();
  // Ensure Flutter widgets are initialized
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZIMRA Fiscalization',
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // final CertificateManager _certificateManager = CertificateManager(); // No longer needed directly here
  bool _isLoading = true;
  // bool _certificateSetupRequired = false; // No longer needed

  DatabaseService? _dbService;
  ZimraApiClient? _zimraApiClient;
  ZimraFiscalizationService? _zimraFiscalizationService;
  FiscalizationMiddleware? _fiscalizationMiddleware;

  Stream<List<Map<String, dynamic>>>? _salesStream;
  Map<String, dynamic>? _companyDetails;

  @override
  void initState() {
    super.initState();
    _initializeApplication();
  }

  Future<void> _initializeApplication() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Skip Certificate Manager initialization for now
      // The ZimraApiClient will be instantiated without a security context or private key.
      // This means mutual TLS will not be performed, and signing will be skipped/mocked.

      // 2. Initialize DatabaseService
      const aroniumDbPath =
          'C:\\Users\\hp\\AppData\\Local\\Aronium\\Data\\pos.db'; // IMPORTANT: Adjust this path
      _dbService = DatabaseService(aroniumDbPath: aroniumDbPath);
      await _dbService!.initDatabases();
      // NEW: Fetch company details once at startup
      _companyDetails = await _dbService!.getCompanyDetails();
      if (_companyDetails == null) {
        debugPrint('Warning: Company details not found in Aronium DB.');
        // You might want to show a more prominent error or prompt here
      }
      // 3. Initialize ZIMRA API Client WITHOUT certificate details
      _zimraApiClient = ZimraApiClient(
        // Do NOT pass signingPrivateKey or securityContext here
        // They will remain null in ZimraApiClient, effectively skipping client auth and real signing.
      );

      // 4. Initialize ZimraFiscalizationService
      _zimraFiscalizationService = ZimraFiscalizationService(_zimraApiClient!);

      // 5. Initialize Fiscalization Middleware
      // You might need to pass a mock CertificateManager or adjust FiscalizationMiddleware
      // if it strictly requires a fully initialized CertificateManager.
      // For now, let's pass a dummy one or remove the dependency if possible.
      // If FiscalizationMiddleware needs it, you'll have to mock its behavior.
      // For this example, let's assume it can handle a null/uninitialized cert manager
      // or we'll create a dummy one.
      final dummyCertManager = CertificateManager(); // Create a dummy instance
      _fiscalizationMiddleware = FiscalizationMiddleware(
        _dbService!,
        _zimraFiscalizationService!,
        dummyCertManager, // Pass a dummy, uninitialized CertificateManager
      );

      // 6. Start polling for sales
      _fiscalizationMiddleware!.startPolling();

      // 7. Set up stream for displaying sales
      _salesStream = Stream.periodic(const Duration(seconds: 2), (_) {
        return _dbService!.getAllSalesDetails();
      }).asyncMap((event) => event);

      setState(() {
        _isLoading = false;
        // _certificateSetupRequired = false; // No longer needed
      });
    } catch (e, st) {
      debugPrint('Error during application initialization: $e\n$st');
      setState(() {
        _isLoading = false;
        // _certificateSetupRequired = true; // No longer needed
      });
      if (mounted) {
        showDialog(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: const Text('Initialization Error'),
                content: Text(
                  'Failed to initialize application: ${e.toString()}\nCheck logs for details.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
        );
      }
    }
  }

  // _showCertificateSetup method is no longer called or needed for now
  // Future<bool> _showCertificateSetup() async {
  //   final result = await showDialog<bool>(
  //     context: context,
  //     builder: (context) => CertificateSetupDialog(
  //       certificateManager: _certificateManager,
  //       zimraApiClient: ZimraApiClient(),
  //     ),
  //   );
  //   return result == true;
  // }

  @override
  void dispose() {
    _fiscalizationMiddleware?.stopPolling();
    _dbService?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ZIMRA Fiscalization')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Remove the certificate setup required UI
    // if (_certificateSetupRequired) {
    //   return Center(
    //     child: Column(
    //       mainAxisAlignment: MainAxisAlignment.center,
    //       children: [
    //         const Icon(Icons.security, size: 64),
    //         const SizedBox(height: 16),
    //         const Text('Certificate Setup Required'),
    //         ElevatedButton(
    //           onPressed: _showCertificateSetup,
    //           child: const Text('Setup Certificate'),
    //         ),
    //       ],
    //     ),
    //   );
    // }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AroniumPOSSimulator(),
          const SizedBox(height: 16),
          if (_fiscalizationMiddleware != null)
            ValueListenableBuilder<String>(
              valueListenable: _fiscalizationMiddleware!.statusMessage,
              builder: (context, message, child) {
                return Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Middleware Status: $message',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 16),
          if (_salesStream != null)
            FiscalizedReceiptsDisplay(
              salesStream: _salesStream!,
              companyDetails: _companyDetails ?? {},
            ),
        ],
      ),
    );
  }
}
