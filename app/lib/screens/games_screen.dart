import 'package:beamer/beamer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart' show nudgeShakeKey;
import '../providers/providers.dart';

class GamesScreen extends ConsumerStatefulWidget {
  const GamesScreen({super.key});

  @override
  ConsumerState<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends ConsumerState<GamesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gamesProvider).loadGames();
      ref.read(notificationsProvider).loadNotifications();
      _setupNotificationCallbacks();
    });
  }

  void _setupNotificationCallbacks() {
    final notifications = ref.read(notificationsProvider);

    notifications.onNotificationReceived = (message) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => _showNotifications(context),
            ),
          ),
        );
      }
    };

    notifications.onGameDeleted = (gameId, deletedBy) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Game was deleted by $deletedBy')),
        );
        // Refresh games list
        ref.read(gamesProvider).loadGames();
      }
    };

    notifications.onGamesListChanged = () {
      if (mounted) {
        // Refresh games list when we get invited or game is deleted
        ref.read(gamesProvider).loadGames();
      }
    };

    notifications.onFriendListChanged = () {
      if (mounted) {
        // Refresh friends list when friend request received/accepted
        ref.read(friendsProvider).loadFriends();
      }
    };

    notifications.onNudgeReceived = () {
      // Trigger shake animation on the entire app
      nudgeShakeKey.currentState?.shake();
    };
  }

  Future<void> _createGame() async {
    final games = ref.read(gamesProvider);
    final gameId = await games.createGame();
    if (gameId != null && mounted) {
      context.beamToNamed('/games/$gameId');
    }
  }

  void _showNotifications(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final notifications = ref.watch(notificationsProvider);
          return DraggableScrollableSheet(
            initialChildSize: 0.5,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) => Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Text(
                        'Notifications',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      if (notifications.notifications.isNotEmpty)
                        TextButton(
                          onPressed: () async {
                            await ref.read(notificationsProvider).clearAll();
                          },
                          child: const Text('Clear All'),
                        ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: notifications.notifications.isEmpty
                      ? const Center(
                          child: Text(
                            'No notifications',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: notifications.notifications.length,
                          itemBuilder: (context, index) {
                            final notification = notifications.notifications[index];
                            return _buildNotificationItem(context, ref, notification);
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildNotificationItem(BuildContext context, WidgetRef ref, Map<String, dynamic> notification) {
    final type = notification['type'] as String? ?? '';
    final status = notification['status'] as String? ?? 'pending';
    final fromUser = notification['fromUser'] as Map<String, dynamic>?;
    final game = notification['game'] as Map<String, dynamic>?;
    final isUnread = status == 'pending';
    final notificationId = notification['id'] as String;

    String title = 'Notification';
    String subtitle = '';
    IconData icon = Icons.notifications;

    switch (type) {
      case 'game_invitation':
        title = 'Game Invitation';
        subtitle = fromUser != null
            ? '${fromUser['displayName'] ?? fromUser['username']} invited you to a game'
            : 'You were invited to a game';
        icon = Icons.games;
        break;
      case 'friend_request':
        title = 'Friend Request';
        subtitle = fromUser != null
            ? '${fromUser['displayName'] ?? fromUser['username']} sent you a friend request'
            : 'You received a friend request';
        icon = Icons.person_add;
        break;
      case 'friend_accepted':
        title = 'Friend Accepted';
        subtitle = fromUser != null
            ? '${fromUser['displayName'] ?? fromUser['username']} accepted your friend request'
            : 'Your friend request was accepted';
        icon = Icons.people;
        break;
      case 'friend_blocked':
        title = 'Friend Removed';
        subtitle = 'A friend relationship was ended';
        icon = Icons.person_off;
        break;
    }

    void handleTap() {
      ref.read(notificationsProvider).markAsRead(notificationId);
      Navigator.pop(context);

      // Navigate based on notification type
      switch (type) {
        case 'game_invitation':
          if (game != null) {
            context.beamToNamed('/games/${game['id']}');
          }
          break;
        case 'friend_request':
          context.beamToNamed('/friends?tab=requests');
          break;
        case 'friend_accepted':
        case 'friend_blocked':
          context.beamToNamed('/friends');
          break;
      }
    }

    return Dismissible(
      key: Key(notificationId),
      direction: DismissDirection.horizontal,
      onDismissed: (_) {
        ref.read(notificationsProvider).deleteNotification(notificationId);
      },
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isUnread ? Colors.blue.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2),
          child: Icon(icon, color: isUnread ? Colors.blue : Colors.grey),
        ),
        title: Text(
          title,
          style: TextStyle(fontWeight: isUnread ? FontWeight.bold : FontWeight.normal),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: handleTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final games = ref.watch(gamesProvider);
    final notifications = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'logo/five_crowns_icon_96.png',
              width: 32,
              height: 32,
            ),
            const SizedBox(width: 8),
            const Text('Five Crowns'),
          ],
        ),
        actions: [
          // Notifications button with badge
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () => _showNotifications(context),
                tooltip: 'Notifications',
              ),
              if (notifications.unreadCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '${notifications.unreadCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.leaderboard_outlined),
            onPressed: () => context.beamToNamed('/stats'),
            tooltip: 'My Stats',
          ),
          IconButton(
            icon: const Icon(Icons.people),
            onPressed: () => context.beamToNamed('/friends'),
            tooltip: 'Friends',
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.beamToNamed('/profile'),
            tooltip: 'My Profile',
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (games.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final gamesList = games.games;
          if (gamesList.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.games, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No games yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _createGame,
                    icon: const Icon(Icons.add),
                    label: const Text('Create Game'),
                  ),
                ],
              ),
            );
          }

          final auth = ref.read(authProvider);
          final myUserId = auth.userId;

          return RefreshIndicator(
            onRefresh: () => games.loadGames(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: gamesList.length,
              itemBuilder: (context, index) {
                final game = gamesList[index];
                // Safely access game data
                final gameId = game['id']?.toString() ?? 'unknown';
                final players = (game['players'] as List?) ?? [];
                final status = game['status']?.toString() ?? 'lobby';
                final maxPlayers = (game['maxPlayers'] as int?) ?? 4;
                final dateStr = _formatDate(game['createdAt']);
                final createdBy = game['createdBy']?.toString();
                final isHost = createdBy == myUserId;
                final isFinished = status == 'finished';
                final canSwipe = !isFinished && status == 'lobby';

                final card = Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text('Game ${gameId.length > 8 ? gameId.substring(0, 8) : gameId}'),
                    subtitle: Text(
                      '${players.length}/$maxPlayers players - ${_statusLabel(status)}${dateStr.isNotEmpty ? '\nStarted: $dateStr' : ''}',
                    ),
                    isThreeLine: dateStr.isNotEmpty,
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () => context.beamToNamed('/games/$gameId'),
                  ),
                );

                if (!canSwipe) {
                  return card;
                }

                return Dismissible(
                  key: Key(gameId),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isHost ? Colors.red : Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(
                          isHost ? Icons.delete : Icons.exit_to_app,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isHost ? 'Delete' : 'Leave',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  confirmDismiss: (direction) async {
                    final action = isHost ? 'delete' : 'leave';
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('${action[0].toUpperCase()}${action.substring(1)} Game?'),
                        content: Text(
                          isHost
                              ? 'Are you sure you want to delete this game? All players will be notified.'
                              : 'Are you sure you want to leave this game?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: TextButton.styleFrom(
                              foregroundColor: isHost ? Colors.red : Colors.orange,
                            ),
                            child: Text(action[0].toUpperCase() + action.substring(1)),
                          ),
                        ],
                      ),
                    );
                    return confirmed ?? false;
                  },
                  onDismissed: (direction) async {
                    if (isHost) {
                      await ref.read(gamesProvider).deleteGame(gameId);
                    } else {
                      await ref.read(gamesProvider).leaveGame(gameId);
                    }
                  },
                  child: card,
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: games.games.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _createGame,
              icon: const Icon(Icons.add),
              label: const Text('New Game'),
            )
          : null,
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'lobby':
        return 'Waiting for players';
      case 'active':
        return 'In progress';
      case 'finished':
        return 'Finished';
      default:
        return status;
    }
  }

  String _formatDate(dynamic dateValue) {
    if (dateValue == null) return '';
    try {
      DateTime date;
      if (dateValue is int) {
        // Unix timestamp in milliseconds
        date = DateTime.fromMillisecondsSinceEpoch(dateValue).toLocal();
      } else if (dateValue is String) {
        // Try ISO 8601 format first, then Unix timestamp
        if (dateValue.contains('-') || dateValue.contains('T')) {
          date = DateTime.parse(dateValue).toLocal();
        } else {
          final ms = int.tryParse(dateValue);
          if (ms == null) return '';
          date = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
        }
      } else {
        return '';
      }
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '${months[date.month - 1]} ${date.day}, ${date.year} $hour:$minute';
    } catch (e) {
      return '';
    }
  }
}
