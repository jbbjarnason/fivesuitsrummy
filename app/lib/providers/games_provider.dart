import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

class GamesProvider extends ChangeNotifier {
  final ApiService api;

  List<Map<String, dynamic>> _games = [];
  List<Map<String, dynamic>> get games => _games;

  Map<String, dynamic>? _currentGame;
  Map<String, dynamic>? get currentGame => _currentGame;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  GamesProvider({required this.api});

  Future<void> loadGames() async {
    _isLoading = true;
    notifyListeners();

    _games = await api.getGames();

    _isLoading = false;
    notifyListeners();
  }

  Future<String?> createGame({int maxPlayers = 4}) async {
    _isLoading = true;
    notifyListeners();

    final result = await api.createGame(maxPlayers: maxPlayers);

    _isLoading = false;
    notifyListeners();

    if (result != null) {
      await loadGames();
      return result['gameId'] as String?;
    }
    return null;
  }

  Future<void> loadGame(String gameId) async {
    _isLoading = true;
    notifyListeners();

    _currentGame = await api.getGame(gameId);

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> invitePlayer(String gameId, String userId) async {
    final success = await api.invitePlayer(gameId, userId);
    if (success) {
      await loadGame(gameId);
    }
    return success;
  }

  Future<bool> deleteGame(String gameId) async {
    final success = await api.deleteGame(gameId);
    if (success) {
      _games.removeWhere((g) => g['id'] == gameId);
      if (_currentGame?['id'] == gameId) {
        _currentGame = null;
      }
      notifyListeners();
    }
    return success;
  }

  Future<bool> leaveGame(String gameId) async {
    final success = await api.leaveGame(gameId);
    if (success) {
      _games.removeWhere((g) => g['id'] == gameId);
      if (_currentGame?['id'] == gameId) {
        _currentGame = null;
      }
      notifyListeners();
    }
    return success;
  }

  Future<bool> nudgeHost(String gameId) async {
    return await api.nudgeHost(gameId);
  }

  Future<Map<String, dynamic>?> getLivekitToken(String gameId) async {
    return await api.getLivekitToken(gameId);
  }

  void updateGameState(Map<String, dynamic> state) {
    _currentGame = {...?_currentGame, ...state};
    notifyListeners();
  }

  void clearCurrentGame() {
    _currentGame = null;
    notifyListeners();
  }
}
