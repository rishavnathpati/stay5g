import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../constants/app_constants.dart';
import '../models/speed_test_result.dart';
import 'storage_service.dart';

class WebViewService {
  // WebView controller
  late final WebViewController _webViewController;
  
  // Timer for periodic tests
  Timer? _webviewTimer;
  DateTime? _nextWebviewTest;
  
  // Stream controllers
  final _statusController = StreamController<String>.broadcast();
  final _webviewVisibleController = StreamController<bool>.broadcast();
  final _lastResultController = StreamController<String>.broadcast();
  final _progressController = StreamController<double>.broadcast();
  
  // Stream getters
  Stream<String> get statusStream => _statusController.stream;
  Stream<bool> get webviewVisibleStream => _webviewVisibleController.stream;
  Stream<String> get lastResultStream => _lastResultController.stream;
  Stream<double> get progressStream => _progressController.stream;
  
  // Current values
  String _status = 'Idle';
  bool _isWebviewVisible = false;
  String _lastWebviewResult = 'No test run yet';
  double _webviewTestProgress = 0.0;
  
  // Getters for current values
  String get status => _status;
  bool get isWebviewVisible => _isWebviewVisible;
  String get lastWebviewResult => _lastWebviewResult;
  double get webviewTestProgress => _webviewTestProgress;
  WebViewController get webViewController => _webViewController;
  DateTime? get nextWebviewTest => _nextWebviewTest;
  
  // Singleton pattern
  static final WebViewService _instance = WebViewService._internal();
  factory WebViewService() => _instance;
  WebViewService._internal() {
    _initWebViewController();
  }
  
