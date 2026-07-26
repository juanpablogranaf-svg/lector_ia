import 'package:flutter/material.dart';

class ScanProgressIndicator extends StatelessWidget {
  final int found;
  const ScanProgressIndicator({super.key, required this.found});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: cs.primary.withOpacity(0.1),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(cs.primary),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Escaneando... $found libro${found == 1 ? '' : 's'} encontrado${found == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
