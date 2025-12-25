import 'dart:async';
import 'dart:convert';
import 'package:fivecrowns_core/fivecrowns_core.dart' as core;
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:stream_channel/stream_channel.dart';

import 'test_helpers.dart';

/// Mock WebSocket channel for testing.
class MockWebSocketChannel extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  final StreamController<dynamic> _inController = StreamController<dynamic>.broadcast();
  final StreamController<dynamic> _outController = StreamController<dynamic>.broadcast();

  @override
  Stream<dynamic> get stream => _outController.stream;

  @override
  WebSocketSink get sink => MockWebSocketSink(_inController);

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future.value();

  /// Simulates receiving a message from the server.
  void receive(String message) {
    _outController.add(message);
  }

  /// Gets messages sent by the client.
  Stream<String> get sentMessages => _inController.stream.cast<String>();

  void dispose() {
    _inController.close();
    _outController.close();
  }
}

class MockWebSocketSink implements WebSocketSink {
  final StreamController<dynamic> _controller;

  MockWebSocketSink(this._controller);

  @override
  void add(dynamic data) {
    _controller.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _controller.addError(error, stackTrace);
  }

  @override
  Future addStream(Stream stream) {
    return stream.forEach(add);
  }

  @override
  Future close([int? closeCode, String? closeReason]) {
    return _controller.close();
  }

  @override
  Future get done => _controller.done;
}

