import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:fivecrowns_protocol/fivecrowns_protocol.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../ws/ws_hub.dart';

const _uuid = Uuid();
String _generateId() => _uuid.v4();

class FriendsRoutes {
  final AppDatabase db;
  final WsHub wsHub;

  FriendsRoutes({required this.db, required this.wsHub});

  Router get router {
    final router = Router();

    router.get('/', _listFriends);
    router.post('/request', _sendRequest);
    router.post('/accept', _acceptRequest);
    router.post('/decline', _declineRequest);
    router.post('/block', _blockUser);
    router.delete('/<friendId>', _removeFriend);

    return router;
  }

  Future<Response> _listFriends(Request request) async {
    final userId = request.context['userId'] as String?;
    if (userId == null) {
      return _unauthorized();
    }

    // Get all friendships where user is involved
    final outgoing = await (db.select(db.friendships)
      ..where((f) => f.userId.equals(userId)))
        .get();

    final incoming = await (db.select(db.friendships)
      ..where((f) => f.friendId.equals(userId)))
        .get();

    final friends = <FriendshipDto>[];
    final pendingIncoming = <FriendshipDto>[];
    final pendingOutgoing = <FriendshipDto>[];

    // Process outgoing relationships
    for (final f in outgoing) {
      final friend = await (db.select(db.users)..where((u) => u.id.equals(f.friendId))).getSingleOrNull();
      if (friend == null) continue;

      final dto = FriendshipDto(
        user: UserDto(
          id: friend.id,
          username: friend.username,
          displayName: friend.displayName,
          avatarUrl: friend.avatarUrl,
        ),
        status: FriendshipStatus.fromString(f.status),
        incomingRequest: false,
        createdAt: f.createdAt,
      );

      if (f.status == 'accepted') {
        friends.add(dto);
      } else if (f.status == 'pending') {
        pendingOutgoing.add(dto);
      }
    }

    // Process incoming relationships
    for (final f in incoming) {
      // Skip if we already have this as outgoing
      if (outgoing.any((o) => o.friendId == f.userId)) continue;

      final friend = await (db.select(db.users)..where((u) => u.id.equals(f.userId))).getSingleOrNull();
      if (friend == null) continue;

      final dto = FriendshipDto(
        user: UserDto(
          id: friend.id,
          username: friend.username,
          displayName: friend.displayName,
          avatarUrl: friend.avatarUrl,
        ),
        status: FriendshipStatus.fromString(f.status),
        incomingRequest: true,
        createdAt: f.createdAt,
      );

      if (f.status == 'accepted') {
        friends.add(dto);
      } else if (f.status == 'pending') {
        pendingIncoming.add(dto);
      }
    }

    return Response(200,
        body: jsonEncode(FriendsListResponse(
          friends: friends,
          pendingIncoming: pendingIncoming,
          pendingOutgoing: pendingOutgoing,
        ).toJson()),
        headers: {'content-type': 'application/json'});
  }

