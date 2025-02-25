import 'dart:io';
import '../constants/app_constants.dart';

// Custom HTTP overrides for keep-alive and connection optimization
class CustomHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..connectionTimeout = const Duration(seconds: AppConstants.connectionTimeout)
      ..idleTimeout = const Duration(seconds: 60)
      ..maxConnectionsPerHost = AppConstants.maxConcurrentDownloads;
  }
} 