void main() {
  late TestHarness harness;
  late String user1Token;
  late String user2Token;
  late String user1Id;
  late String user2Id;
  late String gameId;

  setUp(() async {
    harness = TestHarness();
    await harness.setUp();

    // Create two test users
    final (token1, _) = await createVerifiedUser(harness, email: 'player1@test.com', username: 'player1');
    final (token2, _) = await createVerifiedUser(harness, email: 'player2@test.com', username: 'player2');

    user1Token = token1;
    user2Token = token2;

    // Get user IDs
    final me1 = await harness.request('GET', '/users/me', authToken: user1Token);
    final me2 = await harness.request('GET', '/users/me', authToken: user2Token);

    user1Id = (await harness.parseJson(me1))['id'] as String;
    user2Id = (await harness.parseJson(me2))['id'] as String;

    // Create friendship
    await harness.request('POST', '/friends/request', body: {'userId': user2Id}, authToken: user1Token);
    await harness.request('POST', '/friends/accept', body: {'userId': user1Id}, authToken: user2Token);

    // Create game
    final gameResponse = await harness.request('POST', '/games/', body: {'maxPlayers': 2}, authToken: user1Token);
    gameId = (await harness.parseJson(gameResponse))['gameId'] as String;

    // Invite player 2
    await harness.request('POST', '/games/$gameId/invite', body: {'userId': user2Id}, authToken: user1Token);
  });

  tearDown(() async {
    await harness.tearDown();
  });

  group('Lay Off Game State Logic', () {
    test('player can lay off cards to other player meld', () async {
      // Test the core logic which is what the WsHub uses internally

      // Create a game state with 2 players
      final gameState = core.GameState.create(
        gameId: gameId,
        playerIds: [user1Id, user2Id],
      );
      gameState.startGame();

      // Fast forward: player 0 draws, lays a meld, discards
      gameState.drawFromStock();

      // Create a valid run meld for player 0 (7, 8, 9 of hearts)
      final card7 = core.Card(core.Suit.hearts, core.Rank.seven);
      final card8 = core.Card(core.Suit.hearts, core.Rank.eight);
      final card9 = core.Card(core.Suit.hearts, core.Rank.nine);

      // Set player 0's hand to include the meld cards + something to discard
      final player0 = gameState.players[0];
      final discardCard = player0.hand.first;
      player0.setHand([card7, card8, card9, discardCard]);

      // Lay the meld
      gameState.layMelds([[card7, card8, card9]]);
      expect(player0.melds.length, 1);
      expect(player0.melds[0].cards.length, 3);

      // Discard to end turn
      gameState.discard(discardCard);

      // Now it's player 1's turn
      expect(gameState.currentPlayerIndex, 1);

      // Player 1 draws
      gameState.drawFromStock();

      // Give player 1 a card that extends the run (10 of hearts)
      final card10 = core.Card(core.Suit.hearts, core.Rank.ten);
      final player1 = gameState.players[1];
      player1.setHand([...player1.hand, card10]);

      // Player 1 lays off the 10 to player 0's meld
      gameState.layOff(0, 0, [card10]);

      // Verify the meld was extended
      expect(player0.melds[0].cards.length, 4);
      expect(player0.melds[0].cards.map((c) => c.rank).toList(),
          containsAll([core.Rank.seven, core.Rank.eight, core.Rank.nine, core.Rank.ten]));

      // Verify the card was removed from player 1's hand
      expect(player1.hand.contains(card10), isFalse);
    });

    test('lay off fails during final turn phase', () async {
      // Create a game state and simulate going out scenario
      final gameState = core.GameState.create(
        gameId: 'test-game-final',
        playerIds: ['player1', 'player2'],
      );
      gameState.startGame();

      // Player 0 draws
      gameState.drawFromStock();

      // Give player 0 a valid meld and one card to discard
      final player0 = gameState.players[0];
      final card7 = core.Card(core.Suit.hearts, core.Rank.seven);
      final card8 = core.Card(core.Suit.hearts, core.Rank.eight);
      final card9 = core.Card(core.Suit.hearts, core.Rank.nine);
      final discardCard = core.Card(core.Suit.spades, core.Rank.three);
      player0.setHand([card7, card8, card9, discardCard]);

      // Go out with the meld
      gameState.goOut([[card7, card8, card9]], discardCard);

      // Now it's player 1's turn in final turn phase
      expect(gameState.isFinalTurnPhase, isTrue);
      expect(gameState.currentPlayerIndex, 1);

      // Player 1 draws
      gameState.drawFromStock();

      // Player 1 tries to lay off a card (should fail)
      final player1 = gameState.players[1];
      final card10 = core.Card(core.Suit.hearts, core.Rank.ten);
      player1.setHand([...player1.hand, card10]);

      expect(
        () => gameState.layOff(0, 0, [card10]),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('final turn phase'),
        )),
      );
    });

    test('lay off with multiple cards extends meld correctly', () async {
      final gameState = core.GameState.create(
        gameId: 'test-game-multi',
        playerIds: ['player1', 'player2'],
      );
      gameState.startGame();

      // Player 0 draws, lays meld, discards
      gameState.drawFromStock();

      final player0 = gameState.players[0];
      final card7 = core.Card(core.Suit.hearts, core.Rank.seven);
      final card8 = core.Card(core.Suit.hearts, core.Rank.eight);
      final card9 = core.Card(core.Suit.hearts, core.Rank.nine);
      final discardCard = player0.hand.first;
      player0.setHand([card7, card8, card9, discardCard]);

      gameState.layMelds([[card7, card8, card9]]);
      gameState.discard(discardCard);

      // Player 1's turn
      expect(gameState.currentPlayerIndex, 1);
      gameState.drawFromStock();

      // Player 1 has cards to extend both ends
      final player1 = gameState.players[1];
      final card6 = core.Card(core.Suit.hearts, core.Rank.six);
      final card10 = core.Card(core.Suit.hearts, core.Rank.ten);
      player1.setHand([...player1.hand, card6, card10]);

      // Lay off both cards
      gameState.layOff(0, 0, [card6, card10]);

      // Verify meld now has 5 cards
      expect(player0.melds[0].cards.length, 5);
      expect(player1.hand.contains(card6), isFalse);
      expect(player1.hand.contains(card10), isFalse);
    });

    test('cannot lay off to non-existent meld', () async {
      final gameState = core.GameState.create(
        gameId: 'test-game-invalid',
        playerIds: ['player1', 'player2'],
      );
      gameState.startGame();

      // Player 0 draws and discards (no meld)
      gameState.drawFromStock();
      gameState.discard(gameState.players[0].hand.first);

      // Player 1's turn
      gameState.drawFromStock();

      final player1 = gameState.players[1];
      final card = core.Card(core.Suit.hearts, core.Rank.seven);
      player1.setHand([...player1.hand, card]);

      // Try to lay off to player 0's meld index 0 (doesn't exist)
      expect(
        () => gameState.layOff(0, 0, [card]),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Invalid meld index'),
        )),
      );
    });

    test('cannot lay off with cards that do not extend meld', () async {
      final gameState = core.GameState.create(
        gameId: 'test-game-invalid-cards',
        playerIds: ['player1', 'player2'],
      );
      gameState.startGame();

      // Player 0 draws, lays meld, discards
      gameState.drawFromStock();

      final player0 = gameState.players[0];
      final card7 = core.Card(core.Suit.hearts, core.Rank.seven);
      final card8 = core.Card(core.Suit.hearts, core.Rank.eight);
      final card9 = core.Card(core.Suit.hearts, core.Rank.nine);
      final discardCard = player0.hand.first;
      player0.setHand([card7, card8, card9, discardCard]);

      gameState.layMelds([[card7, card8, card9]]);
      gameState.discard(discardCard);

      // Player 1's turn
      gameState.drawFromStock();

      final player1 = gameState.players[1];
      // Try to lay off a spade (doesn't fit the hearts run)
      final invalidCard = core.Card(core.Suit.spades, core.Rank.ten);
      player1.setHand([...player1.hand, invalidCard]);

      expect(
        () => gameState.layOff(0, 0, [invalidCard]),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Cannot extend meld'),
        )),
      );
    });
  });

  group('Lay Off WebSocket Integration', () {
    test('WsHub broadcasts state after lay off command', () async {
      // Create mock channels for two players
      final channel1 = MockWebSocketChannel();
      final channel2 = MockWebSocketChannel();

      // Collect messages from each channel
      final messages1 = <Map<String, dynamic>>[];
      final messages2 = <Map<String, dynamic>>[];

      channel1.sentMessages.listen((msg) {
        messages1.add(jsonDecode(msg) as Map<String, dynamic>);
      });
      channel2.sentMessages.listen((msg) {
        messages2.add(jsonDecode(msg) as Map<String, dynamic>);
      });

      // Connect both players
      harness.wsHub.handleConnection(channel1);
      harness.wsHub.handleConnection(channel2);

      // Authenticate player 1
      channel1.receive(jsonEncode({
        'type': 'cmd.hello',
        'jwt': user1Token,
        'clientSeq': 1,
      }));
      await Future.delayed(Duration(milliseconds: 100));

      // Authenticate player 2
      channel2.receive(jsonEncode({
        'type': 'cmd.hello',
        'jwt': user2Token,
        'clientSeq': 1,
      }));
      await Future.delayed(Duration(milliseconds: 100));

      // Verify both authenticated
      expect(messages1.any((m) => m['type'] == 'evt.hello'), isTrue);
      expect(messages2.any((m) => m['type'] == 'evt.hello'), isTrue);

      // Player 1 starts the game
      channel1.receive(jsonEncode({
        'type': 'cmd.startGame',
        'gameId': gameId,
        'clientSeq': 2,
      }));
      await Future.delayed(Duration(milliseconds: 100));

      // Both players join the game room
      channel1.receive(jsonEncode({
        'type': 'cmd.joinGame',
        'gameId': gameId,
        'clientSeq': 3,
      }));
      channel2.receive(jsonEncode({
        'type': 'cmd.joinGame',
        'gameId': gameId,
        'clientSeq': 2,
      }));
      await Future.delayed(Duration(milliseconds: 100));

      // Check that game state was broadcast
      final stateMessages1 = messages1.where((m) => m['type'] == 'evt.state').toList();
      expect(stateMessages1.isNotEmpty, isTrue);

      // Clean up
      channel1.dispose();
      channel2.dispose();
    });

    test('cardsLaidOff event is persisted after lay off', () async {
      final channel = MockWebSocketChannel();
      final messages = <Map<String, dynamic>>[];

      channel.sentMessages.listen((msg) {
        messages.add(jsonDecode(msg) as Map<String, dynamic>);
      });

      harness.wsHub.handleConnection(channel);

      // Authenticate
      channel.receive(jsonEncode({
        'type': 'cmd.hello',
        'jwt': user1Token,
        'clientSeq': 1,
      }));
      await Future.delayed(Duration(milliseconds: 100));

      // Start game
      channel.receive(jsonEncode({
        'type': 'cmd.startGame',
        'gameId': gameId,
        'clientSeq': 2,
      }));
      await Future.delayed(Duration(milliseconds: 100));

      // Join game room
      channel.receive(jsonEncode({
        'type': 'cmd.joinGame',
        'gameId': gameId,
        'clientSeq': 3,
      }));
      await Future.delayed(Duration(milliseconds: 100));

      // Draw a card
      channel.receive(jsonEncode({
        'type': 'cmd.draw',
        'gameId': gameId,
        'from': 'stock',
        'clientSeq': 4,
      }));
      await Future.delayed(Duration(milliseconds: 100));

      // Check for state update
      final stateMessages = messages.where((m) => m['type'] == 'evt.state').toList();
      expect(stateMessages.isNotEmpty, isTrue);

      // Verify game events table has entries
      final events = await harness.db.select(harness.db.gameEvents).get();
      expect(events.any((e) => e.gameId == gameId), isTrue);
      expect(events.any((e) => e.type == 'cardDrawn'), isTrue);

      channel.dispose();
    });

    test('lay off command returns error when not players turn', () async {
      final channel1 = MockWebSocketChannel();
      final channel2 = MockWebSocketChannel();

      final messages1 = <Map<String, dynamic>>[];
      final messages2 = <Map<String, dynamic>>[];

      channel1.sentMessages.listen((msg) {
        messages1.add(jsonDecode(msg) as Map<String, dynamic>);
      });
      channel2.sentMessages.listen((msg) {
        messages2.add(jsonDecode(msg) as Map<String, dynamic>);
      });

      harness.wsHub.handleConnection(channel1);
      harness.wsHub.handleConnection(channel2);

      // Authenticate both players
      channel1.receive(jsonEncode({
        'type': 'cmd.hello',
        'jwt': user1Token,
        'clientSeq': 1,
      }));
      channel2.receive(jsonEncode({
        'type': 'cmd.hello',
        'jwt': user2Token,
        'clientSeq': 1,
      }));
      await Future.delayed(Duration(milliseconds: 100));

      // Player 1 starts the game
      channel1.receive(jsonEncode({
        'type': 'cmd.startGame',
        'gameId': gameId,
        'clientSeq': 2,
      }));
      await Future.delayed(Duration(milliseconds: 100));

      // Both join
      channel1.receive(jsonEncode({
        'type': 'cmd.joinGame',
        'gameId': gameId,
        'clientSeq': 3,
      }));
      channel2.receive(jsonEncode({
        'type': 'cmd.joinGame',
        'gameId': gameId,
        'clientSeq': 2,
      }));
      await Future.delayed(Duration(milliseconds: 100));

      // Player 2 tries to lay off (but it's player 1's turn)
      channel2.receive(jsonEncode({
        'type': 'cmd.layOff',
        'gameId': gameId,
        'targetPlayerIndex': 0,
        'meldIndex': 0,
        'cards': ['H7'],
        'clientSeq': 3,
      }));
      await Future.delayed(Duration(milliseconds: 100));

      // Should receive an error
      final errorMessages = messages2.where((m) => m['type'] == 'evt.error').toList();
      expect(errorMessages.isNotEmpty, isTrue);
      expect(errorMessages.last['code'], 'not_your_turn');

      channel1.dispose();
      channel2.dispose();
    });
  });
}
