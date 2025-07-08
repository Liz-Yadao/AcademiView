import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:academiview/screens/auth/login_page.dart';
import 'package:academiview/screens/auth/signup_page.dart';
import 'package:academiview/screens/role_selection_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Try-catch approach to handle Firebase initialization
  try {
    await Firebase.initializeApp(
      options: _getFirebaseOptions(),
    );
    print('Firebase initialized successfully');
  } catch (e) {
    if (e.toString().contains('duplicate-app')) {
      print('Firebase already initialized - continuing...');
    } else {
      print('Firebase initialization error: $e');
      rethrow;
    }
  }
  
  runApp(const AcademiViewApp());
}

// Firebase configuration for different platforms
FirebaseOptions _getFirebaseOptions() {
  if (kIsWeb) {
    // Web configuration
    return const FirebaseOptions(
      apiKey: "AIzaSyCMNPMJqJWhm5EAKJ_n3EKyOOIeXCO5WlU",
      appId: "1:54691102377:web:your_web_app_id", // Replace with your actual web app ID
      messagingSenderId: "54691102377",
      projectId: "academiview-c16db",
      storageBucket: "academiview-c16db.appspot.com",
      authDomain: "academiview-c16db.firebaseapp.com",
    );
  } else {
    // Mobile (Android/iOS) configuration
    return const FirebaseOptions(
      apiKey: "AIzaSyCMNPMJqJWhm5EAKJ_n3EKyOOIeXCO5WlU",
      appId: "1:54691102377:android:b3eeeb7955ce3470c773b8",
      messagingSenderId: "54691102377",
      projectId: "academiview-c16db",
      storageBucket: "academiview-c16db.appspot.com",
    );
  }
}

class AcademiViewApp extends StatelessWidget {
  const AcademiViewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AcademiView',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        // Add some additional theme customization
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthWrapper(),
        '/signup': (context) => const SignupWrapper(),
        '/role-selection': (context) => const RoleSelectionPage(),
      },
      onUnknownRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Page not found')),
            body: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    '404 - Page not found',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFF8A80), Color(0xFFFFAB91)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: LoginPage(
          onSwitchToSignup: () {
            Navigator.pushNamed(context, '/signup');
          },
        ),
      ),
    );
  }
}

class SignupWrapper extends StatelessWidget {
  const SignupWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFF8A80), Color(0xFFFFAB91)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SignupPage(
          onSwitchToLogin: () {
            Navigator.pop(context); // Go back to login
          },
        ),
      ),
    );
  }
}