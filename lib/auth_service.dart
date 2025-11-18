import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class AuthService {
  static const String baseUrl = 'https://smart-device.lskk.co.id/api';
  
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    
    if (token != null) {
      try {
        // Call server logout endpoint
        await http.get(
          Uri.parse('$baseUrl/signout'),
          headers: {
            'Authorization': 'Bearer $token',
          },
        );
      } catch (e) {
        // Ignore errors during logout
      }
    }
    
    // Clear local storage
    await prefs.remove('isLoggedIn');
    await prefs.remove('authToken');
    await prefs.remove('username');
    await prefs.remove('userEmail');
    await prefs.remove('userId');
    await prefs.remove('loginTime');
  }
  
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    final token = prefs.getString('authToken');
    
    return isLoggedIn && token != null;
  }
  
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('authToken');
  }
  
  static Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('username');
  }
}