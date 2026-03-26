import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:holiday_jp/holiday_jp.dart' as holiday_jp;
import 'action_dialogs.dart';

enum FontSizeMode { small, medium, large }

class InStoreScreen extends StatefulWidget {
  const InStoreScreen({super.key});

  @override
  State<InStoreScreen> createState() => _InStoreScreenState();
}

class _InStoreScreenState extends State<InStoreScreen> {
  DateTime _baseDate = DateTime.now();
  List<Map<String, dynamic>> _serviceRecords = [];
  bool _isLoading = true;
  bool _isAdmin = false;
  String _currentUserName = '担当者';
  FontSizeMode _fontSizeMode = FontSizeMode.small;

  // 日ごとの設定（ステータス：0:受付可, 1:要相談, 2:受付不可、および備考）
  Map<String, Map<String, dynamic>> _daySettings = {};

  double get _scale {
    switch (_fontSizeMode) {
      case FontSizeMode.small:
        return 1.0;
      case FontSizeMode.medium:
        return 1.3;
      case FontSizeMode.large:
        return 1.6;
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('full_name, role')
          .eq('id', user.id)
          .maybeSingle();
      if (profile != null) {
        _currentUserName = profile['full_name'] ?? '担当者';
        _isAdmin = profile['role'] == 'admin';
      }
    }

    try {
      // 1. 入庫レコードの取得
      final rData = await Supabase.instance.client
          .from('entry_records')
          .select()
          .order('entry_date', ascending: true);
      
      // 2. 日別設定（ステータス・備考）の取得
      final sData = await Supabase.instance.client
          .from('day_settings')
          .select();
      
      final Map<String, Map<String, dynamic>> fetchedSettings = {};
      for (var s in (sData as List)) {
        fetchedSettings[s['day_key'].toString()] = {
          'status': s['status'] ?? 0,
          'memo': s['memo'] ?? '',
        };
      }

      if (mounted) {
        setState(() {
          _serviceRecords = List<Map<String, dynamic>>.from(rData);
          _daySettings = fetchedSettings;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _serviceRecords = [];
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('データ取得エラー。entry_recordsテーブルを確認してください。')),
        );
      }
    }
  }

