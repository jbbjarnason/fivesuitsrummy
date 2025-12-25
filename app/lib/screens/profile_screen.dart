import 'package:beamer/beamer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Map<String, dynamic>? _stats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final api = ref.read(apiServiceProvider);
    final stats = await api.getMyStats();
    if (mounted) {
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.beamToNamed('/games'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile header
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: Theme.of(context).primaryColor,
                      child: Text(
                        (user?['username'] as String? ?? '?')[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?['displayName'] as String? ?? 'Unknown',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '@${user?['username'] ?? ''}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user?['email'] as String? ?? '',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Stats section
            Text(
              'Game Statistics',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_stats == null)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No statistics yet. Play some games!'),
                ),
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _StatRow(
                        icon: Icons.games,
                        label: 'Games Played',
                        value: '${_stats!['gamesPlayed'] ?? 0}',
                      ),
                      const Divider(),
                      _StatRow(
                        icon: Icons.emoji_events,
                        label: 'Games Won',
                        value: '${_stats!['gamesWon'] ?? 0}',
                        valueColor: Colors.amber,
                      ),
                      const Divider(),
                      _StatRow(
                        icon: Icons.percent,
                        label: 'Win Rate',
                        value: _calculateWinRate(),
                        valueColor: Colors.green,
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // Account info section
            Text(
              'Account Information',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _InfoRow(
                      icon: Icons.person,
                      label: 'User ID',
                      value: _truncateId(auth.userId ?? ''),
                    ),
                    const Divider(),
                    _InfoRow(
                      icon: Icons.calendar_today,
                      label: 'Member Since',
                      value: _formatDate(user?['createdAt']),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Actions
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Logout'),
                      content: const Text('Are you sure you want to logout?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Logout'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && mounted) {
                    await ref.read(authProvider).logout();
                    if (mounted) {
                      // ignore: use_build_context_synchronously
                      context.beamToNamed('/login');
                    }
                  }
                },
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _calculateWinRate() {
    final played = _stats?['gamesPlayed'] as int? ?? 0;
    final won = _stats?['gamesWon'] as int? ?? 0;
    if (played == 0) return '0%';
    return '${((won / played) * 100).toStringAsFixed(1)}%';
  }

  String _truncateId(String id) {
    if (id.length > 8) return '${id.substring(0, 8)}...';
    return id;
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'Unknown';
    try {
      DateTime dt;
      if (date is String) {
        dt = DateTime.parse(date);
      } else if (date is int) {
        dt = DateTime.fromMillisecondsSinceEpoch(date);
      } else {
        return 'Unknown';
      }
      return '${dt.month}/${dt.day}/${dt.year}';
    } catch (e) {
      return 'Unknown';
    }
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 24, color: Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 24, color: Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
