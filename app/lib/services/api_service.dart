import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  final String baseUrl;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  ApiService({required this.baseUrl});

  Future<String?> get accessToken => _storage.read(key: 'accessToken');
  Future<String?> get refreshToken => _storage.read(key: 'refreshToken');

  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: 'accessToken', value: accessToken);
    await _storage.write(key: 'refreshToken', value: refreshToken);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: 'accessToken');
    await _storage.delete(key: 'refreshToken');
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
    int retryCount = 0,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (auth) {
      final token = await accessToken;
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await http.get(uri, headers: headers);
          break;
        case 'POST':
          response = await http.post(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: headers);
          break;
        default:
          throw ArgumentError('Unsupported method: $method');
      }
    } catch (e) {
      // Retry on network errors (timeout, socket exception, etc.)
      if (retryCount < 2) {
        await Future.delayed(const Duration(seconds: 1));
        return _request(method, path, body: body, auth: auth, retryCount: retryCount + 1);
      }
      rethrow;
    }

    // Auto-refresh on 401
    if (response.statusCode == 401 && auth) {
      final refreshed = await _refreshTokens();
      if (refreshed) {
        return _request(method, path, body: body, auth: auth);
      }
    }

    return response;
  }

  Future<bool> _refreshTokens() async {
    final token = await refreshToken;
    if (token == null) return false;

    final response = await http.post(
      Uri.parse('$baseUrl/auth/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refreshToken': token}),
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      await saveTokens(
        accessToken: json['accessJwt'],
        refreshToken: json['refreshToken'],
      );
      return true;
    }

    await clearTokens();
    return false;
  }

  Future<http.Response> get(String path, {bool auth = true}) =>
      _request('GET', path, auth: auth);

  Future<http.Response> post(String path, {Map<String, dynamic>? body, bool auth = true}) =>
      _request('POST', path, body: body, auth: auth);

  Future<http.Response> delete(String path, {bool auth = true}) =>
      _request('DELETE', path, auth: auth);

  // Auth endpoints
  Future<Map<String, dynamic>?> signup({
    required String email,
    required String password,
    required String username,
    required String displayName,
  }) async {
    final response = await post('/auth/signup', body: {
      'email': email,
      'password': password,
      'username': username,
      'displayName': displayName,
    }, auth: false);

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    }
    return null;
  }

  Future<Map<String, dynamic>?> verify(String token) async {
    final response = await post('/auth/verify', body: {'token': token}, auth: false);
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }

  Future<bool> login(String email, String password) async {
    final response = await post('/auth/login', body: {
      'email': email,
      'password': password,
    }, auth: false);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      await saveTokens(
        accessToken: json['accessJwt'],
        refreshToken: json['refreshToken'],
      );
      return true;
    }
    return false;
  }

  Future<void> logout() async {
    await clearTokens();
  }

  Future<Map<String, dynamic>?> requestPasswordReset(String email) async {
    final response = await post('/auth/password-reset/request', body: {'email': email}, auth: false);
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }

  Future<bool> confirmPasswordReset(String token, String newPassword) async {
    final response = await post('/auth/password-reset/confirm', body: {
      'token': token,
      'newPassword': newPassword,
    }, auth: false);
    return response.statusCode == 200;
  }

  // User endpoints
  Future<Map<String, dynamic>?> getMe() async {
    final response = await get('/users/me');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final response = await get('/users/search?username=$query');
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(json['users']);
    }
    return [];
  }

  // Friends endpoints
  Future<Map<String, dynamic>?> getFriends() async {
    final response = await get('/friends/');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }

  Future<bool> sendFriendRequest(String userId) async {
    final response = await post('/friends/request', body: {'userId': userId});
    return response.statusCode == 201 || response.statusCode == 200;
  }

  Future<bool> acceptFriendRequest(String userId) async {
    final response = await post('/friends/accept', body: {'userId': userId});
    return response.statusCode == 200;
  }

  Future<bool> declineFriendRequest(String userId) async {
    final response = await post('/friends/decline', body: {'userId': userId});
    return response.statusCode == 200;
  }

  Future<bool> blockUser(String userId) async {
    final response = await post('/friends/block', body: {'userId': userId});
    return response.statusCode == 200;
  }

  Future<bool> removeFriend(String userId) async {
    final response = await delete('/friends/$userId');
    return response.statusCode == 200;
  }

  // Games endpoints
  Future<List<Map<String, dynamic>>> getGames() async {
    final response = await get('/games/');
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(json['games']);
    }
    return [];
  }

  Future<Map<String, dynamic>?> createGame({int maxPlayers = 4}) async {
    final response = await post('/games/', body: {'maxPlayers': maxPlayers});
    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    }
    return null;
  }

  Future<Map<String, dynamic>?> getGame(String gameId) async {
    final response = await get('/games/$gameId');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }

  Future<bool> invitePlayer(String gameId, String userId) async {
    final response = await post('/games/$gameId/invite', body: {'userId': userId});
    return response.statusCode == 200;
  }

  Future<bool> deleteGame(String gameId) async {
    final response = await delete('/games/$gameId');
    return response.statusCode == 200;
  }

  Future<bool> leaveGame(String gameId) async {
    final response = await post('/games/$gameId/leave');
    return response.statusCode == 200;
  }

  Future<bool> nudgeHost(String gameId) async {
    final response = await post('/games/$gameId/nudge');
    return response.statusCode == 200;
  }

  Future<bool> nudgePlayer(String gameId) async {
    final response = await post('/games/$gameId/nudge-player');
    return response.statusCode == 200;
  }

  Future<Map<String, dynamic>?> getLivekitToken(String gameId) async {
    final response = await post('/games/$gameId/livekit-token');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }

  // Notifications endpoints
  Future<List<Map<String, dynamic>>> getNotifications() async {
    final response = await get('/notifications/');
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(json['notifications']);
    }
    return [];
  }

  Future<int> getUnreadNotificationCount() async {
    final response = await get('/notifications/count');
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return json['count'] as int;
    }
    return 0;
  }

  Future<bool> markNotificationAsRead(String notificationId) async {
    final response = await post('/notifications/$notificationId/read');
    return response.statusCode == 200;
  }

  Future<bool> deleteNotification(String notificationId) async {
    final response = await delete('/notifications/$notificationId');
    return response.statusCode == 200;
  }

  Future<bool> clearAllNotifications() async {
    final response = await delete('/notifications/');
    return response.statusCode == 200;
  }

  // Stats endpoints
  Future<Map<String, dynamic>?> getMyStats() async {
    final response = await get('/users/me/stats');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }

  Future<Map<String, dynamic>?> getGroupStats(String groupKey) async {
    final response = await get('/users/me/stats/${Uri.encodeComponent(groupKey)}');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }
}
