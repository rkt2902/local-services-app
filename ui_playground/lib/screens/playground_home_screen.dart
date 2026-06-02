import 'package:flutter/material.dart';

class PlaygroundHomeScreen extends StatelessWidget {
  const PlaygroundHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('UI Playground')),
      body: const Center(
        child: Text('Nenhum ecrã disponível ainda.'),
      ),
    );
  }
}
