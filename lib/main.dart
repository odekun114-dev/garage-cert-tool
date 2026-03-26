import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/garage_certificate_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // セキュリティ性能の高い String.fromEnvironment を使用
  // Vercel の管理画面で設定した値がビルド時に注入されます
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  // Supabaseの初期化
  await Supabase.initialize(
    url: supabaseUrl.isNotEmpty ? supabaseUrl : '',
    anonKey: supabaseAnonKey.isNotEmpty ? supabaseAnonKey : '',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '車庫証明作成ツール',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const GarageCertificateScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}


