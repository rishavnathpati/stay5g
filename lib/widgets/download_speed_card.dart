import 'package:flutter/material.dart';

class DownloadSpeedCard extends StatelessWidget {
  final String status;
  final double currentSpeed;
  final double averageSpeed;
  final int downloadCount;
  
  const DownloadSpeedCard({
    super.key,
    required this.status,
    required this.currentSpeed,
    required this.averageSpeed,
    required this.downloadCount,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Status: $status',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            Text(
              '${currentSpeed.toStringAsFixed(2)} MB/s',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Current Speed',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (downloadCount > 0) ...[
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text(
                        '${averageSpeed.toStringAsFixed(2)} MB/s',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                      Text(
                        'Average Speed',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      Text(
                        '$downloadCount',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                      Text(
                        'Downloads',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
} 