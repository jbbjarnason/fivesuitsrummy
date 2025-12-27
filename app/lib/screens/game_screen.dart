import 'dart:async';

import 'package:beamer/beamer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fivecrowns_core/fivecrowns_core.dart' show MeldType;
import '../main.dart' show themeProvider;
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/card_widget.dart';
import '../widgets/tutorial_overlay.dart';
import '../widgets/livekit_controls.dart';

class GameScreen extends ConsumerStatefulWidget {
  final String gameId;

  const GameScreen({super.key, required this.gameId});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  // Track selected cards by their index in game.hand (not by string value)
  // This allows selecting duplicate cards like two 7♠
  final Set<int> _selectedCardIndices = {};
  // Track melds by card indices in game.hand
  final List<List<int>> _meldIndices = [];
  bool _showTutorial = false;

  // Lay off target selection
  int? _layOffTargetPlayerIndex;
  int? _layOffTargetMeldIndex;

  // Store provider references for safe dispose
  late final GameProvider _game;
  late final LiveKitProvider _liveKit;

  // Turn timer for nudge feature
  String? _lastCurrentPlayerId;
  DateTime? _turnStartTime;
  bool _canNudge = false;
  Timer? _nudgeTimer;

  // Hand reordering - tracks display order using card strings
  // This preserves order across draws/discards since we track by card value, not index
  final List<String> _handCardOrder = [];

