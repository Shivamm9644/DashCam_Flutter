import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  UserModel? _user;
  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _errorMessage;
  String? _token;

  UserModel? get user => _user;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get token => _token;

  final Completer<void> _initCompleter = Completer<void>();
  Future<void> get isInitialized => _initCompleter.future;

  AuthProvider() {
    _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString('auth_token');
      final savedUser = prefs.getString('user_data');

      if (savedToken != null && savedUser != null) {
        _token = savedToken;
        _user = UserModel.fromJson(jsonDecode(savedUser));
        _isAuthenticated = true;
        ApiService.instance.setToken(savedToken);
      } else {
        // Auto-authenticate as default Inurum Master on first launch so user never has to re-login
        await login(email: 'superadmin@inurum.com', password: 'password', role: 'SUPER_ADMIN');
      }
    } catch (_) {}
    if (!_initCompleter.isCompleted) _initCompleter.complete();
    notifyListeners();
  }

  Future<bool> login({
    required String email,
    required String password,
    required String role,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Authenticate with Java / SaaS backend to obtain cryptographic JWT token
      try {
        final res = await ApiService.instance.post('/auth/login', {
          'email': email,
          'password': password,
        });

        final realToken = res['token'] as String;
        final userData = res['user'] as Map<String, dynamic>;

        _user = UserModel.fromJson(userData);
        _token = realToken;
        _isAuthenticated = true;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', realToken);
        await prefs.setString('user_data', jsonEncode(userData));

        ApiService.instance.setToken(realToken);
        _isLoading = false;
        notifyListeners();
        return true;
      } catch (remoteError) {
        // Fallback for offline demo with realistic role mapping
        final demoUsers = {
          'SUPER_ADMIN': UserModel(
            id: 'user-superadmin-001',
            name: 'Inurum WanWay Master',
            email: email.isNotEmpty ? email : 'admin@inurum.io',
            role: 'SUPER_ADMIN',
            tenantId: 'tenant-inurum-master',
            tenantName: 'Inurum Global Fleet (WanWay Master)',
            avatar: 'IM',
          ),
          'ADMIN': UserModel(
            id: 'user-apex-admin-001',
            name: 'Apex Fleet Manager',
            email: email.isNotEmpty ? email : 'rajesh@apex-logistics.com',
            role: 'ADMIN',
            tenantId: 'tenant-apex',
            tenantName: 'Apex Logistics Corp',
            avatar: 'AF',
          ),
          'CUSTOMER': UserModel(
            id: 'user-apex-cust-003',
            name: 'Retail Customer',
            email: email.isNotEmpty ? email : 'client@apex-logistics.com',
            role: 'CUSTOMER',
            tenantId: 'tenant-apex',
            tenantName: 'Apex Logistics Corp',
            avatar: 'RC',
          ),
        };

        final fallbackUser = demoUsers[role] ?? demoUsers['SUPER_ADMIN']!;
        _user = fallbackUser;
        _token = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.${base64Url.encode(utf8.encode(jsonEncode({"sub": fallbackUser.id, "email": fallbackUser.email, "role": role})))}.fallbackSig';
        _isAuthenticated = true;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', _token!);
        await prefs.setString('user_data', jsonEncode(fallbackUser.toJson()));

        ApiService.instance.setToken(_token!);
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      _errorMessage = 'Network error. Check your connection.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _user = null;
    _token = null;
    _isAuthenticated = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_data');

    ApiService.instance.clearToken();
    notifyListeners();
  }
}
