import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../jobs/data/job_model.dart';
import '../../proposals/data/proposal_model.dart';

class WorkerHelpRequestsLobbyScreen extends ConsumerWidget {
  const WorkerHelpRequestsLobbyScreen({
    super.key,
    required this.job,
    required this.proposal,
  });

  final JobRequest job;
  final JobProposal proposal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Equipa')),
      body: const Center(child: Text('Em construção')),
    );
  }
}
