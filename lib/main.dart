import 'package:fiscalisation_rev/services/fiscalization_middleware.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'services/certificate_manager.dart';
import 'services/zimra_api_client.dart';
import 'services/zimra_fiscalization_service.dart';
import 'services/laravel_api_client.dart';
import 'services/api_config.dart';
import 'widgets/aronium_pos_simulator.dart';
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
  bool _isLoading = true;

  DatabaseService? _dbService;
  ZimraApiClient? _zimraApiClient;
  ZimraFiscalizationService? _zimraFiscalizationService;
  FiscalizationMiddleware? _fiscalizationMiddleware;
  LaravelApiClient? _laravelApiClient;

  Stream<List<Map<String, dynamic>>>? _salesStream;
  Map<String, dynamic>? _companyDetails;
  bool _apiConfigured = false;

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
      // 1. Initialize DatabaseService
      const aroniumDbPath =
          'C:\\Users\\hp\\AppData\\Local\\Aronium\\Data\\pos.db';
      _dbService = DatabaseService(aroniumDbPath: aroniumDbPath);
      await _dbService!.initDatabases();

      // Fetch company details once at startup
      _companyDetails = await _dbService!.getCompanyDetails();
      if (_companyDetails == null) {
        debugPrint('Warning: Company details not found in Aronium DB.');
      }

      // 2. Initialize ZIMRA API Client
      _zimraApiClient = ZimraApiClient();

      // 3. Initialize ZimraFiscalizationService
      _zimraFiscalizationService = ZimraFiscalizationService(_zimraApiClient!);

      // 4. Initialize Laravel API Client (if configured)
      if (ApiConfig.isConfigured() && ApiConfig.enableApiSync) {
        _laravelApiClient = LaravelApiClient(
          baseUrl: ApiConfig.baseUrl,
          apiToken: ApiConfig.apiToken,
          timeout: Duration(seconds: ApiConfig.timeoutSeconds),
        );

        // Test API connection
        final isConnected = await _laravelApiClient!.testConnection();
        _apiConfigured = isConnected;

        if (isConnected) {
          debugPrint('✓ Laravel API connected successfully');
        } else {
          debugPrint('✗ Laravel API connection failed');
        }
      } else {
        debugPrint('Laravel API not configured');
      }

      // 5. Initialize Fiscalization Middleware with optional Laravel API
      final dummyCertManager = CertificateManager();
      _fiscalizationMiddleware = FiscalizationMiddleware(
        _dbService!,
        _zimraFiscalizationService!,
        dummyCertManager,
        laravelApiClient: _laravelApiClient,
      );

      // 6. Start polling for sales
      _fiscalizationMiddleware!.startPolling();

      // 7. Set up stream for displaying sales
      _salesStream =
          Stream.periodic(const Duration(seconds: 2), (_) {
            return _dbService!.getAllSalesDetails();
          }).asyncMap((event) => event).asBroadcastStream();

      setState(() {
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('Error during application initialization: $e\n$st');
      setState(() {
        _isLoading = false;
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

  @override
  void dispose() {
    _fiscalizationMiddleware?.dispose();
    _dbService?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('ZIMRA Fiscalization System'),
        actions: [
          // API Status Indicator
          if (_laravelApiClient != null)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _apiConfigured ? Icons.cloud_done : Icons.cloud_off,
                      color: _apiConfigured ? Colors.green : Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _apiConfigured ? 'API Connected' : 'API Offline',
                      style: TextStyle(
                        color: _apiConfigured ? Colors.green : Colors.orange,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Test API Button
          if (_laravelApiClient != null)
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Test API Connection',
              onPressed: () async {
                final isConnected =
                    await _fiscalizationMiddleware!.testApiConnection();
                setState(() {
                  _apiConfigured = isConnected;
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isConnected
                            ? 'API Connected Successfully'
                            : 'API Connection Failed',
                      ),
                      backgroundColor: isConnected ? Colors.green : Colors.red,
                    ),
                  );
                }
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Status Messages
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Column(
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: _fiscalizationMiddleware!.statusMessage,
                  builder: (context, status, child) {
                    return Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Status: $status',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (_laravelApiClient != null) ...[
                  const SizedBox(height: 8),
                  ValueListenableBuilder<String>(
                    valueListenable: _fiscalizationMiddleware!.apiStatusMessage,
                    builder: (context, status, child) {
                      return Row(
                        children: [
                          Icon(
                            _apiConfigured ? Icons.cloud : Icons.cloud_off,
                            color: _apiConfigured ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              status,
                              style: TextStyle(
                                color:
                                    _apiConfigured ? Colors.green : Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),

          // Aronium POS Info
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: AroniumPOSSimulator(),
          ),

          // Sales List
          Expanded(
            child:
                _salesStream == null
                    ? const Center(child: Text('Initializing...'))
                    : StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _salesStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Text('Error: ${snapshot.error}'),
                          );
                        }
                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return const Center(
                            child: Text('No sales found in Aronium database'),
                          );
                        }
                        return FiscalizedReceiptsDisplay(
                          salesStream: _salesStream!,
                          companyDetails: _companyDetails!,
                          onSyncToApi: (documentId) async {
                            final result = await _fiscalizationMiddleware!
                                .syncSaleToApi(documentId);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    result['success'] == true
                                        ? 'Synced to API successfully'
                                        : 'Sync failed: ${result['message']}',
                                  ),
                                  backgroundColor:
                                      result['success'] == true
                                          ? Colors.green
                                          : Colors.red,
                                ),
                              );
                            }
                          },
                          showApiSyncButton: _laravelApiClient != null,
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
