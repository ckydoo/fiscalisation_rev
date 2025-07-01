import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For FilteringTextInputFormatter
import 'package:fiscalisation_rev/services/certificate_manager.dart';
import 'package:fiscalisation_rev/services/zimra_api_client.dart'; // Import ZimraApiClient

class CertificateSetupDialog extends StatefulWidget {
  final CertificateManager certificateManager;
  final ZimraApiClient
  zimraApiClient; // Pass ZimraApiClient for testing connection

  const CertificateSetupDialog({
    super.key,
    required this.certificateManager,
    required this.zimraApiClient,
  });

  @override
  State<CertificateSetupDialog> createState() => _CertificateSetupDialogState();
}

class _CertificateSetupDialogState extends State<CertificateSetupDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _deviceIdController = TextEditingController();
  final TextEditingController _activationKeyController =
      TextEditingController();
  final TextEditingController _deviceSerialNoController =
      TextEditingController();

  bool _isLoading = false;
  String? _statusMessage;
  bool _isRegisteringNewDevice =
      false; // State to switch between import and register

  @override
  void dispose() {
    _passwordController.dispose();
    _deviceIdController.dispose();
    _activationKeyController.dispose();
    _deviceSerialNoController.dispose();
    super.dispose();
  }

  Future<void> _importCertificate() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Importing certificate...';
    });

    final password = _passwordController.text;
    final success = await widget.certificateManager.importCertificate(password);

    setState(() {
      _isLoading = false;
      if (success) {
        _statusMessage = 'Certificate imported successfully!';
        Navigator.of(context).pop(true); // Indicate success
      } else {
        _statusMessage =
            'Failed to import certificate. Check password or file.';
      }
    });
  }

  Future<void> _registerNewDevice() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Registering new device and obtaining certificate...';
    });

    final deviceId = int.parse(_deviceIdController.text);
    final activationKey = _activationKeyController.text;
    final deviceSerialNo = _deviceSerialNoController.text;
    final password =
        _passwordController.text; // Password for the new private key

    final result = await widget.certificateManager.generateCsrAndRegisterDevice(
      deviceId: deviceId,
      activationKey: activationKey,
      deviceSerialNo: deviceSerialNo,
      password: password,
    );

    setState(() {
      _isLoading = false;
      if (result != null) {
        _statusMessage =
            'Device registered and certificate obtained successfully!';
        Navigator.of(context).pop(true); // Indicate success
      } else {
        _statusMessage =
            'Failed to register device or obtain certificate. Check details and logs.';
      }
    });
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Testing connection...';
    });

    try {
      // Ensure the ZimraApiClient has the loaded certificate for testing
      widget.zimraApiClient.setSecurityContext(
        widget.certificateManager.securityContext,
      );
      widget.zimraApiClient.setSigningPrivateKey(
        widget.certificateManager.signingPrivateKey,
      );

      final deviceId = int.tryParse(_deviceIdController.text);
      if (deviceId == null) {
        setState(() {
          _statusMessage = 'Invalid Device ID for testing.';
          _isLoading = false;
        });
        return;
      }

      final response = await widget.zimraApiClient.ping(deviceID: deviceId);

      setState(() {
        _isLoading = false;
        if (response != null && response['operationID'] != null) {
          _statusMessage =
              'Connection test successful! Reporting frequency: ${response['reportingFrequency']} mins.';
        } else {
          _statusMessage =
              'Connection test failed: ${response?['message'] ?? 'Unknown error'}.';
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Connection test failed with exception: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isRegisteringNewDevice
            ? 'Register New Device'
            : 'Setup ZIMRA Certificate',
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isRegisteringNewDevice) ...[
                TextFormField(
                  controller: _deviceIdController,
                  decoration: const InputDecoration(
                    labelText: 'Device ID (from ZIMRA)',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter Device ID';
                    }
                    if (int.tryParse(value) == null) {
                      return 'Invalid Device ID';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: _activationKeyController,
                  decoration: const InputDecoration(
                    labelText: 'Activation Key (from ZIMRA)',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter Activation Key';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: _deviceSerialNoController,
                  decoration: const InputDecoration(
                    labelText: 'Device Serial No (e.g., SN:001)',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter Device Serial No';
                    }
                    return null;
                  },
                ),
              ],
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText:
                      _isRegisteringNewDevice
                          ? 'Password for new Private Key'
                          : 'Certificate Password',
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a password';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              if (_isLoading)
                const CircularProgressIndicator()
              else if (_statusMessage != null)
                Text(
                  _statusMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  ElevatedButton(
                    onPressed:
                        _isLoading
                            ? null
                            : (_isRegisteringNewDevice
                                ? _registerNewDevice
                                : _importCertificate),
                    child: Text(
                      _isRegisteringNewDevice
                          ? 'Register & Import'
                          : 'Import .p12 File',
                    ),
                  ),
                  if (!_isRegisteringNewDevice) // Only show test connection for imported certs
                    ElevatedButton(
                      onPressed: _isLoading ? null : _testConnection,
                      child: const Text('Test Connection (Ping)'),
                    ),
                ],
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isRegisteringNewDevice = !_isRegisteringNewDevice;
                    _statusMessage = null; // Clear status message on switch
                  });
                },
                child: Text(
                  _isRegisteringNewDevice
                      ? 'Already have a .p12 file? Import it.'
                      : 'Don\'t have a .p12 file? Register new device.',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(false); // Indicate cancellation
          },
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