  Future<Response> _sendRequest(Request request) async {
    final userId = request.context['userId'] as String?;
    if (userId == null) return _unauthorized();

    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final req = FriendRequest.fromJson(json);

      if (req.userId == userId) {
        return _error(400, 'invalid_request', 'Cannot send friend request to yourself');
      }

      // Check if target user exists
      final target = await (db.select(db.users)..where((u) => u.id.equals(req.userId))).getSingleOrNull();
      if (target == null) {
        return _error(404, 'not_found', 'User not found');
      }

      // Check existing relationship
      final existing = await (db.select(db.friendships)
        ..where((f) => f.userId.equals(userId) & f.friendId.equals(req.userId)))
          .getSingleOrNull();

      if (existing != null) {
        if (existing.status == 'blocked') {
          return _error(403, 'blocked', 'You have blocked this user');
        }
        return _error(409, 'already_exists', 'Friend request already sent');
      }

      // Check if they blocked us
      final theirBlocked = await (db.select(db.friendships)
        ..where((f) => f.userId.equals(req.userId) & f.friendId.equals(userId) & f.status.equals('blocked')))
          .getSingleOrNull();

      if (theirBlocked != null) {
        return _error(403, 'blocked', 'Cannot send friend request');
      }

      // Check if they already sent us a request
      final theirPending = await (db.select(db.friendships)
        ..where((f) => f.userId.equals(req.userId) & f.friendId.equals(userId) & f.status.equals('pending')))
          .getSingleOrNull();

      if (theirPending != null) {
        // Auto-accept both ways
        await (db.update(db.friendships)
          ..where((f) => f.userId.equals(req.userId) & f.friendId.equals(userId)))
            .write(const FriendshipsCompanion(status: Value('accepted')));

        await db.into(db.friendships).insert(FriendshipsCompanion.insert(
          userId: userId,
          friendId: req.userId,
          status: 'accepted',
        ));

        return Response(200,
            body: jsonEncode({'status': 'accepted'}),
            headers: {'content-type': 'application/json'});
      }

      // Create pending request
      await db.into(db.friendships).insert(FriendshipsCompanion.insert(
        userId: userId,
        friendId: req.userId,
        status: 'pending',
      ));

      // Persist notification to database and send real-time notification
      final sender = await (db.select(db.users)..where((u) => u.id.equals(userId))).getSingleOrNull();
      if (sender != null) {
        final notificationId = _generateId();
        await db.into(db.notifications).insert(NotificationsCompanion.insert(
          id: Value(notificationId),
          userId: req.userId,
          type: 'friend_request',
          fromUserId: Value(userId),
        ));

        wsHub.sendNotificationToUser(
          req.userId,
          EvtNotification(
            notificationType: NotificationType.friendRequest,
            fromUserId: userId,
            fromUsername: sender.username,
            fromDisplayName: sender.displayName,
            message: '${sender.displayName} sent you a friend request',
          ),
        );
      }

      return Response(201,
          body: jsonEncode({'status': 'pending'}),
          headers: {'content-type': 'application/json'});
    } on FormatException {
      return _error(400, 'invalid_json', 'Invalid JSON');
    }
  }

  Future<Response> _acceptRequest(Request request) async {
    final userId = request.context['userId'] as String?;
    if (userId == null) return _unauthorized();

    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final req = FriendRequest.fromJson(json);

      // Find their pending request to us
      final pending = await (db.select(db.friendships)
        ..where((f) => f.userId.equals(req.userId) & f.friendId.equals(userId) & f.status.equals('pending')))
          .getSingleOrNull();

      if (pending == null) {
        return _error(404, 'not_found', 'No pending request from this user');
      }

      // Update their request to accepted
      await (db.update(db.friendships)
        ..where((f) => f.userId.equals(req.userId) & f.friendId.equals(userId)))
          .write(const FriendshipsCompanion(status: Value('accepted')));

      // Create our side of the friendship
      await db.into(db.friendships).insert(FriendshipsCompanion.insert(
        userId: userId,
        friendId: req.userId,
        status: 'accepted',
      ));

      // Persist notification and send real-time notification to the original requester
      final accepter = await (db.select(db.users)..where((u) => u.id.equals(userId))).getSingleOrNull();
      if (accepter != null) {
        final notificationId = _generateId();
        await db.into(db.notifications).insert(NotificationsCompanion.insert(
          id: Value(notificationId),
          userId: req.userId,
          type: 'friend_accepted',
          fromUserId: Value(userId),
        ));

        wsHub.sendNotificationToUser(
          req.userId,
          EvtNotification(
            notificationType: NotificationType.friendAccepted,
            fromUserId: userId,
            fromUsername: accepter.username,
            fromDisplayName: accepter.displayName,
            message: '${accepter.displayName} accepted your friend request',
          ),
        );
      }

      return Response(200,
          body: jsonEncode({'status': 'accepted'}),
          headers: {'content-type': 'application/json'});
    } on FormatException {
      return _error(400, 'invalid_json', 'Invalid JSON');
    }
  }

  Future<Response> _declineRequest(Request request) async {
    final userId = request.context['userId'] as String?;
    if (userId == null) return _unauthorized();

    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final req = FriendRequest.fromJson(json);

      // Delete their pending request to us
      final deleted = await (db.delete(db.friendships)
        ..where((f) => f.userId.equals(req.userId) & f.friendId.equals(userId) & f.status.equals('pending')))
          .go();

      if (deleted == 0) {
        return _error(404, 'not_found', 'No pending request from this user');
      }

      return Response(200,
          body: jsonEncode({'status': 'declined'}),
          headers: {'content-type': 'application/json'});
    } on FormatException {
      return _error(400, 'invalid_json', 'Invalid JSON');
    }
  }

  Future<Response> _blockUser(Request request) async {
    final userId = request.context['userId'] as String?;
    if (userId == null) return _unauthorized();

    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final req = FriendRequest.fromJson(json);

      // Remove any existing relationship
      await (db.delete(db.friendships)
        ..where((f) => (f.userId.equals(userId) & f.friendId.equals(req.userId)) |
                       (f.userId.equals(req.userId) & f.friendId.equals(userId))))
          .go();

      // Create block
      await db.into(db.friendships).insert(FriendshipsCompanion.insert(
        userId: userId,
        friendId: req.userId,
        status: 'blocked',
      ));

      // Send real-time notification
      final blocker = await (db.select(db.users)..where((u) => u.id.equals(userId))).getSingleOrNull();
      if (blocker != null) {
        wsHub.sendNotificationToUser(
          req.userId,
          EvtNotification(
            notificationType: NotificationType.friendBlocked,
            fromUserId: userId,
            fromUsername: blocker.username,
            fromDisplayName: blocker.displayName,
          ),
        );
      }

      return Response(200,
          body: jsonEncode({'status': 'blocked'}),
          headers: {'content-type': 'application/json'});
    } on FormatException {
      return _error(400, 'invalid_json', 'Invalid JSON');
    }
  }

  Future<Response> _removeFriend(Request request, String friendId) async {
    final userId = request.context['userId'] as String?;
    if (userId == null) return _unauthorized();

    // Delete both sides of the friendship
    await (db.delete(db.friendships)
      ..where((f) => (f.userId.equals(userId) & f.friendId.equals(friendId)) |
                     (f.userId.equals(friendId) & f.friendId.equals(userId))))
        .go();

    // Send real-time notification to the friend who was removed
    final remover = await (db.select(db.users)..where((u) => u.id.equals(userId))).getSingleOrNull();
    if (remover != null) {
      // Note: Using friendBlocked type since there's no friendRemoved type yet
      // This will still trigger the friend list refresh on the client
      wsHub.sendNotificationToUser(
        friendId,
        EvtNotification(
          notificationType: NotificationType.friendBlocked, // Using blocked as a workaround
          fromUserId: userId,
          fromUsername: remover.username,
          fromDisplayName: remover.displayName,
          message: '${remover.displayName} removed you as a friend',
        ),
      );
    }

    return Response(200,
        body: jsonEncode({'status': 'removed'}),
        headers: {'content-type': 'application/json'});
  }

  Response _unauthorized() {
    return Response(401,
        body: jsonEncode({'error': 'unauthorized'}),
        headers: {'content-type': 'application/json'});
  }

  Response _error(int status, String code, String message) {
    return Response(status,
        body: jsonEncode({'error': code, 'message': message}),
        headers: {'content-type': 'application/json'});
  }
}
