import 'package:flutter/material.dart';

class AroniumPOSSimulator extends StatelessWidget {
  const AroniumPOSSimulator({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aronium POS Integration',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'This application monitors the Aronium POS database at:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'C:\\Users\\hp\\AppData\\Local\\Aronium\\Data\\pos.db',
              style: const TextStyle(fontFamily: 'Monospace', fontSize: 12),
            ),
            const SizedBox(height: 8),
            const Text(
              'To test this application, create sales in Aronium POS and they will appear here for fiscalization.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}
