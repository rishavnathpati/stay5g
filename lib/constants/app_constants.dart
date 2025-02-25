// Constants for the Stay5G app
class AppConstants {
  // Network constants
  static const int maxConcurrentDownloads = 1;
  static const int connectionTimeout = 10; // seconds
  static const int maxRetries = 3;
  static const int retryDelay = 5; // seconds
  static const int hotspotCheckInterval = 2; // seconds
  static const int trafficThreshold = 50000; // bytes per second (50KB/s)
  
  // WebView constants
  static const int webviewTestInterval = 300; // 5 minutes in seconds
  static const int webviewTestDuration = 30; // seconds
  static const String fastComUrl = 'https://fast.com';
  
  // Storage constants
  static const int maxHistoryItems = 100;
  static const String historyPrefsKey = 'test_history';
  
  // Test URLs
  static const List<String> testUrls = [
    'https://testfile.org/1.3GBiconpng',
    'https://speed.cloudflare.com/__down?bytes=100000000',
    'https://speed.hetzner.de/100MB.bin',
  ];
} 