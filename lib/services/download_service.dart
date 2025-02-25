import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../constants/app_constants.dart';

class DownloadService {
  bool _isRunning = false;
  bool _isPaused = false;
  Timer? _downloadTimer;
  List<Future<void>>? _activeDownloads;
  final List<File> _activeFiles = [];
  int _retryCount = 0;
  
  // Stream controllers for download metrics
  final _downloadSpeedController = StreamController<double>.broadcast();
  final _averageSpeedController = StreamController<double>.broadcast();
  final _downloadCountController = StreamController<int>.broadcast();
  final _statusController = StreamController<String>.broadcast();
  
  // Stream getters
  Stream<double> get downloadSpeedStream => _downloadSpeedController.stream;
  Stream<double> get averageSpeedStream => _averageSpeedController.stream;
  Stream<int> get downloadCountStream => _downloadCountController.stream;
  Stream<String> get statusStream => _statusController.stream;
  
  // Current values
  double _currentSpeed = 0.0;
  double _averageSpeed = 0.0;
  int _downloadCount = 0;
  String _status = 'Idle';
  
  // Getters for current values
  double get currentSpeed => _currentSpeed;
  double get averageSpeed => _averageSpeed;
  int get downloadCount => _downloadCount;
  String get status => _status;
  bool get isRunning => _isRunning;
  bool get isPaused => _isPaused;
  
  // Singleton pattern
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();
  
  // Get a random test URL to distribute load
  String get _randomTestUrl {
    final random = Random();
    return AppConstants.testUrls[random.nextInt(AppConstants.testUrls.length)];
  }
  
  // Start download loop
  void startLoop() {
    if (_isRunning) return;
    
    _isRunning = true;
    _isPaused = false;
    _downloadCount = 0;
    _averageSpeed = 0.0;
    _retryCount = 0;
    
    _updateStatus('Starting...');
    
    _downloadFile();
    _downloadTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!_isRunning) {
        timer.cancel();
        return;
      }
      if (!_isPaused) {
        _downloadFile();
      }
    });
  }
  
  // Stop download loop
  Future<void> stopLoop() async {
    _isRunning = false;
    _updateStatus('Stopping downloads...');
    _updateDownloadSpeed(0.0);
    
    // Cancel the periodic timer first
    _downloadTimer?.cancel();
    
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
    
    _updateStatus('Stopped');
  }
  
  // Pause downloads
  void pauseDownloads(String reason) {
    if (!_isPaused && _isRunning) {
      _isPaused = true;
      _updateStatus(reason);
    }
  }
  
  // Resume downloads
  void resumeDownloads() {
    if (_isPaused && _isRunning) {
      _isPaused = false;
      _updateStatus('Resuming downloads...');
      _downloadFile(); // Restart the download cycle
    }
  }
  
  // Download file
  Future<void> _downloadFile() async {
    if (!_isRunning || _isPaused) return;
    
    _updateStatus('Downloading');
    _updateDownloadSpeed(0.0);
    
    _activeDownloads = List.generate(
      AppConstants.maxConcurrentDownloads,
      (_) => _performSingleDownload(),
    );
    
    try {
      await Future.wait(_activeDownloads!);
    } catch (e) {
      // Handle any errors from the concurrent downloads
      if (_isRunning) {
        _retryCount++;
        if (_retryCount < AppConstants.maxRetries) {
          _updateStatus(
            'Error: $e\nRetrying in ${AppConstants.retryDelay} seconds... (Attempt $_retryCount/${AppConstants.maxRetries})',
          );
          await Future.delayed(Duration(seconds: AppConstants.retryDelay));
          if (_isRunning && !_isPaused) _downloadFile();
        } else {
          _updateStatus(
            'Max retries reached. Waiting for next scheduled download...',
          );
          _retryCount = 0;
        }
      }
    }
  }
  
  // Perform a single download
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
        Duration(seconds: AppConstants.connectionTimeout),
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
              
              _updateDownloadSpeed(currentSpeed);
              _updateAverageSpeed(currentSpeed);
              
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
              _incrementDownloadCount();
              _updateStatus('Waiting for next download...');
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
  
  // Clean up temporary files
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
  
  // Update status
  void _updateStatus(String status) {
    _status = status;
    _statusController.add(status);
  }
  
  // Update download speed
  void _updateDownloadSpeed(double speed) {
    _currentSpeed = speed;
    _downloadSpeedController.add(speed);
  }
  
  // Update average speed
  void _updateAverageSpeed(double currentSpeed) {
    if (_downloadCount == 0) {
      _averageSpeed = currentSpeed;
    } else {
      _averageSpeed = (_averageSpeed * _downloadCount + currentSpeed) / (_downloadCount + 1);
    }
    _averageSpeedController.add(_averageSpeed);
  }
  
  // Increment download count
  void _incrementDownloadCount() {
    _downloadCount++;
    _downloadCountController.add(_downloadCount);
  }
  
  // Dispose resources
  void dispose() {
    _downloadTimer?.cancel();
    _cleanupFiles();
    _downloadSpeedController.close();
    _averageSpeedController.close();
    _downloadCountController.close();
    _statusController.close();
  }
} 