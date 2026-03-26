import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isAdmin = false;
  bool _isLoading = true;

  // 従業員一覧
  List<Map<String, dynamic>> _profiles = [];
  // 車両一覧
  List<Map<String, dynamic>> _vehicles = [];

  @override
  void initState() {
    super.initState();
    _fetchSettingsAndProfiles();
  }

  Future<void> _fetchSettingsAndProfiles() async {
    setState(() => _isLoading = true);
    try {
      // 1. 自身の権限チェック
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('role')
            .eq('id', user.id)
            .maybeSingle();
        if (profile != null && profile['role'] == 'admin') {
          _isAdmin = true;
        }
      }

      // 2. 従業員リストの取得
      final profilesData = await Supabase.instance.client
          .from('profiles')
          .select()
          .order('updated_at', ascending: true);
      _profiles = List<Map<String, dynamic>>.from(profilesData);

      // 3. 車両リストの取得
      final vehiclesData = await Supabase.instance.client
          .from('master_vehicles')
          .select()
          .is_('deleted_at', null)
          .order('type', ascending: true)
          .order('id', ascending: true);
      _vehicles = List<Map<String, dynamic>>.from(vehiclesData);
    } catch (e) {
      if (mounted) _showSnackBar('データの取得に失敗しました: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Edge Function を呼び出して新規アカウントを作成
  Future<void> _createNewUser() async {
    if (!_isAdmin) return;

    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final nameController = TextEditingController();
    String selectedRole = 'staff';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        bool isSubmitting = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('新規従業員アカウント作成'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        labelText: 'ログインID (例: sato)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: passwordController,
                      decoration: const InputDecoration(
                        labelText: '初期パスワード (6文字以上)',
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: '氏名'),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: const InputDecoration(labelText: '権限'),
                      items: const [
                        DropdownMenuItem(value: 'staff', child: Text('一般社員')),
                        DropdownMenuItem(value: 'admin', child: Text('管理者')),
                      ],
                      onChanged: (val) =>
                          setDialogState(() => selectedRole = val!),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);
                          try {
                            final email =
                                '${emailController.text.trim()}@daisha.system'; // ダミードメイン

                            // ⭕️ Edge Function を呼び出す（名前は 'fullName' に戻す！）
                            final response = await Supabase
                                .instance
                                .client
                                .functions
                                .invoke(
                                  'create_user',
                                  body: {
                                    'email': email,
                                    'password': passwordController.text,
                                    'fullName': nameController
                                        .text, // ★ 'name' ではなく 'fullName' だ！
                                    'role': selectedRole,
                                  },
                                );

                            // ⭕️ 正しいエラーチェックの書き方（status プロパティは使わない！）
                            if (response.data != null &&
                                response.data is Map &&
                                response.data['error'] != null) {
                              throw response
                                  .data['error']; // サーバーからのエラー文をそのまま投げる！
                            }

                            if (context.mounted) Navigator.pop(context, true);
                          } on FunctionException catch (e) {
                            // Edge Function が 400エラー等を返した場合はここに来る！
                            setDialogState(() => isSubmitting = false);
                            if (context.mounted) {
                              // サーバーが返した生のエラー理由（e.details）を表示する！
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'サーバーエラー: ${e.details ?? e.reasonPhrase ?? '不明なエラー'}',
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } catch (e) {
                            // そのめる予期せぬエラー
                            setDialogState(() => isSubmitting = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('エラー: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  child: isSubmitting
                      ? const CircularProgressIndicator()
                      : const Text('作成'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      _showSnackBar('新しい従業員アカウントを作成しました');
      _fetchSettingsAndProfiles(); // リストを再読み込み
    }
  }

  // 従業員アカウントの削除
  Future<void> _deleteUser(Map<String, dynamic> profile) async {
    if (!_isAdmin) return;

    final userId = profile['id'];
    final fullName = profile['full_name'] ?? '名前なし';

    // 自身の削除は禁止（または警告）
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser != null && currentUser.id == userId) {
      _showSnackBar('自分自身のアカウントは削除できません', isError: true);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('従業員アカウントの削除'),
        content: Text('「$fullName」のアカウントを完全に削除しますか？\nこの操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('削除する'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'delete_user',
        body: {'target_user_id': userId},
      );

      if (response.data != null &&
          response.data is Map &&
          response.data['error'] != null) {
        throw response.data['error'];
      }

      _showSnackBar('従業員アカウントを削除しました');
      await _fetchSettingsAndProfiles(); // リストを再読み込み
    } on FunctionException catch (e) {
      _showSnackBar(
        'サーバーエラー: ${e.details ?? e.reasonPhrase ?? '不明なエラー'}',
        isError: true,
      );
    } catch (e) {
      _showSnackBar('エラー: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 車両カテゴリの定義
  final List<String> _carCategories = [
    '軽自動車',
    '普通車',
    '貨物車',
    'レンタカー軽自動車',
    'レンタカー普通車',
    'レンタカー貨物車',
    '他',
  ];

  // 車両の追加・編集ダイアログ
  Future<void> _showVehicleDialog([Map<String, dynamic>? vehicle]) async {
    if (!_isAdmin) return;

    final nameController = TextEditingController(text: vehicle?['name']);
    
    // ★ 修正：年式を和暦で扱うための初期化
    String selectedYearEra = 'R';
    String yearStr = '';
    if (vehicle?['model_year'] != null) {
      int y = int.tryParse(vehicle!['model_year'].toString()) ?? 0;
      if (y >= 2019) {
        selectedYearEra = 'R';
        yearStr = (y - 2018).toString();
      } else if (y >= 1989) {
        selectedYearEra = 'H';
        yearStr = (y - 1988).toString();
      } else if (y >= 1926) {
        selectedYearEra = 'S';
        yearStr = (y - 1925).toString();
      } else {
        yearStr = y.toString();
      }
    }
    final yearController = TextEditingController(text: yearStr);

    final colorController = TextEditingController(text: vehicle?['color']);
    final plateController = TextEditingController(text: vehicle?['plate_no']);
    final inspectionController = TextEditingController(
      text: _toJpDate(vehicle?['inspection_expiry']),
    );
    String? selectedCategory = vehicle?['category'];
    if (selectedCategory == null ||
        !_carCategories.contains(selectedCategory)) {
      selectedCategory = _carCategories.first;
    }

    final isEdit = vehicle != null;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        bool isSubmitting = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEdit ? '車両情報の編集' : '新規車両の追加'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: '車名 (例: アトレー)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: selectedYearEra,
                            decoration: const InputDecoration(labelText: '年号'),
                            items: const [
                              DropdownMenuItem(value: 'R', child: Text('令和')),
                              DropdownMenuItem(value: 'H', child: Text('平成')),
                              DropdownMenuItem(value: 'S', child: Text('昭和')),
                            ],
                            onChanged: (val) => setDialogState(() => selectedYearEra = val!),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: yearController,
                            decoration: const InputDecoration(
                              labelText: '年',
                              suffixText: '年',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: colorController,
                            decoration: const InputDecoration(
                              labelText: '色 (例: 水色)',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: plateController,
                            decoration: const InputDecoration(
                              labelText: '登録番号 (例: 7247)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: inspectionController,
                            decoration: const InputDecoration(
                              labelText: '車検満了日 (例: R9.7.27)',
                            ),
                          ),
                        ),
                      ],
                    ),
                    // ★ 削除：駐車場位置の入力項目
                    /*
                    const SizedBox(height: 8),
                    TextField(
                      controller: parkingController,
                      decoration: const InputDecoration(labelText: '駐車場位置'),
                    ),
                    */
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedCategory,
                      decoration: const InputDecoration(labelText: '車両カテゴリ'),
                      items: _carCategories
                          .map(
                            (cat) =>
                                DropdownMenuItem(value: cat, child: Text(cat)),
                          )
                          .toList(),
                      onChanged: (val) =>
                          setDialogState(() => selectedCategory = val),
                    ),
                    // ★ 削除：表示順の入力項目
                    /*
                    const SizedBox(height: 8),
                    TextField(
                      controller: typeController,
                      decoration: const InputDecoration(
                        labelText: '表示順 (数値が小さいほど上に表示されます)',
                        hintText: '例: 10',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    */
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (nameController.text.isEmpty) {
                            _showSnackBar('車名を入力してください', isError: true);
                            return;
                          }
                          setDialogState(() => isSubmitting = true);
                          try {
                            // 和暦年を西暦に変換
                            int modelYear = int.tryParse(yearController.text) ?? 0;
                            if (modelYear > 0) {
                              if (selectedYearEra == 'R') modelYear += 2018;
                              else if (selectedYearEra == 'H') modelYear += 1988;
                              else if (selectedYearEra == 'S') modelYear += 1925;
                            }

                            final data = {
                              'name': nameController.text,
                              'model_year': modelYear,
                              'color': colorController.text,
                              'plate_no': plateController.text,
                              'inspection_expiry': _toIsoDate(inspectionController.text),
                              'category': selectedCategory,
                              'updated_at': DateTime.now().toIso8601String(),
                            };

                            if (isEdit) {
                              await Supabase.instance.client
                                  .from('master_vehicles')
                                  .update(data)
                                  .eq('id', vehicle['id']);
                            } else {
                              await Supabase.instance.client
                                  .from('master_vehicles')
                                  .insert({
                                    ...data,
                                    'status': 0, // 初期状態は空車
                                    'type': _vehicles.length.toString().padLeft(4, '0'), // 0パディングして保存
                                  });
                            }
                            if (context.mounted) Navigator.pop(context, true);
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            _showSnackBar('エラー: $e', isError: true);
                          }
                        },
                  child: isSubmitting
                      ? const CircularProgressIndicator()
                      : Text(isEdit ? '更新' : '追加'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      _showSnackBar(isEdit ? '車両情報を更新しました' : '車両を追加しました');
      _fetchSettingsAndProfiles();
    }
  }

  // 車両の削除
  Future<void> _deleteVehicle(Map<String, dynamic> vehicle) async {
    if (!_isAdmin) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('車両の削除'),
        content: Text(
          '「${vehicle['name']}」を削除しますか？\nこの車両に関連する貸出履歴がある場合、削除できない可能性があります。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('削除する'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client
          .from('master_vehicles')
          .update({'deleted_at': DateTime.now().toIso8601String()})
          .eq('id', vehicle['id']);

      _showSnackBar('車両を削除しました');
      await _fetchSettingsAndProfiles();
    } catch (e) {
      _showSnackBar('削除に失敗しました。貸出履歴が存在する可能性があります。', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ★ 改善：並び順をDBに保存するメソッド
  Future<void> _updateVehicleOrder() async {
    try {
      // 画面上の現在の並び順に基づいて、すべての車両の'type'カラムを更新
      for (int i = 0; i < _vehicles.length; i++) {
        final vehicleId = _vehicles[i]['id'];
        final newOrderStr = i.toString().padLeft(4, '0');
        
        await Supabase.instance.client
            .from('master_vehicles')
            .update({'type': newOrderStr})
            .eq('id', vehicleId);
      }
      
      _showSnackBar('並び順を保存しました');
    } catch (e) {
      debugPrint('Order Update Error: $e');
      if (mounted) _showSnackBar('並び替えの保存に失敗しました: $e', isError: true);
    }
  }

  // ★ 追加：西暦を和暦年(R6年)に変換するヘルパー
  String _toJpYear(dynamic val) {
    if (val == null) return '';
    int? year = int.tryParse(val.toString());
    if (year == null || year == 0) return '';
    if (year >= 2019) return 'R${year - 2018}年';
    if (year >= 1989) return 'H${year - 1988}年';
    if (year >= 1926) return 'S${year - 1925}年';
    return '${year}年';
  }

  // ★ 追加：和暦(R9.2.27)表示への変換ヘルパー
  String _toJpDate(dynamic val) {
    if (val == null || val.toString().isEmpty) return '';
    try {
      final date = DateTime.parse(val.toString());
      final y = date.year;
      if (y >= 2019) return 'R${y - 2018}.${date.month}.${date.day}';
      if (y >= 1989) return 'H${y - 1988}.${date.month}.${date.day}';
      return 'S${y - 1925}.${date.month}.${date.day}';
    } catch (_) {
      return val.toString();
    }
  }

  // ★ 追加：入力値(R9.2.27等)をISO形式への変換ヘルパー
  String? _toIsoDate(String val) {
    if (val.isEmpty) return null;
    final text = val.trim().toUpperCase();

    // 既に ISO形式 (YYYY-MM-DD) ならそのまま
    if (RegExp(r'^\d{4}[-/]\d{1,2}[-/]\d{1,2}$').hasMatch(text)) {
      return text.replaceAll('/', '-');
    }

    // 和暦形式 (R9.2.27, H18/5/10, etc.) をパース
    final match = RegExp(r'^([RHS])(\d+)[\./](\d+)[\./](\d+)$').firstMatch(text);
    if (match != null) {
      final era = match.group(1);
      final yearNum = int.parse(match.group(2)!);
      final month = int.parse(match.group(3)!);
      final day = int.parse(match.group(4)!);

      int year;
      if (era == 'R') year = yearNum + 2018;
      else if (era == 'H') year = yearNum + 1988;
      else if (era == 'S') year = yearNum + 1925;
      else return null;

      return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
    }

    return null; // パース不能な場合はnullを返して保存（またはエラーメッセージを表示）
  }

  // ナンバープレートから下4桁（または末尾の数字）を抽出する
  String _getLast4Digits(String? plateNo) {
    if (plateNo == null || plateNo.isEmpty || plateNo == '-') return '-';
    final clean = plateNo.replaceAll(RegExp(r'\D'), '');
    if (clean.length >= 4) {
      return clean.substring(clean.length - 4);
    }
    return clean.isEmpty ? plateNo : clean;
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('設定')),
        body: const Center(
          child: Text(
            'この画面を表示する権限がありません。',
            style: TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('システム設定マスタ'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.directions_car), text: '車両管理'),
              Tab(icon: Icon(Icons.people), text: '従業員管理'),
              Tab(icon: Icon(Icons.analytics), text: 'レンタカー集計'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // タブ1: 車両管理
            Column(
              children: [
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: _vehicles.length,
                    onReorder: (oldIndex, newIndex) async {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = _vehicles.removeAt(oldIndex);
                        _vehicles.insert(newIndex, item);
                      });
                      // DB側の並び順（typeカラム）を更新
                      await _updateVehicleOrder();
                    },
                    itemBuilder: (context, index) {
                      final vehicle = _vehicles[index];
                      return ListTile(
                        key: ValueKey(vehicle['id']),
                        leading: ReorderableDragStartListener(
                          index: index,
                          child: CircleAvatar(
                            backgroundColor: Colors.orange.shade100,
                            child: const Icon(Icons.drag_handle, color: Colors.orange, size: 20),
                          ),
                        ),
                        title: Text(
                          '${vehicle['name'] ?? ''} ${_toJpYear(vehicle['model_year'])} ${vehicle['color'] ?? ''}'
                              .trim(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${_getLast4Digits(vehicle['plate_no'])} ${_toJpDate(vehicle['inspection_expiry'])}'.trim(),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _showVehicleDialog(vehicle),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteVehicle(vehicle),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () => _showVehicleDialog(),
                      icon: const Icon(Icons.add_box),
                      label: const Text('新規車両を追加'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade800,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // タブ2: 従業員管理
            Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: _profiles.length,
                    itemBuilder: (context, index) {
                      final profile = _profiles[index];
                      final isStaffAdmin = profile['role'] == 'admin';
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isStaffAdmin
                              ? Colors.red.shade100
                              : Colors.blue.shade100,
                          child: Icon(
                            Icons.person,
                            color: isStaffAdmin ? Colors.red : Colors.blue,
                          ),
                        ),
                        title: Text(profile['full_name'] ?? '名前なし'),
                        subtitle: Text('権限: ${isStaffAdmin ? '管理者' : '一般社員'}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteUser(profile),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _createNewUser,
                      icon: const Icon(Icons.person_add),
                      label: const Text('新規従業員を追加'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // タブ3: レンタカー集計
            const _RentalStatsTab(),
          ],
        ),
      ),
    );
  }
}

class _RentalStatsTab extends StatefulWidget {
  const _RentalStatsTab();

  @override
  State<_RentalStatsTab> createState() => _RentalStatsTabState();
}

class _RentalStatsTabState extends State<_RentalStatsTab> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _records = [];
  DateTime _selectedYear = DateTime.now();

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    setState(() => _isLoading = true);
    try {
      final firstDayOfYear = DateTime(_selectedYear.year, 1, 1);
      final lastDayOfYear = DateTime(_selectedYear.year, 12, 31);

      final data = await Supabase.instance.client
          .from('loaner_records')
          .select()
          .eq('rental_condition', '無料')
          .gte('start_date', firstDayOfYear.toIso8601String().split('T')[0])
          .lte('start_date', lastDayOfYear.toIso8601String().split('T')[0]);

      setState(() {
        _records = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('集計エラー: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    // 月ごとの集計ロジック
    final Map<int, Map<String, int>> monthlyStats = {};
    for (int i = 1; i <= 12; i++) {
      monthlyStats[i] = {'count': 0, 'days': 0};
    }

    for (var r in _records) {
      final start = DateTime.parse(r['start_date']);
      final end = DateTime.parse(r['end_date']);
      final month = start.month;
      
      monthlyStats[month]!['count'] = (monthlyStats[month]!['count'] ?? 0) + 1;
      monthlyStats[month]!['days'] = (monthlyStats[month]!['days'] ?? 0) + 
          (end.difference(start).inDays + 1);
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.blue.shade50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() => _selectedYear = DateTime(_selectedYear.year - 1));
                  _fetchStats();
                },
              ),
              Text(
                '${_selectedYear.year}年 無料貸出集計',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(() => _selectedYear = DateTime(_selectedYear.year + 1));
                  _fetchStats();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: 12,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final month = index + 1;
              final stats = monthlyStats[month]!;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.shade800,
                  foregroundColor: Colors.white,
                  child: Text('$month月'),
                ),
                title: Text('無料貸出台数: ${stats['count']} 台'),
                subtitle: Text('合計貸出日数: ${stats['days']} 日'),
                trailing: Icon(Icons.bar_chart, color: Colors.blue.shade200),
              );
            },
          ),
        ),
      ],
    );
  }
}
