import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/enums.dart';
import '../constants/app_constants.dart';

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  final NetworkInfo _networkInfo = NetworkInfo();
  
  // Stream controllers
  final _connectionTypeController = StreamController<ConnectionType>.broadcast();
  final _hotspotActiveController = StreamController<bool>.broadcast();
  
  // Stream getters
  Stream<ConnectionType> get connectionTypeStream => _connectionTypeController.stream;
  Stream<bool> get hotspotActiveStream => _hotspotActiveController.stream;
  
  // Current values
  ConnectionType _currentConnectionType = ConnectionType.unknown;
  bool _isHotspotActive = false;
  Map<String, int> _lastByteCounts = {};
  DateTime _lastTrafficCheck = DateTime.now();
  
  // Getters for current values
  ConnectionType get connectionType => _currentConnectionType;
  bool get isHotspotActive => _isHotspotActive;
  
  // Singleton pattern
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal() {
    // Initialize the connectivity monitoring
    _initConnectivity();
    _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
    
    // Start hotspot monitoring
    _startHotspotMonitoring();
  }
  
  // Initialize connectivity
  Future<void> _initConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      await _updateConnectionStatus(result);
    } catch (e) {
      _connectionTypeController.add(ConnectionType.unknown);
      _currentConnectionType = ConnectionType.unknown;
    }
  }
  
  // Update connection status
  Future<void> _updateConnectionStatus(ConnectivityResult result) async {
    ConnectionType connectionType;
    
    switch (result) {
      case ConnectivityResult.mobile:
        connectionType = ConnectionType.mobile;
        break;
      case ConnectivityResult.wifi:
        connectionType = ConnectionType.wifi;
        break;
      case ConnectivityResult.none:
        connectionType = ConnectionType.none;
        break;
      default:
        connectionType = ConnectionType.unknown;
        break;
    }
    
    _currentConnectionType = connectionType;
    _connectionTypeController.add(connectionType);
  }
  
  // Start hotspot monitoring
  void _startHotspotMonitoring() {
    Timer.periodic(
      const Duration(seconds: AppConstants.hotspotCheckInterval),
      (_) => _checkHotspotStatus(),
    );
  }
  
  // Check if device is acting as a hotspot
  Future<void> _checkHotspotStatus() async {
    try {
      // Check if device is acting as a hotspot
      final wifiIP = await _networkInfo.getWifiIP();
      final wifiName = await _networkInfo.getWifiName();

      // Common hotspot IP patterns
      final isHotspotIP = wifiIP?.startsWith('192.168.43.') ?? false; // Android default
      final isHotspotName = wifiName?.toLowerCase().contains('android') ?? false;

      bool wasHotspotActive = _isHotspotActive;
      _isHotspotActive = isHotspotIP || isHotspotName;

      if (_isHotspotActive) {
        // Check for actual data usage
        final hasActiveTraffic = await _checkNetworkTraffic();
        _isHotspotActive = hasActiveTraffic;
      }
      
      // Only notify if there's a change
      if (wasHotspotActive != _isHotspotActive) {
        _hotspotActiveController.add(_isHotspotActive);
      }
    } catch (e) {
      print('Error checking hotspot status: $e');
    }
  }
  
  // Check network traffic to determine if hotspot is active
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
              final parts = line.trim().split(RegExp(r'\s+'));
              if (parts.length >= 10) {
                final interface = parts[0].replaceAll(':', '');
                final rxBytes = int.tryParse(parts[1]) ?? 0; // Received bytes
                final txBytes = int.tryParse(parts[9]) ?? 0; // Transmitted bytes
                currentByteCounts[interface] = rxBytes + txBytes;

                // Calculate traffic rate
                if (_lastByteCounts.containsKey(interface)) {
                  final bytesDiff = currentByteCounts[interface]! - _lastByteCounts[interface]!;
                  final timeDiff = now.difference(_lastTrafficCheck).inSeconds;
                  if (timeDiff > 0) {
                    final bytesPerSecond = bytesDiff ~/ timeDiff;
                    if (bytesPerSecond > AppConstants.trafficThreshold) {
                      hasSignificantTraffic = true;
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
  
  // Dispose resources
  void dispose() {
    _connectionTypeController.close();
    _hotspotActiveController.close();
  }
} 