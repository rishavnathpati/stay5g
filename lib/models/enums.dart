// Speed Test Modes
enum SpeedTestMode {
  download,
  fastCom
}

// Connection Types
enum ConnectionType {
  mobile,
  wifi,
  none,
  unknown
}

extension ConnectionTypeExtension on ConnectionType {
  String get displayName {
    switch (this) {
      case ConnectionType.mobile:
        return 'Mobile Network';
      case ConnectionType.wifi:
        return 'WiFi';
      case ConnectionType.none:
        return 'No Connection';
      case ConnectionType.unknown:
        return 'Unknown';
    }
  }
  
  bool get isConnected => this == ConnectionType.mobile || this == ConnectionType.wifi;
} 