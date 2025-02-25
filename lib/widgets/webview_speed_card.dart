import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebViewSpeedCard extends StatelessWidget {
  final bool isWebviewVisible;
  final WebViewController webViewController;
  final String status;
  final String lastResult;
  final DateTime? nextTest;
  final double progress;
  final VoidCallback onRunTest;
  
  const WebViewSpeedCard({
    super.key,
    required this.isWebviewVisible,
    required this.webViewController,
    required this.status,
    required this.lastResult,
    this.nextTest,
    required this.progress,
    required this.onRunTest,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Column(
        children: [
          if (isWebviewVisible)
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(
                    controller: webViewController,
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Card(
                      color: Theme.of(context).colorScheme.surface.withOpacity(0.8),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          status,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Fast.com Speed Test',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 2,
                      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Text(
                              'Last Result:',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              lastResult,
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (nextTest != null) ...[
                      Text(
                        'Next automatic test in:',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatRemainingTime(nextTest!),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (isWebviewVisible)
            LinearProgressIndicator(
              value: null,
              backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
        ],
      ),
    );
  }
  
  String _formatRemainingTime(DateTime nextTest) {
    final difference = nextTest.difference(DateTime.now());
    if (difference.isNegative) {
      return '0:00';
    }
    
    final minutes = difference.inMinutes;
    final seconds = (difference.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}