  @override
  void initState() {
    super.initState();
    // Store references before any async operations
    _game = ref.read(gameProvider);
    _liveKit = ref.read(liveKitProvider);

    // Start timer to check for nudge eligibility
    _nudgeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkNudgeEligibility();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = ref.read(authProvider);
      _game.setUserId(auth.userId!);
      _game.joinGame(widget.gameId);

      // Connect to LiveKit for audio/video
      final api = ref.read(apiServiceProvider);
      _liveKit.connect(
            api: api,
            gameId: widget.gameId,
          );

      // Show tutorial on first play
      if (await TutorialOverlay.shouldShow()) {
        setState(() => _showTutorial = true);
      }
    });
  }

  void _checkNudgeEligibility() {
    final game = ref.read(gameProvider);
    final currentPlayerId = game.currentPlayerId;
    final auth = ref.read(authProvider);

    // Reset timer if turn changed
    if (currentPlayerId != _lastCurrentPlayerId) {
      _lastCurrentPlayerId = currentPlayerId;
      _turnStartTime = DateTime.now();
      if (_canNudge) {
        setState(() => _canNudge = false);
      }
    }

    // Check if 10 seconds have passed and it's not our turn
    if (_turnStartTime != null &&
        currentPlayerId != null &&
        currentPlayerId != auth.userId &&
        !_canNudge) {
      final elapsed = DateTime.now().difference(_turnStartTime!);
      if (elapsed.inSeconds >= 10) {
        setState(() => _canNudge = true);
      }
    }
  }

  /// Update hand card order when hand changes
  /// Preserves user's custom ordering by tracking cards by their string value
  void _updateHandCardOrder(List<String> hand) {
    final handSet = hand.toSet();
    final orderSet = _handCardOrder.toSet();

    // Remove cards that are no longer in hand (discarded/laid)
    _handCardOrder.removeWhere((card) => !handSet.contains(card));

    // Add new cards at the end (drawn cards)
    for (final card in hand) {
      if (!orderSet.contains(card)) {
        _handCardOrder.add(card);
      }
    }
  }

  /// Get display order as indices into the hand list
  List<int> _getHandDisplayOrder(List<String> hand) {
    _updateHandCardOrder(hand);

    // Convert card strings to indices
    final order = <int>[];
    for (final card in _handCardOrder) {
      final index = hand.indexOf(card);
      if (index != -1) {
        order.add(index);
      }
    }

    // Add any cards not in our order (shouldn't happen, but be safe)
    for (int i = 0; i < hand.length; i++) {
      if (!order.contains(i)) {
        order.add(i);
      }
    }

    return order;
  }

  /// Get the wild rank name for a given round number
  String _getWildRankName(int roundNumber) {
    final wildValue = roundNumber + 2; // Round 1 = 3s, Round 4 = 6s, etc.
    return switch (wildValue) {
      3 => '3',
      4 => '4',
      5 => '5',
      6 => '6',
      7 => '7',
      8 => '8',
      9 => '9',
      10 => '10',
      11 => 'J',
      12 => 'Q',
      13 => 'K',
      _ => '?',
    };
  }

  /// Reorder cards in hand (visual only - doesn't affect server state)
  void _reorderHand(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _handCardOrder.removeAt(oldIndex);
      _handCardOrder.insert(newIndex, item);
    });
  }

  /// Reconnect WebSocket and LiveKit after error dismissal
  Future<void> _reconnectAfterError() async {
    final game = ref.read(gameProvider);
    game.clearError();

    // Reconnect WebSocket
    game.joinGame(widget.gameId);

    // Reconnect LiveKit
    final api = ref.read(apiServiceProvider);
    final liveKit = ref.read(liveKitProvider);
    await liveKit.disconnect();
    liveKit.connect(
      api: api,
      gameId: widget.gameId,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reconnecting...')),
      );
    }
  }

  Future<void> _nudgeActivePlayer() async {
    final game = ref.read(gameProvider);
    final success = await game.nudgePlayer(widget.gameId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'Nudge sent!' : 'Failed to nudge')),
      );
      if (success) {
        setState(() => _canNudge = false);
        _turnStartTime = DateTime.now(); // Reset timer after nudge
      }
    }
  }

  @override
  void dispose() {
    _nudgeTimer?.cancel();
    _game.leaveGame();
    _liveKit.disconnect();
    super.dispose();
  }

  void _toggleCardSelection(int cardIndex) {
    setState(() {
      if (_selectedCardIndices.contains(cardIndex)) {
        _selectedCardIndices.remove(cardIndex);
      } else {
        _selectedCardIndices.add(cardIndex);
      }
    });
  }

  /// Convert selected card indices to card strings using the game hand
  List<String> _getSelectedCards(List<String> hand) {
    return _selectedCardIndices.map((i) => hand[i]).toList();
  }

  /// Convert meld indices to card strings
  List<List<String>> _getMelds(List<String> hand) {
    return _meldIndices.map((meld) => meld.map((i) => hand[i]).toList()).toList();
  }

  void _createMeldFromSelection() {
    if (_selectedCardIndices.length >= 3) {
      setState(() {
        _meldIndices.add(_selectedCardIndices.toList());
        _selectedCardIndices.clear();
      });
    }
  }

  void _clearMelds() {
    setState(() {
      _meldIndices.clear();
      _selectedCardIndices.clear();
      _layOffTargetPlayerIndex = null;
      _layOffTargetMeldIndex = null;
    });
  }

  void _selectMeldForLayOff(int playerIndex, int meldIndex) {
    setState(() {
      if (_layOffTargetPlayerIndex == playerIndex && _layOffTargetMeldIndex == meldIndex) {
        // Deselect if already selected
        _layOffTargetPlayerIndex = null;
        _layOffTargetMeldIndex = null;
      } else {
        _layOffTargetPlayerIndex = playerIndex;
        _layOffTargetMeldIndex = meldIndex;
      }
    });
  }

  void _layOffCards() {
    final game = ref.read(gameProvider);
    if (_layOffTargetPlayerIndex != null &&
        _layOffTargetMeldIndex != null &&
        _selectedCardIndices.isNotEmpty) {
      final selectedCards = _getSelectedCards(game.hand);
      game.layOff(
            _layOffTargetPlayerIndex!,
            _layOffTargetMeldIndex!,
            selectedCards,
          );
      setState(() {
        _selectedCardIndices.clear();
        _layOffTargetPlayerIndex = null;
        _layOffTargetMeldIndex = null;
      });
    }
  }

  void _layMelds() {
    final game = ref.read(gameProvider);
    if (_meldIndices.isNotEmpty) {
      final melds = _getMelds(game.hand);
      game.layMelds(melds);
      _clearMelds();
    }
  }

  void _goOut(String discardCard) {
    final game = ref.read(gameProvider);
    final melds = _getMelds(game.hand);
    if (game.canGoOut(melds, discardCard)) {
      game.goOut(melds, discardCard);
      _clearMelds();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot go out - invalid melds or cards remaining')),
      );
    }
  }

  String _getWhoseTurnText(game) {
    final currentPlayerId = game.currentPlayerId;
    if (currentPlayerId == null) return "Waiting...";

    // Find current player
    final players = game.players as List<Map<String, dynamic>>;
    final currentPlayer = players.where((p) => p['id'] == currentPlayerId).firstOrNull;

    if (currentPlayer == null) return "Waiting...";

    final displayName = currentPlayer['displayName'] as String?;
    final username = currentPlayer['username'] as String?;
    var name = displayName ?? username ?? 'Player ${(currentPlayer['seat'] as int? ?? 0) + 1}';
    // Cap name to 10 characters
    if (name.length > 10) {
      name = '${name.substring(0, 9)}…';
    }
    return "$name's turn";
  }

  void _showScoreboard(game) {
    final sortedPlayers = List<Map<String, dynamic>>.from(game.players)
      ..sort((a, b) => (a['score'] as int).compareTo(b['score'] as int));
    final myId = ref.read(authProvider).userId;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.leaderboard_rounded),
            const SizedBox(width: 8),
            const Text('Scoreboard'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: sortedPlayers.asMap().entries.map((entry) {
            final rank = entry.key + 1;
            final player = entry.value;
            final isMe = player['id'] == myId;
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: isMe ? AppTheme.primary.withValues(alpha: 0.1) : null,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: rank == 1 ? AppTheme.success : Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        '$rank',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: rank == 1 ? Colors.white : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isMe ? 'You' : (player['displayName'] as String? ?? player['username'] as String? ?? 'Player ${(player['seat'] as int) + 1}'),
                      style: TextStyle(
                        fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  Text(
                    '${player['score']} pts',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: rank == 1 ? AppTheme.success : null,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            'Round ${game.roundNumber}/11',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppTheme.primary,
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            ref.read(gameProvider).leaveGame();
            context.beamToNamed('/games');
          },
        ),
        actions: [
          const SizedBox(width: 8), // Spacing between title and controls
          // LiveKit audio controls (compact)
          LiveKitControls(
            gameId: widget.gameId,
            activePlayerId: game.currentPlayerId,
          ),
          // Overflow menu for less critical actions
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'help':
                  setState(() => _showTutorial = true);
                  break;
                case 'theme':
                  ref.read(themeProvider).toggle();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'help',
                child: Row(
                  children: const [
                    Icon(Icons.help_outline, size: 20),
                    SizedBox(width: 8),
                    Text('How to play'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'theme',
                child: Row(
                  children: [
                    Icon(
                      ref.watch(themeProvider).isDark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(ref.watch(themeProvider).isDark ? 'Light mode' : 'Dark mode'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Builder(
              builder: (context) {
                if (game.error != null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text('Error: ${game.error}', style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _reconnectAfterError,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reconnect'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                if (game.gameStatus == 'lobby') {
                  return const Center(child: Text('Waiting for game to start...'));
                }

                if (game.gameStatus == 'finished') {
                  return _buildGameEndScreen(game);
                }

                return Column(
                  children: [
                    // Scrollable content
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            // Game info (turn status)
                            _buildGameInfo(game),
                            // Draw piles and active player video
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Active player video
                                const ActivePlayerVideo(),
                                const SizedBox(width: 16),
                                // Draw piles
                                _buildDrawPiles(game),
                              ],
                            ),
                            // Table melds (all players' melds - for lay off)
                            _buildTableMelds(game),
                            // My melds staging area
                            if (_meldIndices.isNotEmpty) _buildMeldsStaging(game),
                            // My hand
                            _buildMyHand(game),
                          ],
                        ),
                      ),
                    ),
                    // Action buttons (fixed at bottom)
                    _buildActionButtons(game),
                  ],
                );
              },
            ),
            // Tutorial overlay
            if (_showTutorial)
              TutorialOverlay(
                roundNumber: game.roundNumber,
                onDismiss: () => setState(() => _showTutorial = false),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameInfo(game) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          // Last action log
          if (game.lastAction != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 16,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      game.lastAction!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showGameLog(game),
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (game.isFinalTurnPhase)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.warning,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'FINAL TURNS',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: game.isMyTurn
                      ? AppTheme.success.withValues(alpha: 0.15)
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: game.isMyTurn ? AppTheme.success : Theme.of(context).dividerColor,
                  ),
                ),
                child: Text(
                  game.isMyTurn
                      ? "Your turn: ${game.turnPhase == 'mustDraw' ? 'Draw' : 'Discard'}"
                      : _getWhoseTurnText(game),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: game.isMyTurn ? AppTheme.success : Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ),
              // Nudge button (appears after 10 seconds when not my turn)
              if (_canNudge && !game.isMyTurn)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ElevatedButton.icon(
                    onPressed: _nudgeActivePlayer,
                    icon: const Icon(Icons.notifications_active, size: 16),
                    label: const Text('Nudge'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showGameLog(game) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history_rounded),
                const SizedBox(width: 8),
                const Text(
                  'Game Log',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                reverse: true,
                itemCount: game.gameLog.length,
                itemBuilder: (context, index) {
                  final reversedIndex = game.gameLog.length - 1 - index;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      game.gameLog[reversedIndex],
                      style: TextStyle(
                        color: index == 0
                            ? Theme.of(context).textTheme.bodyLarge?.color
                            : Theme.of(context).textTheme.bodySmall?.color,
                        fontWeight: index == 0 ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawPiles(game) {
    final canDraw = game.isMyTurn && game.turnPhase == 'mustDraw';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Stock pile
          GestureDetector(
            onTap: canDraw ? () => game.drawFromStock() : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 64,
              height: 88,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.primary,
                    AppTheme.primary.withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: canDraw
                    ? Border.all(color: AppTheme.accent, width: 3)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.3),
                    blurRadius: canDraw ? 16 : 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.layers_rounded, color: Colors.white, size: 24),
                    const SizedBox(height: 4),
                    Text(
                      '${game.stockCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Discard pile
          GestureDetector(
            onTap: canDraw && game.discardTop != null
                ? () => game.drawFromDiscard()
                : null,
            child: game.discardTop != null
                ? CardWidget(
                    cardCode: game.discardTop!,
                    isSelected: false,
                    highlighted: canDraw,
                  )
                : Container(
                    width: 64,
                    height: 88,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: Border.all(
                        color: Theme.of(context).dividerColor,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'Empty',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeldsStaging(game) {
    final melds = _getMelds(game.hand);
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.amber.withValues(alpha: 0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Staged Melds: ', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(
                onPressed: _clearMelds,
                child: const Text('Clear'),
              ),
            ],
          ),
          Wrap(
            children: melds.map((meld) {
              return Container(
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.amber),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: meld.map((c) => SizedBox(
                    width: 30,
                    child: CardWidget(cardCode: c, isSelected: false, small: true),
                  )).toList(),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTableMelds(game) {
    final myId = ref.read(authProvider).userId;
    final players = game.players as List<Map<String, dynamic>>;
    final canLayOff = game.isMyTurn &&
        game.turnPhase == 'mustDiscard' &&
        !game.isFinalTurnPhase &&
        _selectedCardIndices.isNotEmpty;

    // Collect all melds from all players
    final allMelds = <({int playerIndex, int meldIndex, List<String> cards, String playerName, bool isMe})>[];

    for (var i = 0; i < players.length; i++) {
      final player = players[i];
      final melds = player['melds'] as List<dynamic>?;
      if (melds == null || melds.isEmpty) continue;

      final isMe = player['id'] == myId;
      final displayName = player['displayName'] as String?;
      final username = player['username'] as String?;
      final name = isMe ? 'You' : (displayName ?? username ?? 'P${(player['seat'] as int) + 1}');

      for (var j = 0; j < melds.length; j++) {
        final meldCards = (melds[j] as List).cast<String>();
        allMelds.add((
          playerIndex: i,
          meldIndex: j,
          cards: meldCards,
          playerName: name,
          isMe: isMe,
        ));
      }
    }

    if (allMelds.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.table_restaurant_rounded, size: 16),
              const SizedBox(width: 4),
              const Text('Table Melds', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              if (canLayOff) ...[
                const Spacer(),
                Text(
                  'Tap a meld to lay off',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: allMelds.map((meld) {
                final isSelected = _layOffTargetPlayerIndex == meld.playerIndex &&
                    _layOffTargetMeldIndex == meld.meldIndex;

                // Check if this meld can be extended with selected cards
                bool canExtend = false;
                if (canLayOff && meld.cards.length >= 3) {
                  // Determine meld type from cards
                  final gameRef = ref.read(gameProvider);
                  final selectedCards = _getSelectedCards(gameRef.hand);
                  try {
                    // Try as run first, then book
                    canExtend = gameRef.canExtendMeld(
                          meld.cards,
                          selectedCards,
                          MeldType.run,
                        ) ||
                        gameRef.canExtendMeld(
                          meld.cards,
                          selectedCards,
                          MeldType.book,
                        );
                  } catch (_) {
                    canExtend = false;
                  }
                }

                return GestureDetector(
                  onTap: canLayOff && canExtend
                      ? () => _selectMeldForLayOff(meld.playerIndex, meld.meldIndex)
                      : null,
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primary.withValues(alpha: 0.2)
                          : (canExtend && canLayOff
                              ? Colors.orange.withValues(alpha: 0.1)
                              : null),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primary
                            : (canExtend && canLayOff
                                ? Colors.orange
                                : (meld.isMe ? Colors.green : Theme.of(context).dividerColor)),
                        width: isSelected ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2, left: 2),
                          child: Text(
                            meld.playerName,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: meld.isMe ? Colors.green : Theme.of(context).textTheme.bodySmall?.color,
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: meld.cards.map((c) => SizedBox(
                                width: 28,
                                child: CardWidget(cardCode: c, isSelected: false, small: true),
                              )).toList(),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyHand(game) {
    // Get indices of cards that are in staged melds
    final indicesInMelds = _meldIndices.expand((m) => m).toSet();
    // Build list of (index, card) for cards NOT in melds
    final hand = game.hand as List<String>;

    // Get display order (preserves user's custom ordering)
    final handDisplayOrder = _getHandDisplayOrder(hand);

    // Filter out cards in melds from display order
    final availableDisplayOrder = handDisplayOrder
        .where((i) => !indicesInMelds.contains(i) && i < hand.length)
        .toList();

    final myScore = game.scores[ref.read(authProvider).userId] ?? 0;

    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('My Hand (${availableDisplayOrder.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              // Reorder hint icon
              Tooltip(
                message: 'Long-press and drag cards to reorder',
                child: Icon(
                  Icons.swap_horiz_rounded,
                  size: 16,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
              const Spacer(),
              // Wild card indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.star_rounded,
                      size: 14,
                      color: AppTheme.warning,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Wild: ${_getWildRankName(game.roundNumber)}s',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: AppTheme.warning,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Score button - opens scoreboard on tap
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showScoreboard(game),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.leaderboard_rounded,
                          size: 18,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Score: $myScore',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Wrapping hand layout - cards wrap to multiple rows
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: List.generate(availableDisplayOrder.length, (displayIndex) {
              final handIndex = availableDisplayOrder[displayIndex];
              final card = hand[handIndex];
              final isSelected = _selectedCardIndices.contains(handIndex);

              return DragTarget<int>(
                onWillAcceptWithDetails: (details) => details.data != displayIndex,
                onAcceptWithDetails: (details) {
                  final fromDisplayIndex = details.data;
                  // Convert display indices to card order indices
                  final fromCard = hand[availableDisplayOrder[fromDisplayIndex]];
                  final toCard = hand[availableDisplayOrder[displayIndex]];
                  final fromCardOrderIndex = _handCardOrder.indexOf(fromCard);
                  final toCardOrderIndex = _handCardOrder.indexOf(toCard);
                  _reorderHand(fromCardOrderIndex, toCardOrderIndex);
                },
                builder: (context, candidateData, rejectedData) {
                  final isDropTarget = candidateData.isNotEmpty;

                  return LongPressDraggable<int>(
                    data: displayIndex,
                    delay: const Duration(milliseconds: 150),
                    feedback: Material(
                      elevation: 8,
                      color: Colors.transparent,
                      child: Transform.scale(
                        scale: 1.1,
                        child: CardWidget(
                          cardCode: card,
                          isSelected: isSelected,
                        ),
                      ),
                    ),
                    childWhenDragging: Opacity(
                      opacity: 0.3,
                      child: CardWidget(
                        cardCode: card,
                        isSelected: isSelected,
                      ),
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: isDropTarget
                            ? Border.all(color: AppTheme.primary, width: 2)
                            : null,
                      ),
                      child: GestureDetector(
                        onTap: () {
                          if (game.isMyTurn && game.turnPhase == 'mustDiscard') {
                            _toggleCardSelection(handIndex);
                          }
                        },
                        onDoubleTap: () {
                          if (game.isMyTurn && game.turnPhase == 'mustDiscard' && !game.isFinalTurnPhase) {
                            game.discard(card);
                          }
                        },
                        child: CardWidget(
                          cardCode: card,
                          isSelected: isSelected,
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(game) {
    if (!game.isMyTurn || game.turnPhase != 'mustDiscard') {
      return const SizedBox.shrink();
    }

    final hand = game.hand as List<String>;
    final selectedCards = _getSelectedCards(hand);
    final melds = _getMelds(hand);

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (_selectedCardIndices.length >= 3 && game.isValidMeld(selectedCards))
            ElevatedButton(
              onPressed: _createMeldFromSelection,
              child: const Text('Create Meld'),
            ),
          if (_meldIndices.isNotEmpty)
            ElevatedButton(
              onPressed: _layMelds,
              child: const Text('Lay Melds'),
            ),
          // Lay Off button - when cards selected and meld target selected
          if (_selectedCardIndices.isNotEmpty &&
              _layOffTargetPlayerIndex != null &&
              _layOffTargetMeldIndex != null &&
              !game.isFinalTurnPhase)
            ElevatedButton(
              onPressed: _layOffCards,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
              ),
              child: const Text('Lay Off'),
            ),
          if (_selectedCardIndices.length == 1 && !game.isFinalTurnPhase)
            ElevatedButton(
              onPressed: () {
                final card = selectedCards.first;
                if (game.canGoOut(melds, card)) {
                  _goOut(card);
                } else {
                  game.discard(card);
                  _selectedCardIndices.clear();
                  setState(() {});
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: game.canGoOut(melds, selectedCards.first) ? Colors.green : null,
              ),
              child: Text(game.canGoOut(melds, selectedCards.first) ? 'Go Out!' : 'Discard'),
            ),
          if (_selectedCardIndices.length == 1 && game.isFinalTurnPhase)
            ElevatedButton(
              onPressed: () {
                game.discard(selectedCards.first);
                _selectedCardIndices.clear();
                setState(() {});
              },
              child: const Text('Discard'),
            ),
        ],
      ),
    );
  }

  Widget _buildGameEndScreen(game) {
    final sortedScores = game.scores.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Game Over!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          const Text('Final Scores:', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 16),
          ...sortedScores.asMap().entries.map((entry) {
            final rank = entry.key + 1;
            final player = game.players.firstWhere(
              (p) => p['id'] == entry.value.key,
              orElse: () => {'displayName': 'Unknown'},
            );
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '$rank. ${player['displayName'] ?? 'Player'}: ${entry.value.value} points',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: rank == 1 ? FontWeight.bold : FontWeight.normal,
                  color: rank == 1 ? Colors.green : null,
                ),
              ),
            );
          }),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => context.beamToNamed('/games'),
            child: const Text('Back to Games'),
          ),
        ],
      ),
    );
  }
}
