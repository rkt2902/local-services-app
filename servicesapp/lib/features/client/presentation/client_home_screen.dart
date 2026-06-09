import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ClientHomeScreen extends ConsumerWidget {
  const ClientHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LocalServices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outlined),
            onPressed: () => context.push('/client/profile'),
          ),
        ],
      ),
      body: Center(
        child: TextButton(
          onPressed: () => context.push('/client/jobs'),
          child: const Text('Ver os meus pedidos →'),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/client/create-job'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
