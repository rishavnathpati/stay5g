import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';

// Constants for optimization
const int maxConcurrentDownloads = 1;
const int connectionTimeout = 10; // seconds
const int maxRetries = 3;
const int retryDelay = 5; // seconds
const int hotspotCheckInterval = 2; // seconds
const int trafficThreshold = 50000; // bytes per second (50KB/s)

void main() {
  // Enable keep-alive connections
  HttpOverrides.global = _CustomHttpOverrides();
  runApp(const MyApp());
}

// Custom HTTP overrides for keep-alive
class _CustomHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..connectionTimeout = const Duration(seconds: connectionTimeout)
      ..idleTimeout = const Duration(seconds: 60)
      ..maxConnectionsPerHost = maxConcurrentDownloads;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stay5G',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const Stay5GHomePage(),
    );
  }
}

class Stay5GHomePage extends StatefulWidget {
  const Stay5GHomePage({super.key});

  @override
  State<Stay5GHomePage> createState() => _Stay5GHomePageState();
}

class _Stay5GHomePageState extends State<Stay5GHomePage> {
  String _status = 'Idle';
  bool _isRunning = false;
  Timer? _timer;
  String _downloadSpeed = '0 MB/s';
  double _averageSpeed = 0.0;
  int _downloadCount = 0;
  String _connectionType = 'Unknown';
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  List<Future<void>>? _activeDownloads;
  int _retryCount = 0;
  final List<File> _activeFiles = [];
  bool _isHotspotActive = false;
  bool _isPaused = false;
  Timer? _hotspotCheckTimer;
  final _networkInfo = NetworkInfo();
  Map<String, int> _lastByteCounts = {};
  DateTime _lastTrafficCheck = DateTime.now();

  // List of test files from different CDNs
  final List<String> _testUrls = ['https://testfile.org/1.3GBiconpng'];

