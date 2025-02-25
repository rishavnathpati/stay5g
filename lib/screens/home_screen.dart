import 'dart:async';
import 'package:flutter/material.dart';
import '../models/enums.dart';
import '../services/connectivity_service.dart';
import '../services/download_service.dart';
import '../services/webview_service.dart';
import '../widgets/connection_status_card.dart';
import '../widgets/download_speed_card.dart';
import '../widgets/webview_speed_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Services
  final _connectivityService = ConnectivityService();
  final _downloadService = DownloadService();
  final _webViewService = WebViewService();
  
  // Current state
  SpeedTestMode _currentMode = SpeedTestMode.download;
  
  // Stream subscriptions
  late StreamSubscription<ConnectionType> _connectionTypeSubscription;
  late StreamSubscription<bool> _hotspotActiveSubscription;
  
  @override
  void initState() {
    super.initState();
    
    // Listen for connectivity changes
    _connectionTypeSubscription = _connectivityService.connectionTypeStream.listen((_) {
      // Just trigger a rebuild when connection type changes
      if (mounted) setState(() {});
    });
    
    // Listen for hotspot status changes
    _hotspotActiveSubscription = _connectivityService.hotspotActiveStream.listen((isActive) {
      if (isActive) {
        _downloadService.pauseDownloads('Active hotspot traffic detected, downloads paused');
      } else if (_downloadService.isPaused) {
        _downloadService.resumeDownloads();
      }
    });
    
    // Start WebView timer if in Fast.com mode
    if (_currentMode == SpeedTestMode.fastCom) {
      _webViewService.startWebViewTimer();
    }
  }
  
  @override
  void dispose() {
    // Cancel subscriptions
    _connectionTypeSubscription.cancel();
    _hotspotActiveSubscription.cancel();
    
    // Dispose services
    _downloadService.dispose();
    _webViewService.dispose();
    
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Stay5G'),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Mode Selector
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ChoiceChip(
                          label: const Text('Download Test'),
                          selected: _currentMode == SpeedTestMode.download,
                          onSelected: (bool selected) {
                            if (selected) {
                              setState(() {
                                _currentMode = SpeedTestMode.download;
                              });
                              _webViewService.stopWebViewTimer();
                            }
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Fast.com Test'),
                          selected: _currentMode == SpeedTestMode.fastCom,
                          onSelected: (bool selected) {
                            if (selected) {
                              setState(() {
                                _currentMode = SpeedTestMode.fastCom;
                              });
                              if (_downloadService.isRunning) {
                                _downloadService.stopLoop();
                              }
                              _webViewService.startWebViewTimer();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Connection Status Card
                ConnectionStatusCard(
                  connectionType: _connectivityService.connectionType,
                ),
                const SizedBox(height: 16),

                // Speed Monitor or WebView
                Expanded(
                  child: _currentMode == SpeedTestMode.download
                      ? StreamBuilder<double>(
                          stream: _downloadService.downloadSpeedStream,
                          builder: (context, snapshot) {
                            return DownloadSpeedCard(
                              status: _downloadService.status,
                              currentSpeed: _downloadService.currentSpeed,
                              averageSpeed: _downloadService.averageSpeed,
                              downloadCount: _downloadService.downloadCount,
                            );
                          },
                        )
                      : StreamBuilder<bool>(
                          stream: _webViewService.webviewVisibleStream,
                          builder: (context, snapshot) {
                            return WebViewSpeedCard(
                              isWebviewVisible: _webViewService.isWebviewVisible,
                              webViewController: _webViewService.webViewController,
                              status: _webViewService.status,
                              lastResult: _webViewService.lastWebviewResult,
                              nextTest: _webViewService.nextWebviewTest,
                              progress: _webViewService.webviewTestProgress,
                              onRunTest: _webViewService.startWebViewSpeedTest,
                            );
                          },
                        ),
                ),

                const SizedBox(height: 16),

                // Control Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (_currentMode == SpeedTestMode.download) ...[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _downloadService.isRunning ? null : _downloadService.startLoop,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Start'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _downloadService.isRunning ? () => _downloadService.stopLoop() : null,
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ] else ...[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _webViewService.isWebviewVisible ? null : _webViewService.startWebViewSpeedTest,
                          icon: const Icon(Icons.speed),
                          label: const Text('Run Speed Test'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 