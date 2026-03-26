import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart'; // 代車管理画面
import 'in_store_screen.dart';
import 'settings_screen.dart'; // ★ 絶対に忘れずにインポートしろ！
import 'inspection_list_screen.dart'; // ★追加
import 'garage_certificate_screen.dart'; // ★追加
import 'login_screen.dart'; // ★ログアウト後に遷移するために追加

// ============================================================================
// 🔥 アプリ全体の土台（サイドバー付きレイアウト）
// ============================================================================
class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  // 現在選択されているページのインデックス（初期値は0＝代車管理）
  int _selectedIndex = 0;
  String _currentUserName = '担当者';

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('full_name')
            .eq('id', user.id)
            .maybeSingle();
        if (!mounted) return;
        if (profile != null) {
          setState(() => _currentUserName = profile['full_name']);
        }
      } catch (e) {
        debugPrint('Error fetching user data: $e');
      }
    }
  }

  // ページを切り替えるメソッド
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    Navigator.pop(context); // メニューを選んだらサイドバーを閉じる
  }

  @override
  Widget build(BuildContext context) {
    // 選択されたインデックスに応じて、中央に表示する画面を切り替える
    final List<Widget> pages = [
      const HomeScreen(), // 0: 代車管理
      const InStoreScreen(), // 1: 入庫管理
      const InspectionListScreen(), // 2: 車検リスト
      const Center(child: Text('ロードサービス機能（開発中）')), // 3: ロードサービス
      const Center(child: Text('車検証スキャン機能（開発中）')), // 4: 車検証スキャン
      const GarageCertificateScreen(), // 5: 車庫証明作成
      const SettingsScreen(), // 6: 設定・マスタ
    ];

    // AppBarのタイトルも切り替える
    final List<String> titles = [
      '🚗 代車管理カレンダー',
      '🔧 入庫管理',
      '📋 車検リスト',
      '🚑 ロードサービス（開発中）',
      '📷 車検証スキャン（開発中）',
      '📄 車庫証明作成（開発中）',
      '⚙️ システム設定マスタ',
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_selectedIndex], style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
      ),
      // ★ ここが最強の左サイドバー（Drawer）だ！
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(color: Colors.blue.shade900),
              accountName: Text(_currentUserName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              accountEmail: const Text('自動車整備・代車管理システム'),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 40, color: Colors.blue),
              ),
            ),
            // ★ スクロール可能にする
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ListTile(
                    leading: const Icon(Icons.directions_car, color: Colors.blue),
                    title: const Text('代車管理', style: TextStyle(fontWeight: FontWeight.bold)),
                    selected: _selectedIndex == 0,
                    selectedTileColor: Colors.blue.shade50,
                    onTap: () => _onItemTapped(0),
                  ),
                  ListTile(
                    leading: const Icon(Icons.build, color: Colors.orange),
                    title: const Text('入庫管理', style: TextStyle(fontWeight: FontWeight.bold)),
                    selected: _selectedIndex == 1,
                    selectedTileColor: Colors.blue.shade50,
                    onTap: () => _onItemTapped(1),
                  ),
                  ListTile(
                    leading: const Icon(Icons.assignment_ind, color: Colors.green),
                    title: const Text('車検リスト', style: TextStyle(fontWeight: FontWeight.bold)),
                    selected: _selectedIndex == 2,
                    selectedTileColor: Colors.blue.shade50,
                    onTap: () => _onItemTapped(2),
                  ),
                  ListTile(
                    leading: const Icon(Icons.medical_services, color: Colors.red),
                    title: const Text('ロードサービス（開発中）', style: TextStyle(fontWeight: FontWeight.bold)),
                    selected: _selectedIndex == 3,
                    selectedTileColor: Colors.blue.shade50,
                    onTap: () => _onItemTapped(3),
                  ),
                  ListTile(
                    leading: const Icon(Icons.camera_alt, color: Colors.blueGrey),
                    title: const Text('車検証スキャン（開発中）', style: TextStyle(fontWeight: FontWeight.bold)),
                    selected: _selectedIndex == 4,
                    selectedTileColor: Colors.blue.shade50,
                    onTap: () => _onItemTapped(4),
                  ),
                  ListTile(
                    leading: const Icon(Icons.description, color: Colors.purple),
                    title: const Text('車庫証明作成（開発中）', style: TextStyle(fontWeight: FontWeight.bold)),
                    selected: _selectedIndex == 5,
                    selectedTileColor: Colors.blue.shade50,
                    onTap: () => _onItemTapped(5),
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings, color: Colors.grey),
                    title: const Text('設定・マスタ', style: TextStyle(fontWeight: FontWeight.bold)),
                    selected: _selectedIndex == 6,
                    selectedTileColor: Colors.blue.shade50,
                    onTap: () => _onItemTapped(6),
                  ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('ログアウト', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              onTap: () async {
                // ログアウト処理
                // ★ AuthGate (main.dart) がストリームを監視しているため、
                // signOut() を呼ぶだけで自動的にログイン画面へ戻るぞ！
                await Supabase.instance.client.auth.signOut();
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      // 中央のメインコンテンツ
      body: pages[_selectedIndex],
    );
  }
}
