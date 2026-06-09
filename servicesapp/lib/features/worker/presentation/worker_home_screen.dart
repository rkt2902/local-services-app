import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkerHomeScreen extends ConsumerWidget {
  const WorkerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LocalServices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: null,
          ),
        ],
      ),
      body: const Center(child: Text('Pedidos disponíveis — em breve')),
    );
  }
}