  @override
  void initState() {
    super.initState();
    _initConnectivity();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      _updateConnectionStatus,
    );
    _startHotspotMonitoring();
  }

  Future<void> _initConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      await _updateConnectionStatus(result);
    } catch (e) {
      setState(() {
        _connectionType = 'Failed to get connection type';
      });
    }
  }

  Future<void> _updateConnectionStatus(ConnectivityResult result) async {
    setState(() {
      switch (result) {
        case ConnectivityResult.mobile:
          _connectionType = 'Mobile Network';
          break;
        case ConnectivityResult.wifi:
          _connectionType = 'WiFi';
          break;
        case ConnectivityResult.none:
          _connectionType = 'No Connection';
          break;
        default:
          _connectionType = 'Unknown';
          break;
      }
    });
  }

  // Get a random test URL to distribute load
  String get _randomTestUrl {
    final random = Random();
    return _testUrls[random.nextInt(_testUrls.length)];
  }

  void _startHotspotMonitoring() {
    _hotspotCheckTimer?.cancel();
    _hotspotCheckTimer = Timer.periodic(
      const Duration(seconds: hotspotCheckInterval),
      (_) => _checkHotspotStatus(),
    );
  }

  Future<void> _checkHotspotStatus() async {
    try {
      // Check if device is acting as a hotspot
      final wifiIP = await _networkInfo.getWifiIP();
      final wifiName = await _networkInfo.getWifiName();

      // Common hotspot IP patterns
      final isHotspotIP =
          wifiIP?.startsWith('192.168.43.') ?? false; // Android default
      final isHotspotName =
          wifiName?.toLowerCase().contains('android') ?? false;

      bool wasHotspotActive = _isHotspotActive;
      _isHotspotActive = isHotspotIP || isHotspotName;

      if (_isHotspotActive) {
        // Check for actual data usage
        final hasActiveTraffic = await _checkNetworkTraffic();
        if (hasActiveTraffic && !_isPaused) {
          _pauseDownloads('Active hotspot traffic detected, downloads paused');
        } else if (!hasActiveTraffic && _isPaused) {
          _resumeDownloads();
        }
      } else if (wasHotspotActive && !_isHotspotActive && _isPaused) {
        _resumeDownloads();
      }
    } catch (e) {
      print('Error checking hotspot status: $e');
    }
  }

  Future<bool> _checkNetworkTraffic() async {
    try {
      if (Platform.isAndroid) {
        // Get network interface statistics
        final result = await Process.run('cat', ['/proc/net/dev']);
        if (result.exitCode == 0) {
          final now = DateTime.now();
          final lines = result.stdout.toString().split('\n');
          bool hasSignificantTraffic = false;
          Map<String, int> currentByteCounts = {};

          // Parse network interface statistics
          for (var line in lines) {
            if (line.contains('wlan0') || line.contains('ap0')) {
              // Common Android hotspot interfaces
              final parts = line.trim().split(
                RegExp(r'\s+'),
              ); // Split by whitespace
              if (parts.length >= 10) {
                final interface = parts[0].replaceAll(':', '');
                final rxBytes = int.tryParse(parts[1]) ?? 0; // Received bytes
                final txBytes =
                    int.tryParse(parts[9]) ?? 0; // Transmitted bytes
                currentByteCounts[interface] = rxBytes + txBytes;

                // Calculate traffic rate
                if (_lastByteCounts.containsKey(interface)) {
                  final bytesDiff =
                      currentByteCounts[interface]! -
                      _lastByteCounts[interface]!;
                  final timeDiff = now.difference(_lastTrafficCheck).inSeconds;
                  if (timeDiff > 0) {
                    final bytesPerSecond = bytesDiff ~/ timeDiff;
                    if (bytesPerSecond > trafficThreshold) {
                      hasSignificantTraffic = true;
                      print(
                        'Traffic detected on $interface: ${(bytesPerSecond / 1024).toStringAsFixed(2)} KB/s',
                      );
                    }
                  }
                }
              }
            }
          }

          _lastByteCounts = currentByteCounts;
          _lastTrafficCheck = now;
          return hasSignificantTraffic;
        }
      }
    } catch (e) {
      print('Error checking network traffic: $e');
    }
    return false;
  }

  void _pauseDownloads(String reason) {
    if (!_isPaused) {
      setState(() {
        _isPaused = true;
        _status = reason;
      });
      // Don't stop the downloads completely, just pause them
      _activeDownloads?.forEach((download) => download);
    }
  }

  void _resumeDownloads() {
    if (_isPaused && _isRunning) {
      setState(() {
        _isPaused = false;
        _status = 'Resuming downloads...';
      });
      _downloadFile(); // Restart the download cycle
    }
  }

  Future<void> _downloadFile() async {
    if (!_isRunning || _isPaused) return;

    setState(() {
      _status = 'Downloading';
      _downloadSpeed = '0 MB/s';
    });

    _activeDownloads = List.generate(
      maxConcurrentDownloads,
      (_) => _performSingleDownload(),
    );

    try {
      await Future.wait(_activeDownloads!);
    } catch (e) {
      // Handle any errors from the concurrent downloads
      if (_isRunning) {
        _retryCount++;
        if (_retryCount < maxRetries) {
          setState(() {
            _status =
                'Error: $e\nRetrying in $retryDelay seconds... (Attempt $_retryCount/$maxRetries)';
          });
          await Future.delayed(Duration(seconds: retryDelay));
          if (_isRunning) _downloadFile();
        } else {
          setState(() {
            _status =
                'Max retries reached. Waiting for next scheduled download...';
            _retryCount = 0;
          });
        }
      }
    }
  }

  Future<void> _cleanupFiles() async {
    for (var file in _activeFiles) {
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        print('Error deleting file: $e');
      }
    }
    _activeFiles.clear();
  }

  Future<void> _performSingleDownload() async {
    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}/downloaded_file_${DateTime.now().millisecondsSinceEpoch}.tmp',
    );
    _activeFiles.add(file); // Track the file
    final sink = file.openWrite();
    final stopwatch = Stopwatch()..start();
    var client = http.Client();
    StreamSubscription<List<int>>? subscription;

    try {
      final request = http.Request('GET', Uri.parse(_randomTestUrl))
        ..headers['Connection'] = 'keep-alive';

      final response = await client.send(request).timeout(
        Duration(seconds: connectionTimeout),
        onTimeout: () {
          throw TimeoutException('Connection timed out');
        },
      );

      if (response.statusCode == 200) {
        var downloadedBytes = 0;
        var lastUpdateTime = DateTime.now();
        var lastBytes = 0;

        // Create a Completer to handle the async completion
        final completer = Completer<void>();

        subscription = response.stream.listen(
          (List<int> chunk) {
            if (!_isRunning) {
              subscription?.cancel();
              completer.complete();
              return;
            }
            sink.add(chunk);
            downloadedBytes += chunk.length;

            final now = DateTime.now();
            if (now.difference(lastUpdateTime).inMilliseconds >= 500) {
              final intervalBytes = downloadedBytes - lastBytes;
              final intervalSeconds = now.difference(lastUpdateTime).inMilliseconds / 1000;
              final currentSpeed = (intervalBytes / intervalSeconds) / (1024 * 1024);

              setState(() {
                _downloadSpeed = '${currentSpeed.toStringAsFixed(2)} MB/s';
                _averageSpeed = (_averageSpeed * _downloadCount + currentSpeed) / (_downloadCount + 1);
              });

              lastUpdateTime = now;
              lastBytes = downloadedBytes;
            }
          },
          onDone: () async {
            await sink.close();
            if (await file.exists()) {
              await file.delete();
              _activeFiles.remove(file);
            }
            if (_isRunning) {
              setState(() {
                _downloadCount++;
                _status = 'Waiting for next download...';
              });
            }
            completer.complete();
          },
          onError: (error) {
            completer.completeError(error);
          },
          cancelOnError: true,
        );

        // Wait for the download to complete or be cancelled
        await completer.future;
      } else {
        throw Exception('Failed to download file: ${response.statusCode}');
      }
    } catch (e) {
      subscription?.cancel();
      rethrow;
    } finally {
      stopwatch.stop();
      await sink.close();
      client.close();
      if (await file.exists()) {
        await file.delete();
        _activeFiles.remove(file);
      }
    }
  }

  void _startLoop() {
    if (_isRunning) return;

    setState(() {
      _isRunning = true;
      _status = 'Starting...';
      _downloadCount = 0;
      _averageSpeed = 0.0;
      _retryCount = 0;
    });

    _downloadFile();
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!_isRunning) {
        timer.cancel();
        return;
      }
      _downloadFile();
    });
  }

  void _stopLoop() async {
    setState(() {
      _isRunning = false;
      _status = 'Stopping downloads...';
      _downloadSpeed = '0 MB/s';
    });

    // Cancel the periodic timer first
    _timer?.cancel();

    // Cancel all active downloads
    if (_activeDownloads != null) {
      try {
        // Wait for all downloads to complete or cancel with a timeout
        await Future.wait(_activeDownloads!).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            print('Download cancellation timed out');
            return []; // Return empty list on timeout
          },
        );
      } catch (e) {
        print('Error during download cancellation: $e');
      }
      _activeDownloads = null;
    }

    // Cleanup files
    await _cleanupFiles();

    setState(() {
      _status = 'Stopped';
    });
  }

  @override
  void dispose() {
    _stopLoop();
    _connectivitySubscription?.cancel();
    _hotspotCheckTimer?.cancel();
    _cleanupFiles();
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
                // Connection Status Card
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(
                          _connectionType == 'Mobile Network'
                              ? Icons.signal_cellular_alt
                              : Icons.signal_cellular_off,
                          size: 32,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Network Type',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                _connectionType,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Speed Monitor Card
                Expanded(
                  child: Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Status: $_status',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _downloadSpeed,
                            style: Theme.of(
                              context,
                            ).textTheme.displayMedium?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Current Speed',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          if (_downloadCount > 0) ...[
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                Column(
                                  children: [
                                    Text(
                                      '${_averageSpeed.toStringAsFixed(2)} MB/s',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge?.copyWith(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.secondary,
                                      ),
                                    ),
                                    Text(
                                      'Average Speed',
                                      style:
                                          Theme.of(
                                            context,
                                          ).textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                                Column(
                                  children: [
                                    Text(
                                      '$_downloadCount',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge?.copyWith(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.secondary,
                                      ),
                                    ),
                                    Text(
                                      'Downloads',
                                      style:
                                          Theme.of(
                                            context,
                                          ).textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Control Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isRunning ? null : _startLoop,
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
                        onPressed: _isRunning ? _stopLoop : null,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
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
