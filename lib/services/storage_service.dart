import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/speed_test_result.dart';
import '../constants/app_constants.dart';

class StorageService {
  // Stream controllers
  final _testHistoryController = StreamController<List<SpeedTestResult>>.broadcast();
  
  // Stream getters
  Stream<List<SpeedTestResult>> get testHistoryStream => _testHistoryController.stream;
  
  // Current values
  List<SpeedTestResult> _testHistory = [];
  
  // Getters for current values
  List<SpeedTestResult> get testHistory => _testHistory;
  
  // Singleton pattern
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal() {
    _loadTestHistory();
  }
  
  // Load test history from SharedPreferences
  Future<void> _loadTestHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(AppConstants.historyPrefsKey);
      if (historyJson != null) {
        final List<dynamic> decoded = json.decode(historyJson);
        _testHistory = decoded
            .map((item) => SpeedTestResult.fromJson(item))
            .toList();
        _testHistoryController.add(_testHistory);
      }
    } catch (e) {
      print('Error loading test history: $e');
    }
  }
  
  // Save a test result
  Future<void> saveTestResult(SpeedTestResult result) async {
    _testHistory.insert(0, result);
    if (_testHistory.length > AppConstants.maxHistoryItems) {
      _testHistory.removeLast();
    }
    _testHistoryController.add(_testHistory);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonData = json.encode(_testHistory.map((item) => item.toJson()).toList());
      await prefs.setString(AppConstants.historyPrefsKey, jsonData);
    } catch (e) {
      print('Error saving test history: $e');
    }
  }
  
  // Clear test history
  Future<void> clearTestHistory() async {
    _testHistory.clear();
    _testHistoryController.add(_testHistory);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConstants.historyPrefsKey);
    } catch (e) {
      print('Error clearing test history: $e');
    }
  }
  
  // Dispose resources
  void dispose() {
    _testHistoryController.close();
  }
} 