  // 設定をDBに保存する共通メソッド
  Future<void> _saveDaySetting(String dayKey, int status, String memo) async {
    try {
      await Supabase.instance.client.from('day_settings').upsert({
        'day_key': dayKey,
        'status': status,
        'memo': memo,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('DaySetting Save Error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('設定の保存に失敗しました: $e')));
    }
  }

  List<Map<String, dynamic>> _getRecordsForDate(DateTime targetDate) {
    List<Map<String, dynamic>> dayRecords = [];
    for (var r in _serviceRecords) {
      if (r['entry_date'] == null) continue;
      try {
        DateTime sDate = DateTime.parse(r['entry_date'].toString());
        if (sDate.year == targetDate.year &&
            sDate.month == targetDate.month &&
            sDate.day == targetDate.day) {
          dayRecords.add(r);
        }
      } catch (_) {}
    }
    return dayRecords;
  }

  // ナンバープレートから下4桁（または末尾の数字）を抽出する
  String _getLast4Digits(String? plateNo) {
    if (plateNo == null || plateNo.isEmpty || plateNo == '-') return '-';
    final match = RegExp(r'\d{1,4}$').stringMatch(plateNo.trim());
    return match ?? plateNo;
  }

  Future<void> _showNewServiceDialog({DateTime? initialDate}) async {
    final bool completed = await showEntryReceptionDialog(
      context: context,
      currentUserName: _currentUserName,
      initialDate: initialDate,
    );
    if (completed) _fetchData();
  }

  Future<void> _showReservationDetailsDialog(Map<String, dynamic> record) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Text('📋 入庫詳細', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _detailItem(Icons.person, 'お客様名', '${record['customer_name'] ?? '-'} 様'),
                    _detailItem(Icons.directions_car, '対象車両', record['vehicle_name'] ?? '-'),
                    _detailItem(Icons.pin, 'ナンバー', record['plate_no'] ?? '-'),
                    _detailItem(Icons.calendar_today, '入庫日', '${record['entry_date'] ?? '-'} (${record['entry_period'] ?? '-'})'),
                    _detailItem(Icons.event_available, '納車予定', '${record['exit_date'] ?? '-'} (${record['exit_period'] ?? '-'})'),
                    _detailItem(Icons.category, '区分', record['category'] ?? '-'),
                    _detailItem(Icons.notes, '備考', record['remarks'] ?? '-'),
                    const SizedBox(height: 20),
                    Text('登録者: ${record['registered_by'] ?? '-'}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('⚠️ 警告'),
                            content: const Text('この入庫記録を削除しますか？\n紐付いている代車予約がある場合、それも削除されます。'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('削除する', style: TextStyle(color: Colors.red))),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await Supabase.instance.client.from('loaner_records').delete().eq('entry_id', record['id']);
                          await Supabase.instance.client.from('entry_records').delete().eq('id', record['id']);
                          if (context.mounted) Navigator.pop(context);
                          _fetchData();
                        }
                      },
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text('削除', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await showEntryEditDialog(context, record, _currentUserName);
                        _fetchData();
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('編集する'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.blue.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 700;
    final weekDays = ['月', '火', '水', '木', '金', '土', '日'];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('入庫リスト', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 22)),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        actions: [
          PopupMenuButton<FontSizeMode>(
            icon: const Icon(Icons.format_size, color: Colors.black54),
            tooltip: '文字サイズ変更',
            onSelected: (value) => setState(() => _fontSizeMode = value),
            itemBuilder: (context) => [
              const PopupMenuItem(value: FontSizeMode.small, child: Text('文字サイズ：小')),
              const PopupMenuItem(value: FontSizeMode.medium, child: Text('文字サイズ：中')),
              const PopupMenuItem(value: FontSizeMode.large, child: Text('文字サイズ：大')),
            ],
          ),
          if (!isMobile)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: ElevatedButton.icon(
                onPressed: () => _showNewServiceDialog(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('新規入庫受付', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: isMobile 
          ? FloatingActionButton.extended(
              onPressed: () => _showNewServiceDialog(),
              icon: const Icon(Icons.add),
              label: const Text('新規入庫'),
              backgroundColor: Colors.blue.shade700,
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
                  ),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${_baseDate.year}年', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                          Text(
                            '${_baseDate.month}月',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                          ),
                        ],
                      ),
                      const Spacer(),
                      _buildNavBtn(Icons.chevron_left, () => setState(() => _baseDate = _baseDate.subtract(const Duration(days: 14)))),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => setState(() => _baseDate = DateTime.now()),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          side: BorderSide(color: Colors.blue.shade100),
                        ),
                        child: const Text('今日', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      _buildNavBtn(Icons.chevron_right, () => setState(() => _baseDate = _baseDate.add(const Duration(days: 14)))),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: 31,
                    padding: const EdgeInsets.only(top: 12, bottom: 80),
                    itemBuilder: (context, index) {
                      final currentDate = _baseDate.add(Duration(days: index));
                      final isHoliday = holiday_jp.isHoliday(currentDate);
                      final isToday = DateUtils.isSameDay(currentDate, DateTime.now());
                      final dayRecords = _getRecordsForDate(currentDate);
                      return _buildDaySection(currentDate, isToday, isHoliday, dayRecords, weekDays, isMobile);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildNavBtn(IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
      child: IconButton(
        icon: Icon(icon, color: Colors.blue.shade700, size: 20),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildDaySection(DateTime date, bool isToday, bool isHoliday, List<Map<String, dynamic>> records, List<String> weekDays, bool isMobile) {
    final dayKey = "${date.year}-${date.month}-${date.day}";
    final setting = _daySettings[dayKey] ?? {'status': 0, 'memo': ''};
    final int status = setting['status']; // 0:可, 1:要相談, 2:不可
    final String dayMemo = setting['memo'];

    final dayColor = (isHoliday || date.weekday == 7) ? Colors.red : (date.weekday == 6 ? Colors.blue : Colors.blueGrey.shade700);
    
    // ステータスに応じたマークと色
    IconData statusIcon = Icons.circle_outlined;
    Color statusColor = Colors.green;
    String statusLabel = '受付可';
    if (status == 1) {
      statusIcon = Icons.help_outline_rounded;
      statusColor = Colors.orange;
      statusLabel = '要相談';
    } else if (status == 2) {
      statusIcon = Icons.block_flipped;
      statusColor = Colors.red;
      statusLabel = '受付不可';
    }

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左側：日付・ステータス
            Container(
              width: 55,
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isToday ? Colors.blue.shade700 : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isToday ? Colors.blue.shade700 : (isHoliday || date.weekday == 7 ? Colors.red.shade200 : Colors.blue.shade100),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '${date.day}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isToday ? Colors.white : dayColor,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    weekDays[date.weekday - 1],
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: dayColor.withOpacity(0.7)),
                  ),
                  const SizedBox(height: 4),
                  // 受付状況切り替えボタン（管理者のみ有効）
                  InkWell(
                    onTap: !_isAdmin ? null : () async {
                      final current = _daySettings[dayKey] ?? {'status': 0, 'memo': ''};
                      final nextStatus = (current['status'] + 1) % 3;
                      final newMemo = current['memo'].toString();
                      
                      setState(() {
                        _daySettings[dayKey] = {'status': nextStatus, 'memo': newMemo};
                      });
                      await _saveDaySetting(dayKey, nextStatus, newMemo);
                    },
                    child: Column(
                      children: [
                        Icon(statusIcon, size: 20, color: statusColor),
                        Text(statusLabel, style: TextStyle(fontSize: 8, color: statusColor, fontWeight: FontWeight.bold)),
                        // 大型車両がある場合に青丸を表示
                        if (records.any((r) => 
                          (r['remarks']??'').toString().contains('大型') || 
                          (r['remarks']??'').toString().contains('4t') || 
                          (r['remarks']??'').toString().contains('トラック') ||
                          r['is_large'] == true || r['is_large'] == 1
                        )) ...[
                          const SizedBox(height: 4),
                          // 大型マークを大きく（受付可アイコンと同等サイズ）表示
                          Icon(Icons.circle, size: 18, color: Colors.blue.shade700),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // 中央・右側：備考とカードリスト
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   // 備考欄（全日作成、タップで編集）
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Icon(Icons.notes, size: 12, color: Colors.blueGrey.shade200),
                        const SizedBox(width: 4),
                        Expanded(
                          child: InkWell(
                            onTap: !_isAdmin ? null : () async {
                              final controller = TextEditingController(text: dayMemo);
                              final newMemoResult = await showDialog<String>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text('${date.month}月${date.day}日の備考'),
                                  content: TextField(controller: controller, decoration: const InputDecoration(hintText: '例：リフト埋まり、メカ2名不在など')),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
                                    TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('保存')),
                                  ],
                                ),
                              );
                              if (newMemoResult != null) {
                                final currentStatus = (_daySettings[dayKey] ?? {'status': 0})['status'];
                                setState(() {
                                  _daySettings[dayKey] = {'status': currentStatus, 'memo': newMemoResult};
                                });
                                await _saveDaySetting(dayKey, currentStatus, newMemoResult);
                              }
                            },
                            child: Text(
                              dayMemo.isEmpty ? '備考を入力...' : dayMemo,
                              style: TextStyle(
                                fontSize: 10,
                                color: dayMemo.isEmpty ? Colors.grey.shade400 : Colors.blueGrey.shade800,
                                fontStyle: dayMemo.isEmpty ? FontStyle.italic : FontStyle.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12, right: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (records.isNotEmpty) ...[
                          Row(
                            children: [
                              Text(
                                '入庫 ${records.length}台',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.blue.shade900),
                              ),
                              const Spacer(),
                              InkWell(
                                onTap: () => _showNewServiceDialog(initialDate: date),
                                child: Icon(Icons.add_circle_outline, color: Colors.blue.shade300, size: 16),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          // デバイスの向き（縦/横）や種類に応じて段数を切り替え
                          OrientationBuilder(
                            builder: (context, orientation) {
                              // MediaQueryから直接取得することでブラウザ環境でも確実に検知
                              final bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
                              
                              // 横向き(Landscape)なら2段、スマホの縦向き(Portrait)は3段構成
                              final int rowCount = isLandscape ? 2 : (isMobile ? 3 : 1);
                              final double singleRowHeight = isMobile ? 36 : 42;
                              
                              return SizedBox(
                                height: (singleRowHeight * rowCount * _scale).clamp(singleRowHeight * rowCount, 250),
                                child: GridView.builder(
                                  scrollDirection: Axis.horizontal,
                                  shrinkWrap: true,
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: rowCount,
                                    mainAxisExtent: isLandscape ? 280 * _scale : (isMobile ? 180 * _scale : 350 * _scale),
                                    crossAxisSpacing: 2,
                                    mainAxisSpacing: 4,
                                  ),
                                  itemCount: records.length,
                                  itemBuilder: (context, rIndex) {
                                    return _buildCustomerCard(records[rIndex], status == 2);
                                  },
                                ),
                              );
                            },
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Container(width: 3, height: 3, decoration: BoxDecoration(color: Colors.blue.shade100, shape: BoxShape.circle)),
                              const SizedBox(width: 8),
                              Text('予定なし', style: TextStyle(color: Colors.grey.shade300, fontSize: 10)),
                              const Spacer(),
                              InkWell(
                                onTap: () => _showNewServiceDialog(initialDate: date),
                                child: Icon(Icons.add_rounded, color: Colors.grey.shade200, size: 16),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 2, color: Color(0xFFE0E0E0), thickness: 1.2),
      ],
    );
  }

  Widget _buildCustomerCard(Map<String, dynamic> record, bool isRestricted) {
    final String category = (record['category'] ?? '一般').toString();
    final String remarks = (record['remarks'] ?? '').toString();
    
    // 判定ロジック: 明示的なフラグまたはキーワード（互換性のため残す）
    final bool isLargeVehicle = record['is_large'] == true || 
                                record['is_large'] == 1 ||
                                remarks.contains('大型') || remarks.contains('4t') || remarks.contains('トラック');
    
    Color catColor = isRestricted ? Colors.grey : Colors.blue.shade700;
    IconData catIcon = Icons.settings_rounded;
    
    if (category.contains('車検')) {
      catColor = Colors.indigo.shade700;
      catIcon = Icons.fact_check_rounded;
    } else if (category.contains('点検')) {
      catColor = Colors.teal.shade700;
      catIcon = Icons.build_circle_rounded;
    } else if (category.contains('修理')) {
      catColor = Colors.orange.shade800;
      catIcon = Icons.home_repair_service_rounded;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showReservationDetailsDialog(record),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: isLargeVehicle ? Colors.blue.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isLargeVehicle ? Colors.blue.shade700 : (isRestricted ? Colors.grey.shade400 : catColor.withOpacity(0.1)),
              width: isLargeVehicle ? 1.2 : 0.8,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(catIcon, size: 10 * _scale, color: catColor),
              const SizedBox(width: 4),
              // お客様名
              Text(
                '${record['customer_name'] ?? '-'}',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 8.5 * _scale, letterSpacing: -0.5),
              ),
              const SizedBox(width: 4),
              const Text('|', style: TextStyle(color: Colors.black12, fontSize: 9)),
              const SizedBox(width: 4),
              // 車種・下4桁
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${record['vehicle_name'] ?? '-'}',
                        style: TextStyle(fontSize: 7.5 * _scale, color: Colors.grey.shade700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _getLast4Digits(record['plate_no']),
                      style: TextStyle(fontSize: 7.5 * _scale, color: Colors.blue.shade700, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              if (remarks.isNotEmpty || isLargeVehicle || isRestricted) ...[
                const SizedBox(width: 4),
                const Text('|', style: TextStyle(color: Colors.black12, fontSize: 9)),
                const SizedBox(width: 4),
                if (isRestricted) Icon(Icons.block, size: 8 * _scale, color: Colors.grey),
                if (isLargeVehicle) Icon(Icons.circle, size: 8 * _scale, color: Colors.blue.shade700),
                if (remarks.isNotEmpty)
                  Flexible(
                    child: Text(
                      ' $remarks',
                      style: TextStyle(fontSize: 7 * _scale, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
