class SpeedTestResult {
  final DateTime timestamp;
  final String type;
  final double download;
  final double upload;
  final int latency;
  final String unit;

  SpeedTestResult({
    required this.timestamp,
    required this.type,
    required this.download,
    this.upload = 0.0,
    this.latency = 0,
    this.unit = 'Mbps',
  });

  // Create from JSON (for SharedPreferences storage)
  factory SpeedTestResult.fromJson(Map<String, dynamic> json) {
    return SpeedTestResult(
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      type: json['type'] as String,
      download: json['download'] as double,
      upload: json['upload'] as double? ?? 0.0,
      latency: json['latency'] as int? ?? 0,
      unit: json['unit'] as String? ?? 'Mbps',
    );
  }

  // Convert to JSON (for SharedPreferences storage)
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.millisecondsSinceEpoch,
      'type': type,
      'download': download,
      'upload': upload,
      'latency': latency,
      'unit': unit,
    };
  }
} 