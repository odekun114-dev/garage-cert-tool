import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:holiday_jp/holiday_jp.dart' as holiday_jp;
import 'action_dialogs.dart';

// ============================================================================
// 🔥 代車管理カレンダー（全方位タップ反応 ＆ 空車確認ボトムシート版）
// ============================================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _baseDate = DateTime.now();
  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _records = [];
  bool _isLoading = true;
  String _currentUserName = '担当者';
  int? _filterVehicleId; // ★追加：特定の車両のみ表示するフィルター用ID

  // ★ 追加：車両カテゴリフィルター
  String _selectedCategory = '全体';
  final List<Map<String, dynamic>> _categories = [
    {'name': '全体', 'icon': Icons.apps},
    {'name': '軽自動車', 'icon': Icons.directions_car},
    {'name': '普通車', 'icon': Icons.directions_car_filled},
    {'name': '貨物車', 'icon': Icons.local_shipping},
    {'name': 'レンタカー軽自動車', 'icon': Icons.car_rental},
    {'name': 'レンタカー普通車', 'icon': Icons.car_rental},
    {'name': 'レンタカー貨物車', 'icon': Icons.vignette},
    {'name': '他', 'icon': Icons.more_horiz},
  ];

  // ★ 追加：表示密度（サイズ）の切り替え用
  // 0: 極小 (Compact), 1: 標準 (Standard), 2: 大きめ (Large)
  int _uiDensity = 1;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle();
      if (profile != null) _currentUserName = profile['full_name'];
    }

    final vData = await Supabase.instance.client
        .from('master_vehicles')
        .select()
        .order('type', ascending: true)
        .order('id', ascending: true);

    final rData = await Supabase.instance.client
        .from('loaner_records')
        .select();

    if (mounted) {
      setState(() {
        _vehicles = List<Map<String, dynamic>>.from(vData);
        _records = List<Map<String, dynamic>>.from(rData);
        _isLoading = false;
      });
    }
  }

  void _changeDate(int days) {
    setState(() => _baseDate = _baseDate.add(Duration(days: days)));
  }

  // ★ 追加：ナビゲーションボタンのビルダー
  Widget _buildNavButton({required VoidCallback onPressed, required IconData icon}) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: Colors.blue.shade900),
      ),
    );
  }

  // ★ 追加：スタイリッシュなカテゴリタブのビルダー
  Widget _buildCategoryTab(Map<String, dynamic> category) {
    final String name = category['name'];
    final IconData icon = category['icon'];
    final bool isSelected = _selectedCategory == name;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCategory = name;
          _filterVehicleId = null;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8, bottom: 4, top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade800 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  )
                ],
          border: Border.all(
            color: isSelected ? Colors.blue.shade900 : Colors.grey.shade300,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.blue.shade800,
            ),
            const SizedBox(width: 6),
            Text(
              name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ★ 追加：密度切り替えボタンのビルダー
  Widget _buildDensityButton(int density, String label) {
    final bool isSelected = _uiDensity == density;
    return GestureDetector(
      onTap: () => setState(() => _uiDensity = density),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade800 : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  // ★ 追加：現在の密度に基づいたサイズ設定を取得する
  Map<String, double> _getDynamicSizes() {
    switch (_uiDensity) {
      case 0: // 極小 (Compact)
        return {
          'rowHeight': 45.0,
          'vehicleWidth': 100.0,
          'headerHeight': 40.0,
          'fontMain': 9.0,
          'fontSub': 8.5,
          'fontTiny': 8.5,
        };
      case 2: // 大きめ (Large)
        return {
          'rowHeight': 85.0,
          'vehicleWidth': 160.0,
          'headerHeight': 65.0,
          'fontMain': 13.0,
          'fontSub': 11.5,
          'fontTiny': 11.5,
        };
      case 1: // 標準 (Standard)
      default:
        return {
          'rowHeight': 65.0,
          'vehicleWidth': 130.0,
          'headerHeight': 55.0,
          'fontMain': 11.0,
          'fontSub': 10.0,
          'fontTiny': 10.0,
        };
    }
  }

  // ★ 1. 空車確認ボトムシート（駐車場位置を明示）
  void _showAvailableVehiclesSheet() {
    final availableCars = _vehicles.where((v) => v['status'] != 1).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '🔑 空車確認・使用中リスト',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: availableCars.length,
                itemBuilder: (context, index) {
                  final car = availableCars[index];
                  final bool isStaffUse = car['status'] == 2;
                  final String location = car['parking'] ?? '不明';

                  return Container(
                    width: 140,
                    margin: const EdgeInsets.only(right: 12, bottom: 8),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isStaffUse
                            ? Colors.blue.shade50
                            : Colors.green.shade50,
                        foregroundColor: isStaffUse
                            ? Colors.blue.shade900
                            : Colors.green.shade900,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(8),
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                        setState(() {
                          _filterVehicleId = car['id'];
                        });
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            car['name'],
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          if (isStaffUse)
                            Text(
                              '👤 ${car['staff_use']}\n使用中',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 10),
                            )
                          else
                            Text(
                              '🅿️ $location 駐車場',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  // ★ 2. 車両情報セル（左リスト）
  Widget _buildVehicleInfoCell(
    Map<String, dynamic> car,
    Map<String, double> sizes,
  ) {
    final int status = car['status'];
    final String location = car['parking'] ?? '不明';
    Color accentColor = status == 1
        ? Colors.red
        : (status == 2 ? Colors.blue : Colors.green);

    return InkWell(
      onTap: () async {
        await showVehicleActionDialog(context, car, _currentUserName);
        _fetchInitialData();
      },
      child: Container(
        height: sizes['rowHeight'],
        width: sizes['vehicleWidth'],
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: status == 1
              ? Colors.red.shade50
              : (status == 2 ? Colors.blue.shade50 : Colors.white),
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade300),
            left: BorderSide(color: accentColor, width: 4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${car['name'] ?? ''} ${_toJpYear(car['model_year'])} ${car['color'] ?? ''}'.trim(),
              style: TextStyle(
                fontSize: sizes['fontMain'],
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${_getLast4Digits(car['plate_no'])} ${_toJpDate(car['inspection_expiry'])}'.trim(),
              style: TextStyle(
                fontSize: sizes['fontSub'],
                color: Colors.blueGrey,
                height: 1.1,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 1),
            if (status == 1)
              Text(
                '⚠️ 貸出中',
                style: TextStyle(
                  fontSize: sizes['fontSub'],
                  color: Colors.red.shade800,
                  fontWeight: FontWeight.bold,
                ),
              )
            else if (status == 2)
              Text(
                '👤 ${car['staff_use'] ?? '不明'}',
                style: TextStyle(
                  fontSize: sizes['fontSub'],
                  color: Colors.blue.shade800,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              )
            else
              Text(
                '🅿️ $location 駐車場',
                style: TextStyle(
                  fontSize: sizes['fontSub'],
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }

  // 予定表の制限・警告表示用
  Widget _buildReservationBar(
    Map<String, dynamic> record,
    Map<String, dynamic> car,
    double barWidth,
    double barHeight,
    Map<String, double> sizes,
  ) {
    final name = record['customer_name'] ?? '名前なし';
    final category = record['category']?.toString() ?? '';
    final condition = record['rental_condition']?.toString() ?? '';
    final bool isReturned =
        record['is_returned'].toString() == '1' ||
        record['is_returned'].toString() == 'true';

    // 今日の日付を取得（時刻を00:00:00に正規化）
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final startDate = DateTime.parse(record['start_date']);

    Color barColor;
    String statusIcon = '📅';
    if (isReturned) {
      barColor = Colors.grey.shade400; // 1. 貸出済み（灰色）
      statusIcon = '✅';
    } else if (car['status'] == 1 && !startDate.isAfter(today)) {
      barColor = Colors.red.shade800; // 2. 貸出中（赤）
      statusIcon = '🔑';
    } else {
      barColor = Colors.lightBlue.shade300; // 3. 予定（水色）
    }

    // 車両サイズによるアイコン判定（貨物車やレンタカー貨物車を「大きい車両」とみなす）
    final bool isLargeVehicle = car['category']?.toString().contains('貨物') ?? false;

    return InkWell(
      onTap: () async {
        await showEditReservationDialog(context, record, car);
        _fetchInitialData();
      },
      child: Container(
        width: barWidth,
        height: barHeight,
        decoration: BoxDecoration(
          color: barColor,
          borderRadius: BorderRadius.circular(3),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLargeVehicle)
                  Container(
                    margin: const EdgeInsets.only(right: 2),
                    padding: const EdgeInsets.all(1),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.circle, size: 8, color: Colors.blue),
                  )
                else
                  Text(statusIcon, style: TextStyle(fontSize: sizes['fontTiny'])),
                const SizedBox(width: 1),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: sizes['fontSub'],
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  category + (condition == '無料' ? '(無)' : ''),
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: sizes['fontTiny'],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (isLargeVehicle)
                  const Text(' ※', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ヘッダー・日付
  Widget _buildDayColumnHeader(
    DateTime date,
    double dayWidth,
    Map<String, double> sizes,
  ) {
    final now = DateTime.now();
    final bool isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    final isHoliday = holiday_jp.isHoliday(date);
    final isWeekend =
        date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
    final weekDays = ['月', '火', '水', '木', '金', '土', '日'];
    
    Color bgColor = isToday 
        ? Colors.blue.shade100 
        : (isHoliday || isWeekend) ? Colors.red.shade50 : Colors.grey.shade100;

    // その日の予約数をカウント（社用を除く）
    final dailyRecords = _records.where((r) => 
      r['category'] != '社用' && 
      r['start_date'] != null && 
      r['end_date'] != null &&
      DateTime.parse(r['start_date']).isBefore(date.add(const Duration(days: 1))) &&
      DateTime.parse(r['end_date']).isAfter(date.subtract(const Duration(seconds: 1)))
    ).toList();

    // 全体の予約がいっぱい（例：車両数の80%以上）
    final bool isFull = _vehicles.isNotEmpty && dailyRecords.length >= (_vehicles.length * 0.8);

    return Container(
      width: dayWidth,
      height: sizes['headerHeight'],
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.grey.shade300, width: 1),
          bottom: isToday ? BorderSide(color: Colors.blue.shade800, width: 2) : BorderSide.none,
        ),
        color: bgColor,
      ),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isToday)
                    Text(
                      '今日',
                      style: TextStyle(
                        fontSize: sizes['fontTiny']! - 1,
                        color: Colors.blue.shade900,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${date.month}/${date.day}(${weekDays[date.weekday - 1]})',
                        style: TextStyle(
                          fontSize: sizes['fontMain'],
                          color: isToday 
                              ? Colors.blue.shade900 
                              : (isHoliday || isWeekend) ? Colors.red.shade800 : Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isFull)
                        const Text(' ※', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: sizes['fontSub']! * 2,
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade300, width: 1),
                      right: BorderSide(color: Colors.grey.shade300, width: 1),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'AM',
                    style: TextStyle(
                      fontSize: sizes['fontTiny'],
                      color: isToday ? Colors.blue.shade900 : Colors.black54,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  height: sizes['fontSub']! * 2,
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade300, width: 1),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'PM',
                    style: TextStyle(
                      fontSize: sizes['fontTiny'],
                      color: isToday ? Colors.blue.shade900 : Colors.black54,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // バー配置ロジック
  List<Widget> _buildReservationBars(
    double dayWidth,
    List<Map<String, dynamic>> vehicles,
    DateTime baseDate,
    Map<String, double> sizes,
  ) {
    List<Widget> bars = [];
    final normalizedBaseDate = DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
    );
    for (int vIdx = 0; vIdx < vehicles.length; vIdx++) {
      final vRecords = _records
          .where(
            (r) =>
                r['loaner_id'] == vehicles[vIdx]['id'] && r['category'] != '社用',
          )
          .toList();
      for (var record in vRecords) {
        if (record['start_date'] == null || record['end_date'] == null) {
          continue;
        }
        DateTime sDate = DateTime.parse('${record['start_date']} 00:00:00');
        DateTime eDate = DateTime.parse('${record['end_date']} 00:00:00');
        if (eDate.isBefore(normalizedBaseDate) ||
            sDate.isAfter(normalizedBaseDate.add(const Duration(days: 13)))) {
          continue;
        }

        double leftPos = sDate.difference(normalizedBaseDate).inDays * dayWidth;
        if (record['start_period'] == 'PM') leftPos += dayWidth / 2;
        if (leftPos < 0) leftPos = 0;

        double rightPos = dayWidth * 14;
        if (eDate.isBefore(normalizedBaseDate.add(const Duration(days: 14)))) {
          rightPos =
              (eDate.difference(normalizedBaseDate).inDays + 1) * dayWidth;
          if (record['end_period'] == 'AM') rightPos -= dayWidth / 2;
        }

        double barWidth = rightPos - leftPos;
        if (barWidth < 20) barWidth = 20;

        bars.add(
          Positioned(
            left: leftPos + 1,
            top: vIdx * sizes['rowHeight']! + 3.0,
            child: _buildReservationBar(
              record,
              vehicles[vIdx],
              barWidth - 2,
              sizes['rowHeight']! - 6.0,
              sizes,
            ),
          ),
        );
      }
    }
    return bars;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final sizes = _getDynamicSizes();

    final weekStartDate = _baseDate.subtract(Duration(days: _baseDate.weekday - 1));
    final weekEndDate = weekStartDate.add(const Duration(days: 7));

    final filteredByDeletion = _vehicles.where((v) {
      if (v['deleted_at'] == null) return true;
      final deletedAt = DateTime.parse(v['deleted_at']);
      // 表示中の週の開始日が削除日より前であれば表示する
      return weekStartDate.isBefore(deletedAt);
    }).toList();

    final filteredByCategory = _selectedCategory == '全体'
        ? filteredByDeletion
        : filteredByDeletion.where((v) => v['category'] == _selectedCategory).toList();

    final displayVehicles = _filterVehicleId == null
        ? filteredByCategory
        : filteredByCategory.where((v) => v['id'] == _filterVehicleId).toList();

    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: Colors.white,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _buildNavButton(
                          onPressed: () => _changeDate(-7),
                          icon: Icons.arrow_back_ios_new,
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => setState(() => _baseDate = DateTime.now()),
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.blue.shade50,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(
                            '今日',
                            style: TextStyle(
                              color: Colors.blue.shade900,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildNavButton(
                          onPressed: () => _changeDate(7),
                          icon: Icons.arrow_forward_ios,
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildDensityButton(0, '小'),
                              _buildDensityButton(1, '中'),
                              _buildDensityButton(2, '大'),
                            ],
                          ),
                        ),
                        if (_filterVehicleId != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () => setState(() => _filterVehicleId = null),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.red.shade200),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.close, size: 14, color: Colors.red.shade800),
                                    const SizedBox(width: 4),
                                    Text(
                                      '全表示',
                                      style: TextStyle(
                                        color: Colors.red.shade800,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ElevatedButton.icon(
                          onPressed: _showAvailableVehiclesSheet,
                          icon: const Icon(Icons.search, size: 16),
                          label: const Text(
                            '空車確認',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade800,
                            foregroundColor: Colors.white,
                            elevation: 2,
                            shadowColor: Colors.blue.withOpacity(0.5),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    itemBuilder: (context, index) => _buildCategoryTab(_categories[index]),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: sizes['vehicleWidth'],
                  child: Column(
                    children: [
                      Container(
                        height: sizes['headerHeight'],
                        decoration: BoxDecoration(
                          color: Colors.blue.shade800,
                          border: Border.all(color: Colors.blue.shade900),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '車両情報',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: sizes['fontSub'],
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          physics: const ClampingScrollPhysics(),
                          itemCount: displayVehicles.length,
                          itemBuilder: (context, index) =>
                              _buildVehicleInfoCell(
                                displayVehicles[index],
                                sizes,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      double dayWidth = constraints.maxWidth / 3;
                      if (dayWidth > 120) dayWidth = 120;
                      if (dayWidth < 80) dayWidth = 80;

                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: dayWidth * 14,
                          child: Column(
                            children: [
                              Row(
                                children: List.generate(
                                  14,
                                  (i) => _buildDayColumnHeader(
                                    _baseDate.add(Duration(days: i)),
                                    dayWidth,
                                    sizes,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: SingleChildScrollView(
                                  physics: const ClampingScrollPhysics(),
                                  child: SizedBox(
                                    height:
                                        displayVehicles.length *
                                        sizes['rowHeight']!,
                                    child: Stack(
                                      children: [
                                        Column(
                                          children: displayVehicles
                                              .map(
                                                (car) => Container(
                                                  height: sizes['rowHeight'],
                                                  decoration: BoxDecoration(
                                                    border: Border(
                                                      bottom: BorderSide(
                                                        color: Colors
                                                            .grey
                                                            .shade300,
                                                        width: 1,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    children: List.generate(14, (
                                                      i,
                                                    ) {
                                                      final d = _baseDate.add(
                                                        Duration(days: i),
                                                      );
                                                      return SizedBox(
                                                        width: dayWidth,
                                                        child: InkWell(
                                                          onTap: () async {
                                                            final now =
                                                                DateTime.now();
                                                            final String
                                                            initPeriod =
                                                                (d.year ==
                                                                        now.year &&
                                                                    d.month ==
                                                                        now.month &&
                                                                    d.day ==
                                                                        now.day &&
                                                                    now.hour >=
                                                                        12)
                                                                ? 'PM'
                                                                : 'AM';
                                                            final bool
                                                            completed = await showNewReservationDialog(
                                                              context,
                                                              car,
                                                              d,
                                                              _currentUserName,
                                                              initialStartPeriod:
                                                                  initPeriod,
                                                            );
                                                            if (completed ==
                                                                true) {
                                                              _fetchInitialData();
                                                            }
                                                          },
                                                          child: Row(
                                                            children: [
                                                              Expanded(
                                                                child: Container(
                                                                  decoration: BoxDecoration(
                                                                    border: Border(
                                                                      right: BorderSide(
                                                                        color: Colors
                                                                            .grey
                                                                            .shade200,
                                                                        width:
                                                                            1,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                              Expanded(
                                                                child: Container(
                                                                  decoration: BoxDecoration(
                                                                    border: Border(
                                                                      right: BorderSide(
                                                                        color: Colors
                                                                            .grey
                                                                            .shade300,
                                                                        width:
                                                                            1,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      );
                                                    }),
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                        ),
                                        ..._buildReservationBars(
                                          dayWidth,
                                          displayVehicles,
                                          _baseDate,
                                          sizes,
                                        ),
                                        Builder(
                                          builder: (context) {
                                            final now = DateTime.now();
                                            final today = DateTime(now.year, now.month, now.day);
                                            final normalizedBase = DateTime(_baseDate.year, _baseDate.month, _baseDate.day);
                                            final diff = today.difference(normalizedBase).inDays;
                                            
                                            if (diff >= 0 && diff < 14) {
                                              return Positioned(
                                                left: diff * dayWidth + (now.hour >= 12 ? dayWidth / 2 : 0),
                                                top: 0,
                                                bottom: 0,
                                                child: Container(
                                                  width: 2,
                                                  color: Colors.blue.withOpacity(0.5),
                                                ),
                                              );
                                            }
                                            return const SizedBox.shrink();
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final bool completed = await showNewReservationDialog(
            context,
            null,
            DateTime.now(),
            _currentUserName,
          );
          if (completed == true) _fetchInitialData();
        },
        label: const Text(
          '新規予約',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        icon: const Icon(Icons.add, color: Colors.white),
        backgroundColor: Colors.blue.shade800,
      ),
    );
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

  // ナンバープレートから下4桁（または末尾の数字）を抽出する
  String _getLast4Digits(String? plateNo) {
    if (plateNo == null || plateNo.isEmpty || plateNo == '-') return '-';
    final clean = plateNo.replaceAll(RegExp(r'\D'), '');
    if (clean.length >= 4) {
      return clean.substring(clean.length - 4);
    }
    return clean.isEmpty ? plateNo : clean;
  }
}
