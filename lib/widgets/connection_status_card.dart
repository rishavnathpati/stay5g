import 'package:flutter/material.dart';
import '../models/enums.dart';

class ConnectionStatusCard extends StatelessWidget {
  final ConnectionType connectionType;
  
  const ConnectionStatusCard({
    super.key,
    required this.connectionType,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              _getConnectionIcon(),
              size: 32,
              color: _getConnectionColor(context),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Network Type',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    connectionType.displayName,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  IconData _getConnectionIcon() {
    switch (connectionType) {
      case ConnectionType.mobile:
        return Icons.signal_cellular_alt;
      case ConnectionType.wifi:
        return Icons.wifi;
      case ConnectionType.none:
        return Icons.signal_cellular_off;
      case ConnectionType.unknown:
        return Icons.signal_cellular_connected_no_internet_4_bar;
    }
  }
  
  Color _getConnectionColor(BuildContext context) {
    switch (connectionType) {
      case ConnectionType.mobile:
        return Theme.of(context).colorScheme.primary;
      case ConnectionType.wifi:
        return Theme.of(context).colorScheme.secondary;
      case ConnectionType.none:
        return Theme.of(context).colorScheme.error;
      case ConnectionType.unknown:
        return Theme.of(context).colorScheme.tertiary;
    }
  }
} 