  // Initialize WebView controller
  void _initWebViewController() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setUserAgent('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36')
      ..enableZoom(false)
      ..addJavaScriptChannel(
        'FlutterApp',
        onMessageReceived: (JavaScriptMessage message) {
          print('Message from JavaScript: ${message.message}');
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            print('WebView started loading: $url');
            _updateStatus('Loading Fast.com...');
          },
          onProgress: (int progress) {
            print('WebView loading progress: $progress%');
            _updateStatus('Loading Fast.com... ($progress%)');
          },
          onPageFinished: (String url) {
            print('WebView finished loading: $url');
            _updateStatus('Fast.com loaded');
            
            // Inject JavaScript to help with debugging
            _webViewController.runJavaScriptReturningResult("""
              console.log = function(message) {
                FlutterApp.postMessage(message);
              };
            """);
          },
          onWebResourceError: (WebResourceError error) {
            print('WebView error: ${error.description} (${error.errorCode})');
            _updateLastResult('Error: ${error.description}');
            _setWebViewVisible(false);
            _updateStatus('Failed to load Fast.com');
          },
        ),
      );
  }
  
  // Start WebView timer for periodic tests
  void startWebViewTimer() {
    _webviewTimer?.cancel();
    _nextWebviewTest = DateTime.now().add(const Duration(seconds: AppConstants.webviewTestInterval));
    _webviewTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (_nextWebviewTest != null) {
          final remaining = _nextWebviewTest!.difference(DateTime.now());
          if (remaining.isNegative && !_isWebviewVisible) {
            startWebViewSpeedTest();
          } else {
            _updateProgress(1 - (remaining.inSeconds / AppConstants.webviewTestInterval));
          }
        }
      },
    );
  }
  
  // Stop WebView timer
  void stopWebViewTimer() {
    _webviewTimer?.cancel();
    _webviewTimer = null;
  }
  
  // Start a WebView speed test
  Future<void> startWebViewSpeedTest() async {
    _setWebViewVisible(true);
    _updateStatus('Running Fast.com speed test...');
    _updateLastResult('Test in progress...');
    
    // Load Fast.com
    _webViewController.loadRequest(Uri.parse(AppConstants.fastComUrl));
    
    // Wait for the test to complete
    Future.delayed(const Duration(seconds: AppConstants.webviewTestDuration), () async {
      // Check if the test is still running by looking for the progress indicator
      try {
        final isTestRunning = await _webViewController.runJavaScriptReturningResult("""
          (function() {
            return document.querySelector('.progress-indicator') !== null ||
                   document.querySelector('.loading-speed-text') !== null;
          })();
        """);
        
        // If test is still running, wait a bit longer
        if (isTestRunning.toString() == 'true') {
          print("Fast.com test still running, waiting longer...");
          _updateStatus('Test still running, please wait...');
          
          // Wait additional time
          Future.delayed(const Duration(seconds: 15), () {
            _completeWebViewTest();
          });
        } else {
          // Test appears to be complete
          _completeWebViewTest();
        }
      } catch (e) {
        print("Error checking test status: $e");
        _completeWebViewTest(); // Proceed anyway
      }
    });
  }
  
  // Complete the WebView speed test
  Future<void> _completeWebViewTest() async {
    double downloadSpeed = 0.0;
    String unit = "Mbps";
    
    // Extract the speed test result from Fast.com using JavaScript
    try {
      // First try to get the result from the main result element
      final resultScript = """
        (function() {
          // Try to get the speed value
          var speedElement = document.querySelector('.speed-results-container .speed-value');
          var unitElement = document.querySelector('.speed-results-container .speed-units');
          
          if (speedElement && unitElement) {
            return {
              speed: speedElement.textContent.trim(),
              unit: unitElement.textContent.trim()
            };
          }
          
          // Fallback for other possible selectors
          speedElement = document.querySelector('.speed-value');
          unitElement = document.querySelector('.speed-units');
          
          if (speedElement && unitElement) {
            return {
              speed: speedElement.textContent.trim(),
              unit: unitElement.textContent.trim()
            };
          }
          
          return null;
        })();
      """;
      
      final result = await _webViewController.runJavaScriptReturningResult(resultScript);
      print("Extracted test result: $result");
      
      if (result != null && result != "null") {
        // Parse the result which is a JSON object
        final Map<String, dynamic> resultMap = json.decode(result.toString());
        if (resultMap.containsKey('speed') && resultMap.containsKey('unit')) {
          downloadSpeed = double.tryParse(resultMap['speed'].toString()) ?? 0.0;
          unit = resultMap['unit'].toString();
          
          _updateLastResult('$downloadSpeed $unit');
        }
      }
    } catch (e) {
      print("JavaScript extraction error: $e");
      // Try a simpler approach if the first one fails
      try {
        final simpleResult = await _webViewController.runJavaScriptReturningResult(
          "document.querySelector('.speed-value')?.textContent || 'Not found'"
        );
        print("Simple extraction result: $simpleResult");
        
        if (simpleResult != null && simpleResult.toString() != "Not found") {
          downloadSpeed = double.tryParse(simpleResult.toString().trim()) ?? 0.0;
          _updateLastResult('$downloadSpeed $unit');
        }
      } catch (e) {
        print("Simple JavaScript extraction error: $e");
      }
    }
    
    _setWebViewVisible(false);
    _nextWebviewTest = DateTime.now().add(const Duration(seconds: AppConstants.webviewTestInterval));
    _updateStatus('Fast.com test completed');
    
    // Save the test result
    final testResult = SpeedTestResult(
      timestamp: DateTime.now(),
      type: 'fast.com',
      download: downloadSpeed,
      unit: unit,
    );
    
    StorageService().saveTestResult(testResult);
  }
  
  // Update status
  void _updateStatus(String status) {
    _status = status;
    _statusController.add(status);
  }
  
  // Update WebView visibility
  void _setWebViewVisible(bool visible) {
    _isWebviewVisible = visible;
    _webviewVisibleController.add(visible);
  }
  
  // Update last result
  void _updateLastResult(String result) {
    _lastWebviewResult = result;
    _lastResultController.add(result);
  }
  
  // Update progress
  void _updateProgress(double progress) {
    _webviewTestProgress = progress;
    _progressController.add(progress);
  }
  
  // Dispose resources
  void dispose() {
    _webviewTimer?.cancel();
    _statusController.close();
    _webviewVisibleController.close();
    _lastResultController.close();
    _progressController.close();
  }
} 