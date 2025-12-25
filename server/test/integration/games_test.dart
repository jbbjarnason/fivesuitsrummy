import 'package:test/test.dart';
import 'test_helpers.dart';

void main() {
  late TestHarness harness;
  late String user1Token;
  late String user2Token;
  late String user3Token;
  late String user1Id;
  late String user2Id;
  late String user3Id;

  setUp(() async {
    harness = TestHarness();
    await harness.setUp();

    // Create three test users
    final (token1, _) = await createVerifiedUser(harness, email: 'player1@test.com', username: 'player1');
    final (token2, _) = await createVerifiedUser(harness, email: 'player2@test.com', username: 'player2');
    final (token3, _) = await createVerifiedUser(harness, email: 'player3@test.com', username: 'player3');

    user1Token = token1;
    user2Token = token2;
    user3Token = token3;

    // Get user IDs
    final me1 = await harness.request('GET', '/users/me', authToken: user1Token);
    final me2 = await harness.request('GET', '/users/me', authToken: user2Token);
    final me3 = await harness.request('GET', '/users/me', authToken: user3Token);

    user1Id = (await harness.parseJson(me1))['id'] as String;
    user2Id = (await harness.parseJson(me2))['id'] as String;
    user3Id = (await harness.parseJson(me3))['id'] as String;
  });

  tearDown(() async {
    await harness.tearDown();
  });

  group('Game Creation', () {
    test('create game', () async {
      final response = await harness.request(
        'POST',
        '/games/',
        body: {'maxPlayers': 4},
        authToken: user1Token,
      );

      expect(response.statusCode, 201);
      final json = await harness.parseJson(response);
      expect(json['gameId'], isNotEmpty);
    });

    test('create game with default max players', () async {
      final response = await harness.request(
        'POST',
        '/games/',
        body: {},
        authToken: user1Token,
      );

      expect(response.statusCode, 201);
    });

    test('reject invalid max players', () async {
      final tooFew = await harness.request(
        'POST',
        '/games/',
        body: {'maxPlayers': 1},
        authToken: user1Token,
      );
      expect(tooFew.statusCode, 400);

      final tooMany = await harness.request(
        'POST',
        '/games/',
        body: {'maxPlayers': 10},
        authToken: user1Token,
      );
      expect(tooMany.statusCode, 400);
    });

    test('creator is automatically added as first player', () async {
      final createResponse = await harness.request(
        'POST',
        '/games/',
        body: {'maxPlayers': 4},
        authToken: user1Token,
      );
      final gameId = (await harness.parseJson(createResponse))['gameId'] as String;

      final gameResponse = await harness.request(
        'GET',
        '/games/$gameId',
        authToken: user1Token,
      );

      final gameJson = await harness.parseJson(gameResponse);
      final players = gameJson['players'] as List;
      expect(players.length, 1);
      expect(players[0]['user']['id'], user1Id);
      expect(players[0]['seat'], 0);
    });

    test('list games shows user games', () async {
      // Create two games
      await harness.request('POST', '/games/', body: {}, authToken: user1Token);
      await harness.request('POST', '/games/', body: {}, authToken: user1Token);

      final response = await harness.request(
        'GET',
        '/games/',
        authToken: user1Token,
      );

      final json = await harness.parseJson(response);
      expect((json['games'] as List).length, 2);
    });

    test('user only sees games they are part of', () async {
      // User1 creates a game
      await harness.request('POST', '/games/', body: {}, authToken: user1Token);

      // User2 should not see it
      final response = await harness.request(
        'GET',
        '/games/',
        authToken: user2Token,
      );

      final json = await harness.parseJson(response);
      expect((json['games'] as List).length, 0);
    });
  });

  group('Game Invites', () {
    late String gameId;

    setUp(() async {
      // Create friendships between user1 and user2, user1 and user3
      // User1 sends friend request to user2
      await harness.request('POST', '/friends/request', body: {'userId': user2Id}, authToken: user1Token);
      await harness.request('POST', '/friends/accept', body: {'userId': user1Id}, authToken: user2Token);

      // User1 sends friend request to user3
      await harness.request('POST', '/friends/request', body: {'userId': user3Id}, authToken: user1Token);
      await harness.request('POST', '/friends/accept', body: {'userId': user1Id}, authToken: user3Token);

      final response = await harness.request(
        'POST',
        '/games/',
        body: {'maxPlayers': 3},
        authToken: user1Token,
      );
      gameId = (await harness.parseJson(response))['gameId'] as String;
    });

    test('invite player to game', () async {
      final response = await harness.request(
        'POST',
        '/games/$gameId/invite',
        body: {'userId': user2Id},
        authToken: user1Token,
      );

      expect(response.statusCode, 200);

      // Check game now has 2 players
      final gameResponse = await harness.request(
        'GET',
        '/games/$gameId',
        authToken: user1Token,
      );
      final players = (await harness.parseJson(gameResponse))['players'] as List;
      expect(players.length, 2);
    });

    test('invited player can see the game', () async {
      await harness.request(
        'POST',
        '/games/$gameId/invite',
        body: {'userId': user2Id},
        authToken: user1Token,
      );

      final response = await harness.request(
        'GET',
        '/games/',
        authToken: user2Token,
      );

      final json = await harness.parseJson(response);
      expect((json['games'] as List).length, 1);
    });

    test('cannot invite same player twice', () async {
      await harness.request(
        'POST',
        '/games/$gameId/invite',
        body: {'userId': user2Id},
        authToken: user1Token,
      );

      final response = await harness.request(
        'POST',
        '/games/$gameId/invite',
        body: {'userId': user2Id},
        authToken: user1Token,
      );

      expect(response.statusCode, 409);
    });

    test('cannot invite beyond max players', () async {
      // Invite user2 (now 2 players)
      await harness.request(
        'POST',
        '/games/$gameId/invite',
        body: {'userId': user2Id},
        authToken: user1Token,
      );

      // Invite user3 (now 3 players = max)
      await harness.request(
        'POST',
        '/games/$gameId/invite',
        body: {'userId': user3Id},
        authToken: user1Token,
      );

      // Create user4 and set up friendship
      final (token4, _) = await createVerifiedUser(harness, email: 'player4@test.com', username: 'player4');
      final me4 = await harness.request('GET', '/users/me', authToken: token4);
      final user4Id = (await harness.parseJson(me4))['id'] as String;

      // Create friendship with user4
      await harness.request('POST', '/friends/request', body: {'userId': user4Id}, authToken: user1Token);
      await harness.request('POST', '/friends/accept', body: {'userId': user1Id}, authToken: token4);

      final response = await harness.request(
        'POST',
        '/games/$gameId/invite',
        body: {'userId': user4Id},
        authToken: user1Token,
      );

      expect(response.statusCode, 400);
      final json = await harness.parseJson(response);
      expect(json['error'], 'game_full');
    });

    test('non-member cannot invite', () async {
      final response = await harness.request(
        'POST',
        '/games/$gameId/invite',
        body: {'userId': user3Id},
        authToken: user2Token, // user2 is not in the game
      );

      expect(response.statusCode, 403);
    });
  });

  group('LiveKit Token', () {
    late String gameId;

    setUp(() async {
      final response = await harness.request(
        'POST',
        '/games/',
        body: {},
        authToken: user1Token,
      );
      gameId = (await harness.parseJson(response))['gameId'] as String;
    });

    test('get livekit token for game member', () async {
      final response = await harness.request(
        'POST',
        '/games/$gameId/livekit-token',
        authToken: user1Token,
      );

      expect(response.statusCode, 200);
      final json = await harness.parseJson(response);
      expect(json['url'], 'wss://test.livekit.local');
      expect(json['room'], 'game-$gameId');
      expect(json['token'], isNotEmpty);
    });

    test('non-member cannot get livekit token', () async {
      final response = await harness.request(
        'POST',
        '/games/$gameId/livekit-token',
        authToken: user2Token, // not in game
      );

      expect(response.statusCode, 403);
    });
  });

  group('Game Invite with Friendship', () {
    test('can invite friend after mutual accept', () async {
      // First, user1 sends friend request to user2
      await harness.request(
        'POST',
        '/friends/request',
        body: {'userId': user2Id},
        authToken: user1Token,
      );

      // User2 accepts the friend request (this creates TWO rows in friendships table)
      final acceptResponse = await harness.request(
        'POST',
        '/friends/accept',
        body: {'userId': user1Id},
        authToken: user2Token,
      );
      expect(acceptResponse.statusCode, 200);

      // User1 creates a game
      final gameResponse = await harness.request(
        'POST',
        '/games/',
        body: {'maxPlayers': 4},
        authToken: user1Token,
      );
      expect(gameResponse.statusCode, 201);
      final gameId = (await harness.parseJson(gameResponse))['gameId'] as String;

      // User1 invites user2 - this should NOT fail with "Too many elements"
      final inviteResponse = await harness.request(
        'POST',
        '/games/$gameId/invite',
        body: {'userId': user2Id},
        authToken: user1Token,
      );

      expect(inviteResponse.statusCode, 200);
      final inviteJson = await harness.parseJson(inviteResponse);
      expect(inviteJson['status'], 'invited');
    });
  });

  group('Game Nudge', () {
    late String gameId;

    setUp(() async {
      // Create friendship between user1 and user2
      await harness.request('POST', '/friends/request', body: {'userId': user2Id}, authToken: user1Token);
      await harness.request('POST', '/friends/accept', body: {'userId': user1Id}, authToken: user2Token);

      // User1 creates a game
      final response = await harness.request(
        'POST',
        '/games/',
        body: {'maxPlayers': 4},
        authToken: user1Token,
      );
      gameId = (await harness.parseJson(response))['gameId'] as String;

      // Invite user2
      await harness.request(
        'POST',
        '/games/$gameId/invite',
        body: {'userId': user2Id},
        authToken: user1Token,
      );
    });

    test('guest can nudge host', () async {
      final response = await harness.request(
        'POST',
        '/games/$gameId/nudge',
        authToken: user2Token,
      );

      expect(response.statusCode, 200);
      final json = await harness.parseJson(response);
      expect(json['status'], 'nudged');
    });

    test('host cannot nudge themselves', () async {
      final response = await harness.request(
        'POST',
        '/games/$gameId/nudge',
        authToken: user1Token,
      );

      expect(response.statusCode, 400);
      final json = await harness.parseJson(response);
      expect(json['error'], 'is_host');
    });

    test('non-member cannot nudge', () async {
      final response = await harness.request(
        'POST',
        '/games/$gameId/nudge',
        authToken: user3Token, // not in game
      );

      expect(response.statusCode, 403);
    });

    test('cannot nudge after game started', () async {
      // Start the game via WebSocket is complex in tests,
      // so we'll just update the game status directly in DB
      await harness.db.customStatement(
        "UPDATE games SET status = 'active' WHERE id = '$gameId'"
      );

      final response = await harness.request(
        'POST',
        '/games/$gameId/nudge',
        authToken: user2Token,
      );

      expect(response.statusCode, 400);
      final json = await harness.parseJson(response);
      expect(json['error'], 'game_started');
    });
  });

  group('Leave Game', () {
    late String gameId;

    setUp(() async {
      // Make player1 and player2 friends first
      await harness.request(
        'POST',
        '/friends/request',
        body: {'userId': user2Id},
        authToken: user1Token,
      );
      await harness.request(
        'POST',
        '/friends/accept',
        body: {'userId': user1Id},
        authToken: user2Token,
      );

      // Create a game with player1 as host
      final createResponse = await harness.request(
        'POST',
        '/games/',
        body: {'maxPlayers': 4},
        authToken: user1Token,
      );
      final json = await harness.parseJson(createResponse);
      gameId = json['gameId'] as String;

      // Invite player2 (now friends)
      await harness.request(
        'POST',
        '/games/$gameId/invite',
        body: {'userId': user2Id},
        authToken: user1Token,
      );
    });

    test('guest can leave game', () async {
      final response = await harness.request(
        'POST',
        '/games/$gameId/leave',
        authToken: user2Token,
      );

      expect(response.statusCode, 200);
      final json = await harness.parseJson(response);
      expect(json['status'], 'left');

      // Verify player is no longer in game
      final gameResponse = await harness.request(
        'GET',
        '/games/$gameId',
        authToken: user1Token,
      );
      final gameJson = await harness.parseJson(gameResponse);
      final players = gameJson['players'] as List;
      expect(players.any((p) => p['id'] == user2Id), false);
    });

    test('host cannot leave game', () async {
      final response = await harness.request(
        'POST',
        '/games/$gameId/leave',
        authToken: user1Token,
      );

      expect(response.statusCode, 400);
      final json = await harness.parseJson(response);
      expect(json['error'], 'is_host');
    });

    test('cannot leave started game', () async {
      // Start the game
      await harness.db.customStatement(
        "UPDATE games SET status = 'active' WHERE id = '$gameId'"
      );

      final response = await harness.request(
        'POST',
        '/games/$gameId/leave',
        authToken: user2Token,
      );

      expect(response.statusCode, 400);
      final json = await harness.parseJson(response);
      expect(json['error'], 'game_started');
    });

    test('non-member cannot leave game', () async {
      final response = await harness.request(
        'POST',
        '/games/$gameId/leave',
        authToken: user3Token,
      );

      expect(response.statusCode, 400);
      final json = await harness.parseJson(response);
      expect(json['error'], 'not_in_game');
    });
  });
}
