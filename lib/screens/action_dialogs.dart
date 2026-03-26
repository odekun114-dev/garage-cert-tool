import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:calendar_date_picker2/calendar_date_picker2.dart';

// ★ 共通ヘルパー: 西暦を和暦年(R6年)に変換
String _toJpYear(dynamic val) {
  if (val == null) return '';
  int? year = int.tryParse(val.toString());
  if (year == null || year == 0) return '';
  if (year >= 2019) return 'R${year - 2018}年';
  if (year >= 1989) return 'H${year - 1988}年';
  if (year >= 1926) return 'S${year - 1925}年';
  return '${year}年';
}

// ★ 共通ヘルパー: 和暦(R8.2.28)表示への変換
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

// ★ 共通ヘルパー: ナンバープレートから下4桁を抽出
String _getLast4Digits(String? plateNo) {
  if (plateNo == null || plateNo.isEmpty || plateNo == '-') return '-';
  final clean = plateNo.replaceAll(RegExp(r'\D'), '');
  if (clean.length >= 4) {
    return clean.substring(clean.length - 4);
  }
  return clean.isEmpty ? plateNo : clean;
}

// ============================================================================
// 1. 車両操作パネル（営業優先・PM自動判別版）
// ============================================================================
Future<void> showVehicleActionDialog(
  BuildContext context,
  Map<String, dynamic> car,
  String currentUserName,
) async {
  String selectedParking = car['parking'] ?? 'A';
  final int status = car['status'];

  await showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          title: Text('🚗 ${car['name']} の操作パネル'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status == 0 || status == 2 || status == 3) ...[
                Text(
                  status == 2
                      ? '👤 ${car['staff_use']} が使用中ですが、'
                      : '✅ 現在貸出可能です',
                ),
                const Text('お客様に貸し出しますか？'),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                      ),
                      onPressed: () async {
                        final now = DateTime.now();
                        final String initialPeriod =
                            now.hour >= 12 ? 'PM' : 'AM';
                        final bool completed = await showNewReservationDialog(
                          context,
                          car,
                          now,
                          currentUserName,
                          initialCategory: 'クイック',
                          isImmediateLoan: true,
                          initialStartPeriod: initialPeriod,
                        );
                        if (completed && context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                      child: const Text(
                        'お客様貸出',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    if (status == 0 || status == 3)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade400,
                        ),
                        onPressed: () =>
                            _executeStaffUse(context, car, currentUserName),
                        child: const Text(
                          '従業員使用',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ],
              if (status == 1 || status == 2) ...[
                const SizedBox(height: 16),
                const Divider(),
                const Text(
                  '🔙 返却処理',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedParking,
                  decoration: const InputDecoration(labelText: '返却時の駐車位置'),
                  items: ['A', 'B', 'C', 'D']
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (val) => setState(() => selectedParking = val!),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade700,
                  ),
                  onPressed: () =>
                      _executeReturn(context, car, selectedParking),
                  child: const Text(
                    '返却処理を完了する',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    ),
  );
}

// 従業員使用・返却ロジック
Future<void> _executeStaffUse(
  BuildContext context,
  Map<String, dynamic> newCar,
  String staffName,
) async {
  final List<dynamic> activeRecords = await Supabase.instance.client
      .from('loaner_records')
      .select('*, master_vehicles(*)')
      .eq('customer_name', staffName)
      .eq('category', '社用')
      .eq('is_returned', 0);
  if (activeRecords.isNotEmpty) {
    for (var record in activeRecords) {
      final oldCar = record['master_vehicles'];
      if (oldCar == null) continue;
      String? oldParking = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('⚠️ 重複使用の検知'),
          content: Text(
            '$staffName さん、まだ『${oldCar['name']}』を返却していません！\n駐車位置を選択してください。',
          ),
          actions: ['A', 'B', 'C', 'D']
              .map(
                (p) => TextButton(
                  onPressed: () => Navigator.pop(ctx, p),
                  child: Text('$p 駐車場'),
                ),
              )
              .toList(),
        ),
      );
      if (oldParking != null) {
        final now = DateTime.now();
        await Supabase.instance.client
            .from('master_vehicles')
            .update({'status': 0, 'parking': oldParking, 'staff_use': null})
            .eq('id', oldCar['id']);
        await Supabase.instance.client
            .from('loaner_records')
            .update({
              'is_returned': 1,
              'end_date': now.toIso8601String().split('T')[0],
              'end_period': now.hour < 12 ? 'AM' : 'PM',
              'parking_spot': oldParking,
            })
            .eq('id', record['id']);
      }
    }
  }
  final now = DateTime.now();
  await Supabase.instance.client
      .from('master_vehicles')
      .update({'status': 2, 'staff_use': staffName})
      .eq('id', newCar['id']);
  await Supabase.instance.client.from('loaner_records').insert({
    'loaner_id': newCar['id'],
    'customer_name': staffName,
    'category': '社用',
    'start_date': now.toIso8601String().split('T')[0],
    'start_period': now.hour < 12 ? 'AM' : 'PM',
    'end_date': now.toIso8601String().split('T')[0],
    'end_period': 'PM',
    'is_returned': 0,
    'registered_by': staffName,
  });
  if (context.mounted) Navigator.pop(context);
}

Future<void> _executeReturn(
  BuildContext context,
  Map<String, dynamic> car,
  String parking,
) async {
  try {
    final now = DateTime.now();
    final todayStr = now.toIso8601String().split('T')[0];

    // 1. 車両ステータスを更新
    await Supabase.instance.client
        .from('master_vehicles')
        .update({'status': 0, 'parking': parking, 'staff_use': null})
        .eq('id', car['id']);

    // 2. 未返却のレコードを検索
    final List<dynamic> raw = await Supabase.instance.client
        .from('loaner_records')
        .select()
        .eq('loaner_id', car['id'])
        .eq('is_returned', 0)
        .lte('start_date', todayStr);

    if (raw.isNotEmpty) {
      final records = List<Map<String, dynamic>>.from(raw);
      // 車両の状態に合わせてターゲットを特定
      final target = car['status'] == 2
          ? records.firstWhere(
              (r) => r['category'] == '社用',
              orElse: () => records.first,
            )
          : records.firstWhere(
              (r) => r['category'] != '社用',
              orElse: () => records.first,
            );

      // 3. レコードを返却済みに更新
      await Supabase.instance.client
          .from('loaner_records')
          .update({
            'is_returned': 1,
            'end_date': todayStr,
            'end_period': now.hour < 12 ? 'AM' : 'PM',
            'parking_spot': parking,
          })
          .eq('id', target['id']);
    }

    if (context.mounted) Navigator.pop(context);
  } catch (e) {
    debugPrint('Return Error: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('返却処理中にエラーが発生しました: $e')),
      );
    }
  }
}

// ============================================================================
// 2. 新規予約ダイアログ
// ============================================================================
Future<bool> showNewReservationDialog(
  BuildContext context,
  Map<String, dynamic>? preSelectedCar,
  DateTime preDate,
  String currentUserName, {
  String? initialCategory,
  String? initialName,
  bool isImmediateLoan = false,
  String initialStartPeriod = 'AM',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => NewReservationDialogWidget(
      preSelectedCar: preSelectedCar,
      preDate: preDate,
      currentUserName: currentUserName,
      initialCategory: initialCategory,
      initialName: initialName,
      isImmediateLoan: isImmediateLoan,
      initialStartPeriod: initialStartPeriod,
    ),
  );
  return result ?? false;
}

class NewReservationDialogWidget extends StatefulWidget {
  final Map<String, dynamic>? preSelectedCar;
  final DateTime preDate;
  final String currentUserName;
  final String? initialCategory;
  final String? initialName;
  final bool isImmediateLoan;
  final String initialStartPeriod;
  const NewReservationDialogWidget({
    super.key,
    this.preSelectedCar,
    required this.preDate,
    required this.currentUserName,
    this.initialCategory,
    this.initialName,
    this.isImmediateLoan = false,
    this.initialStartPeriod = 'AM',
  });
  @override
  State<NewReservationDialogWidget> createState() =>
      _NewReservationDialogWidgetState();
}

class _NewReservationDialogWidgetState
    extends State<NewReservationDialogWidget> {
  late DateTimeRange _selectedDateRange;
  late String _startAmPm;
  String _endAmPm = 'PM';
  String _category = '車検';
  String _rentalCondition = '有料'; // ★追加：有料・無料の初期値
  List<Map<String, dynamic>> _allVehicles = [];
  List<Map<String, dynamic>> _activeRecords = [];
  List<Map<String, dynamic>> _availableVehicles = [];
  int? _selectedCarId;
  final TextEditingController _nameController = TextEditingController();
  bool _isLoading = true;
  final List<String> _validCategories = [
    '車検',
    '点検',
    'クイック',
    '板金',
    'レンタ',
    '社用',
    'その他',
  ];

  @override
  void initState() {
    super.initState();
    _selectedDateRange = DateTimeRange(
      start: widget.preDate,
      end: widget.preDate,
    );
    _selectedCarId = widget.preSelectedCar?['id'] as int?;
    _startAmPm = widget.initialStartPeriod;
    if (widget.initialCategory != null &&
        _validCategories.contains(widget.initialCategory)) {
      _category = widget.initialCategory!;
    }
    if (widget.initialName != null) _nameController.text = widget.initialName!;
    _fetchDataAndCheckAvailability();
  }

  Future<void> _fetchDataAndCheckAvailability() async {
    setState(() => _isLoading = true);
    final vData = await Supabase.instance.client
        .from('master_vehicles')
        .select();
    final rData = await Supabase.instance.client
        .from('loaner_records')
        .select()
        .eq('is_returned', 0);
    _allVehicles = List<Map<String, dynamic>>.from(vData);
    _activeRecords = List<Map<String, dynamic>>.from(rData);
    _filterAvailableVehicles();
  }

  void _filterAvailableVehicles() {
    List<Map<String, dynamic>> available = [];
    double newS = _dateToVal(_selectedDateRange.start, _startAmPm);
    double newE = _dateToVal(_selectedDateRange.end, _endAmPm);
    for (var car in _allVehicles) {
      if (car['status'] == 1) continue;
      bool overlap = false;
      for (var r in _activeRecords) {
        if (r['loaner_id'] != car['id'] || r['category'] == '社用') continue;
        double rs = _dateToVal(
          DateTime.parse(r['start_date']),
          r['start_period'] ?? 'AM',
        );
        double re = _dateToVal(
          DateTime.parse(r['end_date']),
          r['end_period'] ?? 'PM',
        );
        if ((newS > rs ? newS : rs) <= (newE < re ? newE : re)) {
          overlap = true;
          break;
        }
      }
      if (!overlap) available.add(car);
    }
    setState(() {
      _availableVehicles = available;
      if (_selectedCarId == null ||
          !_availableVehicles.any((c) => c['id'] == _selectedCarId)) {
        _selectedCarId = _availableVehicles.isEmpty
            ? null
            : _availableVehicles.first['id'];
      }
      _isLoading = false;
    });
  }

  double _dateToVal(DateTime d, String ampm) =>
      d.difference(DateTime(2020, 1, 1)).inDays + (ampm == 'AM' ? 0.0 : 0.5);

  Future<void> _submitReservation() async {
    if (_nameController.text.isEmpty || _selectedCarId == null) return;
    final selCar = _allVehicles.firstWhere((c) => c['id'] == _selectedCarId);
    if (selCar['status'] == 2) {
      final now = DateTime.now();
      await Supabase.instance.client
          .from('loaner_records')
          .update({
            'is_returned': 1,
            'end_date': now.toIso8601String().split('T')[0],
            'end_period': now.hour < 12 ? 'AM' : 'PM',
            'parking_spot': selCar['parking'],
          })
          .eq('loaner_id', _selectedCarId!)
          .eq('is_returned', 0)
          .eq('category', '社用');
    }
    await Supabase.instance.client.from('loaner_records').insert({
      'loaner_id': _selectedCarId,
      'customer_name': _nameController.text,
      'start_date': _selectedDateRange.start.toIso8601String().split('T')[0],
      'end_date': _selectedDateRange.end.toIso8601String().split('T')[0],
      'start_period': _startAmPm,
      'end_period': _endAmPm,
      'category': _category,
      'rental_condition': (selCar['type'] == 'rental' || (selCar['category']?.toString().contains('レンタ') ?? false)) ? _rentalCondition : null, // ★追加
      'is_returned': 0,
      'registered_by': widget.currentUserName,
    });
    if (widget.isImmediateLoan) {
      await Supabase.instance.client
          .from('master_vehicles')
          .update({'status': 1, 'staff_use': null})
          .eq('id', _selectedCarId!);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('➕ 新規予約・貸出登録'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () async {
                final picked = await showDialog<List<DateTime?>>(
                  context: context,
                  builder: (ctx) => Dialog(
                    child: CalendarDatePicker2(
                      config: CalendarDatePicker2Config(
                        calendarType: CalendarDatePicker2Type.range,
                      ),
                      value: [_selectedDateRange.start, _selectedDateRange.end],
                      onValueChanged: (dates) {
                        if (dates.length == 2) {
                          Navigator.pop(ctx, dates);
                        }
                      },
                    ),
                  ),
                );
                if (picked != null) {
                  setState(() {
                    _selectedDateRange = DateTimeRange(
                      start: picked[0]!,
                      end: picked[1]!,
                    );
                    _filterAvailableVehicles();
                  });
                }
              },
              child: Text(
                '${_selectedDateRange.start.month}/${_selectedDateRange.start.day} 〜 ${_selectedDateRange.end.month}/${_selectedDateRange.end.day}',
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _startAmPm,
                    items: ['AM', 'PM']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _startAmPm = v!;
                      _filterAvailableVehicles();
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _endAmPm,
                    items: ['AM', 'PM']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _endAmPm = v!;
                      _filterAvailableVehicles();
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: '入庫区分'),
              items: _validCategories
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v!),
            ),
            // ★レンタカーの場合のみ「有料・無料」の選択肢を表示
            if (_selectedCarId != null) ...[
              Builder(builder: (context) {
                final selCar = _availableVehicles.firstWhere(
                  (c) => c['id'] == _selectedCarId,
                  orElse: () => {},
                );
                final bool isRental = selCar['type'] == 'rental' ||
                    (selCar['category']?.toString().contains('レンタ') ?? false);
                if (!isRental) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    const Text('💰 レンタカー条件',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    DropdownButtonFormField<String>(
                      initialValue: _rentalCondition,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Color(0xFFFFF9C4),
                      ),
                      items: ['有料', '無料']
                          .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                          .toList(),
                      onChanged: (v) => setState(() => _rentalCondition = v!),
                    ),
                  ],
                );
              }),
            ],
            const SizedBox(height: 16),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              DropdownButtonFormField<int?>(
                initialValue: _selectedCarId,
                items: _availableVehicles
                    .map(
                      (c) => DropdownMenuItem<int?>(
                        value: c['id'],
                        child: Text('${c['name']}'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedCarId = v),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'お客様名'),
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
          onPressed: _submitReservation,
          child: const Text('予約確定'),
        ),
      ],
    );
  }
}

// ============================================================================
// 3. 予約編集ダイアログ（完了レコード操作封鎖版）
// ============================================================================
Future<void> showEditReservationDialog(
  BuildContext context,
  Map<String, dynamic> record,
  Map<String, dynamic> car,
) async {
  await showDialog(
    context: context,
    builder: (context) => EditReservationDialogWidget(record: record, car: car),
  );
}

class EditReservationDialogWidget extends StatefulWidget {
  final Map<String, dynamic> record;
  final Map<String, dynamic> car;
  const EditReservationDialogWidget({
    super.key,
    required this.record,
    required this.car,
  });

  @override
  State<EditReservationDialogWidget> createState() =>
      _EditReservationDialogWidgetState();
}

class _EditReservationDialogWidgetState
    extends State<EditReservationDialogWidget> {
  late DateTimeRange _selectedDateRange;
  late String _startAmPm;
  late String _endAmPm;
  late String _category;
  late String _rentalCondition; // ★追加
  late TextEditingController _nameController;
  final List<String> _validCategories = [
    '車検',
    '点検',
    'クイック',
    '板金',
    'レンタ',
    '社用',
    'その他',
  ];

  @override
  void initState() {
    super.initState();
    _selectedDateRange = DateTimeRange(
      start: DateTime.parse(widget.record['start_date']),
      end: DateTime.parse(widget.record['end_date']),
    );
    _startAmPm = widget.record['start_period'] ?? 'AM';
    _endAmPm = widget.record['end_period'] ?? 'PM';
    _category = widget.record['category'] ?? 'その他';
    _rentalCondition = widget.record['rental_condition'] ?? '有料'; // ★追加
    _nameController = TextEditingController(
      text: widget.record['customer_name'],
    );
  }

  Future<void> _startLoan() async {
    final now = DateTime.now();
    final String todayStr = now.toIso8601String().split('T')[0];
    final String amPm = now.hour >= 12 ? 'PM' : 'AM';

    await Supabase.instance.client
        .from('master_vehicles')
        .update({'status': 1, 'staff_use': null})
        .eq('id', widget.car['id']);

    await Supabase.instance.client
        .from('loaner_records')
        .update({'start_date': todayStr, 'start_period': amPm})
        .eq('id', widget.record['id']);

    if (mounted) Navigator.pop(context);
  }

  Future<void> _checkOverlapAndSubmit() async {
    await Supabase.instance.client.from('loaner_records').update({
      'customer_name': _nameController.text,
      'start_date': _selectedDateRange.start.toIso8601String().split('T')[0],
      'end_date': _selectedDateRange.end.toIso8601String().split('T')[0],
      'start_period': _startAmPm,
      'end_period': _endAmPm,
      'category': _category,
      'rental_condition': (widget.car['type'] == 'rental' || (widget.car['category']?.toString().contains('レンタ') ?? false)) ? _rentalCondition : null, // ★追加
    }).eq('id', widget.record['id']);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // ★ 修正：返却済みフラグを厳格に判定
    final bool isAlreadyReturned =
        widget.record['is_returned'].toString() == '1' ||
            widget.record['is_returned'].toString() == 'true';

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('✏️ ${widget.car['name']} 編集'),
          if (isAlreadyReturned)
            const Text('✅ 返却済み（完了）',
                style: TextStyle(fontSize: 12, color: Colors.green)),
        ],
      ),
      content: AbsorbPointer(
        absorbing: isAlreadyReturned, // 返却済みなら操作不能にする
        child: Opacity(
          opacity: isAlreadyReturned ? 0.6 : 1.0,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    final picked = await showDialog<List<DateTime?>>(
                      context: context,
                      builder: (ctx) => Dialog(
                        child: CalendarDatePicker2(
                          config: CalendarDatePicker2Config(
                            calendarType: CalendarDatePicker2Type.range,
                          ),
                          value: [
                            _selectedDateRange.start,
                            _selectedDateRange.end,
                          ],
                          onValueChanged: (dates) {
                            if (dates.length == 2) {
                              Navigator.pop(ctx, dates);
                            }
                          },
                        ),
                      ),
                    );
                    if (picked != null) {
                      setState(
                        () => _selectedDateRange = DateTimeRange(
                          start: picked[0]!,
                          end: picked[1]!,
                        ),
                      );
                    }
                  },
                  child: Text(
                    '${_selectedDateRange.start.month}/${_selectedDateRange.start.day} 〜 ${_selectedDateRange.end.month}/${_selectedDateRange.end.day}',
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _startAmPm,
                        items: ['AM', 'PM']
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text(v),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _startAmPm = v!),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _endAmPm,
                        items: ['AM', 'PM']
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text(v),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _endAmPm = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  items: _validCategories
                      .map(
                        (v) => DropdownMenuItem(value: v, child: Text(v)),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _category = v!),
                ),
                // ★レンタカーの場合のみ「有料・無料」の選択肢を表示
                Builder(builder: (context) {
                  final bool isRental = widget.car['type'] == 'rental' ||
                      (widget.car['category']?.toString().contains('レンタ') ??
                          false);
                  if (!isRental) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      const Text('💰 レンタカー条件',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      DropdownButtonFormField<String>(
                        initialValue: _rentalCondition,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Color(0xFFFFF9C4),
                        ),
                        items: ['有料', '無料']
                            .map((v) =>
                                DropdownMenuItem(value: v, child: Text(v)))
                            .toList(),
                        onChanged: (v) => setState(() => _rentalCondition = v!),
                      ),
                    ],
                  );
                }),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'お客様名'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (!isAlreadyReturned) ...[
          // ★ 修正：現在貸出中（または本日開始）の予約には「返却」ボタンを表示
          if (DateTime.parse(widget.record['start_date'])
              .isBefore(DateTime.now().add(const Duration(days: 1))))
            ElevatedButton(
              onPressed: () async {
                // 車両マスタと予約レコードの両方を返却済みに更新
                await _executeReturn(
                    context, widget.car, widget.car['parking'] ?? 'A');
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade700),
              child: const Text('🔙 返却する',
                  style: TextStyle(color: Colors.white)),
            ),
          if (widget.car['status'] != 1)
            ElevatedButton(
              onPressed: _startLoan,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600),
              child: const Text('🔑 貸出開始',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ElevatedButton(
            onPressed: _checkOverlapAndSubmit,
            child: const Text('保存'),
          ),
        ],
        if (isAlreadyReturned)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
      ],
    );
  }
}

// ============================================================================
// 5. 入庫・代車編集ダイアログ
// ============================================================================
Future<void> showEntryEditDialog(
  BuildContext context,
  Map<String, dynamic> record,
  String currentUserName,
) async {
  await showDialog(
    context: context,
    builder: (context) => EntryEditDialogWidget(
      record: record,
      currentUserName: currentUserName,
    ),
  );
}

class EntryEditDialogWidget extends StatefulWidget {
  final Map<String, dynamic> record;
  final String currentUserName;
  const EntryEditDialogWidget({
    super.key,
    required this.record,
    required this.currentUserName,
  });

  @override
  State<EntryEditDialogWidget> createState() => _EntryEditDialogWidgetState();
}

class _EntryEditDialogWidgetState extends State<EntryEditDialogWidget> {
  late TextEditingController _nameController;
  late TextEditingController _vehicleController;
  late TextEditingController _plateController;
  late TextEditingController _remarksController;

  late DateTimeRange _selectedDateRange;
  late String _entryAmPm;
  late String _exitAmPm;
  late String _category;
  bool _needLoaner = false;
  int? _selectedLoanerId;
  String _rentalCondition = '無料';
  bool _isLarge = false;

  List<Map<String, dynamic>> _allVehicles = [];
  List<Map<String, dynamic>> _activeRecords = [];
  List<Map<String, dynamic>> _availableVehicles = [];
  bool _isLoadingVehicles = false;
  Map<String, dynamic>? _currentLoanerRecord;

  final List<String> _categories = ['車検', '点検', '板金', '一般修理', 'その他'];

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _nameController = TextEditingController(text: r['customer_name']);
    _vehicleController = TextEditingController(text: r['vehicle_name']);
    _plateController = TextEditingController(text: r['plate_no']);
    _remarksController = TextEditingController(text: r['remarks']);

    _selectedDateRange = DateTimeRange(
      start: DateTime.parse(r['entry_date']),
      end: DateTime.parse(r['exit_date'] ?? r['entry_date']),
    );
    _entryAmPm = r['entry_period'] ?? 'AM';
    _exitAmPm = r['exit_period'] ?? 'PM';
    _category = r['category'] ?? '車検';
    final remarks = (r['remarks'] ?? '').toString();
    _isLarge = (r['is_large'] == true || r['is_large'] == 1) || remarks.contains('大型');

    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    setState(() => _isLoadingVehicles = true);
    
    // 1. 車両マスタと稼働中レコードを取得
    final vData = await Supabase.instance.client.from('master_vehicles').select();
    final rData = await Supabase.instance.client
        .from('loaner_records')
        .select()
        .eq('is_returned', 0);
    
    _allVehicles = List<Map<String, dynamic>>.from(vData);
    _activeRecords = List<Map<String, dynamic>>.from(rData);

    // 2. この入庫に紐づく代車予約があるか確認
    final loanerData = await Supabase.instance.client
        .from('loaner_records')
        .select()
        .eq('entry_id', widget.record['id'])
        .maybeSingle();

    if (loanerData != null) {
      _currentLoanerRecord = loanerData;
      _needLoaner = true;
      _selectedLoanerId = loanerData['loaner_id'];
      _rentalCondition = loanerData['rental_condition'] ?? '無料';
    }

    _filterAvailableVehicles();
  }

  void _filterAvailableVehicles() {
    List<Map<String, dynamic>> available = [];
    double newS = _dateToVal(_selectedDateRange.start, _entryAmPm);
    double newE = _dateToVal(_selectedDateRange.end, _exitAmPm);

    for (var car in _allVehicles) {
      if (car['status'] == 1) {
        // 現在貸出中の車でも、この予約自体がその車を使っているなら選択肢に残す
        if (_currentLoanerRecord == null || car['id'] != _currentLoanerRecord!['loaner_id']) {
          continue;
        }
      }
      
      bool overlap = false;
      for (var r in _activeRecords) {
        // 自分自身の現在の予約レコードは重複チェックから除外
        if (_currentLoanerRecord != null && r['id'] == _currentLoanerRecord!['id']) continue;
        
        if (r['loaner_id'] != car['id'] || r['category'] == '社用') continue;
        
        double rs = _dateToVal(DateTime.parse(r['start_date']), r['start_period'] ?? 'AM');
        double re = _dateToVal(DateTime.parse(r['end_date']), r['end_period'] ?? 'PM');
        
        if ((newS > rs ? newS : rs) <= (newE < re ? newE : re)) {
          overlap = true;
          break;
        }
      }
      if (!overlap) available.add(car);
    }
    
    setState(() {
      _availableVehicles = available;
      if (_selectedLoanerId != null && !_availableVehicles.any((c) => c['id'] == _selectedLoanerId)) {
        _selectedLoanerId = null;
      }
      _isLoadingVehicles = false;
    });
  }

  double _dateToVal(DateTime d, String ampm) =>
      d.difference(DateTime(2020, 1, 1)).inDays + (ampm == 'AM' ? 0.0 : 0.5);

  Future<void> _update() async {
    if (_nameController.text.isEmpty || _vehicleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('お客様名と車両名を入力してください')));
      return;
    }

    try {
      final String entryDateStr = _selectedDateRange.start.toIso8601String().split('T')[0];

      // 大型車両の1日1台バリデーション
      if (_isLarge) {
        final List<dynamic> existingLarge = await Supabase.instance.client
            .from('entry_records')
            .select('id')
            .eq('entry_date', entryDateStr)
            .eq('is_large', true)
            .neq('id', widget.record['id'])
            .limit(1);
        if (existingLarge.isNotEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('⚠️ この日は既に大型車両が予約されています（1日1台制限）'), backgroundColor: Colors.orange),
            );
          }
          return;
        }
      }

      // 1. 入庫レコードの更新
      await Supabase.instance.client.from('entry_records').update({
        'customer_name': _nameController.text,
        'vehicle_name': _vehicleController.text,
        'plate_no': _plateController.text,
        'entry_date': entryDateStr,
        'entry_period': _entryAmPm,
        'exit_date': _selectedDateRange.end.toIso8601String().split('T')[0],
        'exit_period': _exitAmPm,
        'category': _category,
        'remarks': (_isLarge && !_remarksController.text.contains('大型')) ? '[大型] ${_remarksController.text}' : _remarksController.text,
      }).eq('id', widget.record['id']);

      // 2. 代車予約の処理
      if (_needLoaner && _selectedLoanerId != null) {
        final selCar = _allVehicles.firstWhere((c) => c['id'] == _selectedLoanerId);
        final loanerData = {
          'loaner_id': _selectedLoanerId,
          'customer_name': _nameController.text,
          'start_date': _selectedDateRange.start.toIso8601String().split('T')[0],
          'end_date': _selectedDateRange.end.toIso8601String().split('T')[0],
          'start_period': _entryAmPm,
          'end_period': _exitAmPm,
          'category': _category,
          'rental_condition': (selCar['type'] == 'rental' || (selCar['category']?.toString().contains('レンタ') ?? false)) ? _rentalCondition : null,
          'entry_id': widget.record['id'],
        };

        if (_currentLoanerRecord != null) {
          // 既存の代車予約を更新
          await Supabase.instance.client.from('loaner_records').update(loanerData).eq('id', _currentLoanerRecord!['id']);
        } else {
          // 新規に代車予約を作成
          loanerData['is_returned'] = 0;
          loanerData['registered_by'] = widget.currentUserName;
          await Supabase.instance.client.from('loaner_records').insert(loanerData);
        }
      } else if (!_needLoaner && _currentLoanerRecord != null) {
        // 代車が不要になったので既存の予約を削除
        await Supabase.instance.client.from('loaner_records').delete().eq('id', _currentLoanerRecord!['id']);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Update Error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新中にエラーが発生しました: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.edit, color: Colors.blue),
          SizedBox(width: 8),
          Text('入庫・代車予約の編集'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('👤 基本情報', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'お客様名', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _vehicleController,
                      decoration: const InputDecoration(labelText: '対象車両', border: OutlineInputBorder(), prefixIcon: Icon(Icons.directions_car)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _plateController,
                      decoration: const InputDecoration(labelText: 'ナンバー', border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('📅 入庫期間', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final picked = await showDialog<List<DateTime?>>(
                    context: context,
                    builder: (ctx) => Dialog(
                      child: CalendarDatePicker2(
                        config: CalendarDatePicker2Config(calendarType: CalendarDatePicker2Type.range),
                        value: [_selectedDateRange.start, _selectedDateRange.end],
                        onValueChanged: (dates) {
                          if (dates.length == 2) Navigator.pop(ctx, dates);
                        },
                      ),
                    ),
                  );
                  if (picked != null) {
                    setState(() {
                      _selectedDateRange = DateTimeRange(start: picked[0]!, end: picked[1]!);
                      _filterAvailableVehicles();
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4)),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 18),
                      const SizedBox(width: 8),
                      Text('${_selectedDateRange.start.month}/${_selectedDateRange.start.day} 〜 ${_selectedDateRange.end.month}/${_selectedDateRange.end.day}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _entryAmPm,
                      decoration: const InputDecoration(labelText: '入庫時間'),
                      items: ['AM', 'PM'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                      onChanged: (v) => setState(() { _entryAmPm = v!; _filterAvailableVehicles(); }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _exitAmPm,
                      decoration: const InputDecoration(labelText: '納車時間'),
                      items: ['AM', 'PM'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                      onChanged: (v) => setState(() { _exitAmPm = v!; _filterAvailableVehicles(); }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: '入庫区分', border: OutlineInputBorder()),
                items: _categories.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: (v) => setState(() => _category = v!),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('🔵 大型車両として登録', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                subtitle: const Text('1日1台に制限されます', style: TextStyle(fontSize: 10)),
                value: _isLarge,
                activeColor: Colors.blue,
                onChanged: (val) => setState(() => _isLarge = val),
              ),
              const SizedBox(height: 16),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('🚗 代車の要・不要', style: TextStyle(fontWeight: FontWeight.bold)),
                  Switch(
                    value: _needLoaner,
                    onChanged: (val) {
                      setState(() => _needLoaner = val);
                      if (val) _filterAvailableVehicles();
                    },
                    activeThumbColor: Colors.blue.shade800,
                  ),
                ],
              ),
              if (_needLoaner) ...[
                const SizedBox(height: 8),
                if (_isLoadingVehicles)
                  const Center(child: CircularProgressIndicator())
                else if (_availableVehicles.isEmpty)
                  const Text('⚠️ 指定期間に空き代車がありません', style: TextStyle(color: Colors.red, fontSize: 12))
                else ...[
                  DropdownButtonFormField<int?>(
                    initialValue: _selectedLoanerId,
                    decoration: const InputDecoration(
                      labelText: '空き代車を選択',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Color(0xFFE3F2FD),
                    ),
                    items: _availableVehicles
                        .map((c) => DropdownMenuItem<int?>(value: c['id'], child: Text(c['name'])))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedLoanerId = v),
                  ),
                  const SizedBox(height: 8),
                  Builder(builder: (context) {
                    final selCar = _availableVehicles.firstWhere((c) => c['id'] == _selectedLoanerId, orElse: () => {});
                    final bool isRental = selCar['type'] == 'rental' || (selCar['category']?.toString().contains('レンタ') ?? false);
                    if (!isRental) return const SizedBox.shrink();
                    return DropdownButtonFormField<String>(
                      initialValue: _rentalCondition,
                      decoration: const InputDecoration(labelText: 'レンタカー条件', border: OutlineInputBorder()),
                      items: ['有料', '無料'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                      onChanged: (v) => setState(() => _rentalCondition = v!),
                    );
                  }),
                ],
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _remarksController,
                decoration: const InputDecoration(labelText: '備考', border: OutlineInputBorder()),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
        ElevatedButton(
          onPressed: _update,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade800, foregroundColor: Colors.white),
          child: const Text('変更を保存'),
        ),
      ],
    );
  }
}

// ============================================================================
// 6. 入庫受付（ワンストップ）ダイアログ
// ============================================================================
Future<bool> showEntryReceptionDialog({
  required BuildContext context,
  required String currentUserName,
  String? initialCustomerName,
  String? initialVehicleName,
  String? initialPlateNo,
  String? initialCategory,
  int? inspectionTargetId,
  DateTime? initialDate, // ★追加
}) async {
  bool isCompleted = false;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      return _EntryReceptionForm(
        currentUserName: currentUserName,
        initialCustomerName: initialCustomerName,
        initialVehicleName: initialVehicleName,
        initialPlateNo: initialPlateNo,
        initialCategory: initialCategory,
        inspectionTargetId: inspectionTargetId,
        initialDate: initialDate, // ★追加
        onCompleted: () {
          isCompleted = true;
          Navigator.of(dialogContext).pop();
        },
        onCancel: () => Navigator.of(dialogContext).pop(),
      );
    },
  );

  return isCompleted;
}

class _EntryReceptionForm extends StatefulWidget {
  final String currentUserName;
  final String? initialCustomerName;
  final String? initialVehicleName;
  final String? initialPlateNo;
  final String? initialCategory;
  final int? inspectionTargetId;
  final DateTime? initialDate; // ★追加
  final VoidCallback onCompleted;
  final VoidCallback onCancel;

  const _EntryReceptionForm({
    required this.currentUserName,
    this.initialCustomerName,
    this.initialVehicleName,
    this.initialPlateNo,
    this.initialCategory,
    this.inspectionTargetId,
    this.initialDate, // ★追加
    required this.onCompleted,
    required this.onCancel,
  });

  @override
  State<_EntryReceptionForm> createState() => _EntryReceptionFormState();
}

class _EntryReceptionFormState extends State<_EntryReceptionForm> {
  late final TextEditingController _customerNameCtrl;
  late final TextEditingController _vehicleNameCtrl;
  late final TextEditingController _plateNoCtrl;
  final _remarksCtrl = TextEditingController();

  List<DateTime?> _dates = [];
  String _entryPeriod = 'AM';
  String _exitPeriod = 'PM';
  late String _category;

  bool _needsLoaner = false;
  bool _isLoadingLoaners = false;
  List<Map<String, dynamic>> _availableLoaners = [];
  int? _selectedLoanerId;
  String _rentalCondition = '有料';
  bool _isLarge = false;
  int? _linkedInspectionTargetId; // ★追加: 紐付け用ID

  final List<String> _categories = ['車検', '点検', '板金', '一般修理', 'その他'];

  @override
  void initState() {
    super.initState();
    _customerNameCtrl = TextEditingController(text: widget.initialCustomerName);
    _vehicleNameCtrl = TextEditingController(text: widget.initialVehicleName);
    _linkedInspectionTargetId = widget.inspectionTargetId; // 初期化
    
    if (widget.initialDate != null) {
      _dates = [widget.initialDate, widget.initialDate];
    }
    
    // 登録番号の下4桁のみを抽出
    String plateNo = widget.initialPlateNo ?? '';
    final plateMatch = RegExp(r'\d{1,4}$').firstMatch(plateNo.trim());
    if (plateMatch != null) {
      plateNo = plateMatch.group(0)!;
    }
    _plateNoCtrl = TextEditingController(text: plateNo);
    
    // 下4桁入力時の自動検索リスナー
    _plateNoCtrl.addListener(_onPlateNoChanged);
    
    _category = widget.initialCategory ?? '車検';
  }

  @override
  void dispose() {
    _plateNoCtrl.removeListener(_onPlateNoChanged);
    _plateNoCtrl.dispose();
    _customerNameCtrl.dispose();
    _vehicleNameCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  void _onPlateNoChanged() {
    final text = _plateNoCtrl.text.trim();
    // 4桁の数字が入力されたときのみ検索を実行
    if (text.length == 4 && RegExp(r'^\d{4}$').hasMatch(text)) {
      // 以前の検索結果と同じであれば再検索しない（バグ回避）
      if (_lastSearchedDigits == text) return;
      _lastSearchedDigits = text;
      
      _searchInspectionTarget(text);
    } else {
      _lastSearchedDigits = null;
    }
  }

  String? _lastSearchedDigits; // ★追加：二重検索防止用

  Future<void> _searchInspectionTarget(String digits) async {
    try {
      final now = DateTime.now();
      final twoMonthsLater = now.add(const Duration(days: 60));
      
      // 車検リストから下4桁が一致し、かつ満了日が今日から2ヶ月以内のものを検索
      final List<dynamic> results = await Supabase.instance.client
          .from('inspection_targets')
          .select()
          .ilike('plate_no', '%$digits')
          .gte('inspection_due_date', now.toIso8601String().split('T')[0])
          .lte('inspection_due_date', twoMonthsLater.toIso8601String().split('T')[0]);

      if (results.isNotEmpty) {
        if (!mounted) return;

        // 検索結果をリストから選択させるポップアップを表示
        final Map<String, dynamic>? selected = await showDialog<Map<String, dynamic>>(
          context: context,
          barrierDismissible: false, // 確実に選択させる
          builder: (ctx) => AlertDialog(
            title: Text('ナンバー「$digits」の候補'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('車検リストから一致する車両が見つかりました。選択してください。', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: results.length,
                      separatorBuilder: (ctx, i) => const Divider(),
                      itemBuilder: (ctx, i) {
                        final item = results[i];
                        return ListTile(
                          title: Text(item['customer_name'] ?? '名前なし', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${item['vehicle_name'] ?? '車種不明'} (${_getLast4Digits(item['plate_no'])})\n満了日: ${_toJpDate(item['inspection_due_date'])}'),
                          isThreeLine: true,
                          onTap: () {
                            // 選択したアイテムを返してダイアログを閉じる
                            Navigator.of(ctx).pop(item);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop(); // 何も返さずに閉じる
                },
                child: const Text('該当なし（手入力する）'),
              ),
            ],
          ),
        );

        if (selected != null) {
          _applyTargetData(selected);
        }
      }
    } catch (e) {
      debugPrint('車検リスト検索エラー: $e');
    }
  }

  void _applyTargetData(Map<String, dynamic> target) {
    setState(() {
      _customerNameCtrl.text = target['customer_name'] ?? _customerNameCtrl.text;
      _vehicleNameCtrl.text = target['vehicle_name'] ?? _vehicleNameCtrl.text;
      _linkedInspectionTargetId = int.tryParse(target['id'].toString());
      _category = '車検'; // 車検リストからの紐付けなのでカテゴリを車検にセット
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('車検リストから情報を取得し、紐付けました')),
    );
  }

  Future<void> _fetchAvailableLoaners() async {
    if (_dates.isEmpty || _dates[0] == null) {
      setState(() => _availableLoaners = []);
      return;
    }

    final startDate = _dates[0]!;
    final endDate = _dates.length > 1 && _dates[1] != null ? _dates[1]! : startDate;

    setState(() {
      _isLoadingLoaners = true;
      _selectedLoanerId = null;
    });

    try {
      final startStr = startDate.toIso8601String().split('T')[0];
      final endStr = endDate.toIso8601String().split('T')[0];

      // 1. 全ての代車マスターを取得 (ステータスに関わらず予約可能かチェックするため)
      final allVehicles = await Supabase.instance.client
          .from('master_vehicles')
          .select();

      // 2. 指定期間に重複する予約レコードを取得
      final conflictingRecords = await Supabase.instance.client
          .from('loaner_records')
          .select('loaner_id')
          .eq('is_returned', 0) // 未返却のもの
          .lte('start_date', endStr)
          .gte('end_date', startStr);

      final conflictingIds = conflictingRecords
          .map((r) => r['loaner_id'] as int)
          .toSet();

      // 3. 重複していない車両のみを抽出
      final available = allVehicles.where((v) {
        final id = v['id'] as int;
        return !conflictingIds.contains(id);
      }).toList();

      setState(() {
        _availableLoaners = List<Map<String, dynamic>>.from(available);
      });
    } catch (e) {
      debugPrint('代車検索エラー: $e');
    } finally {
      setState(() => _isLoadingLoaners = false);
    }
  }

  Future<void> _selectDates() async {
    final values = await showCalendarDatePicker2Dialog(
      context: context,
      config: CalendarDatePicker2WithActionButtonsConfig(
        calendarType: CalendarDatePicker2Type.range,
        firstDate: DateTime.now().subtract(const Duration(days: 30)),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      ),
      dialogSize: const Size(325, 400),
      value: _dates,
    );

    if (values != null && values.isNotEmpty) {
      setState(() => _dates = values);
      if (_needsLoaner) _fetchAvailableLoaners();
    }
  }

  Future<void> _submit() async {
    if (_customerNameCtrl.text.isEmpty || _vehicleNameCtrl.text.isEmpty || _dates.isEmpty || _dates[0] == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('お客様名、対象車両、入庫日は必須です。', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
      return;
    }

    if (_needsLoaner && _selectedLoanerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('代車を選択してください。', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
      return;
    }

    final entryDateStr = _dates[0]!.toIso8601String().split('T')[0];
    final exitDateStr = (_dates.length > 1 && _dates[1] != null) ? _dates[1]!.toIso8601String().split('T')[0] : entryDateStr;

    try {
      // 1. 入庫レコードの作成
      final entryResult = await Supabase.instance.client.from('entry_records').insert({
        'customer_name': _customerNameCtrl.text,
        'vehicle_name': _vehicleNameCtrl.text,
        'plate_no': _plateNoCtrl.text,
        'category': _category,
        'entry_date': entryDateStr,
        'entry_period': _entryPeriod,
        'exit_date': exitDateStr,
        'exit_period': _exitPeriod,
        'remarks': (_isLarge && !_remarksCtrl.text.contains('大型')) ? '[大型] ${_remarksCtrl.text}' : _remarksCtrl.text,
        'registered_by': widget.currentUserName,
      }).select().single();

      final newEntryId = entryResult['id'];

      // ★追加: CRM連携（車検リストの更新）
      if (_linkedInspectionTargetId != null) {
        final now = DateTime.now().toIso8601String();
        await Supabase.instance.client
            .from('inspection_targets')
            .update({
              'status': '予約済',
              'reservation_date': entryDateStr,
              'reserved_by': widget.currentUserName,
              'reserved_at': now,
            })
            .eq('id', _linkedInspectionTargetId!);
      }

      if (_needsLoaner && _selectedLoanerId != null) {
         final selCar = _availableLoaners.firstWhere((c) => c['id'] == _selectedLoanerId, orElse: () => {});
        await Supabase.instance.client.from('loaner_records').insert({
          'loaner_id': _selectedLoanerId, // ★修正: 'vehicle_id' から 'loaner_id' に修正
          'customer_name': _customerNameCtrl.text,
          'start_date': entryDateStr,
          'start_period': _entryPeriod,
          'end_date': exitDateStr,
          'end_period': _exitPeriod,
          'category': _category,
          'rental_condition': (selCar['type'] == 'rental' || (selCar['category']?.toString().contains('レンタ') ?? false)) ? _rentalCondition : null,
          'registered_by': widget.currentUserName,
          'entry_id': newEntryId,
          'is_returned': 0, // ★追加: 初期状態は未返却
        });
      }

      widget.onCompleted();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('登録エラー: $e', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('📋 ワンストップ入庫受付', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('基本情報', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
              const Divider(),
              TextField(controller: _customerNameCtrl, decoration: const InputDecoration(labelText: 'お客様名 (必須)', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: TextField(controller: _vehicleNameCtrl, decoration: const InputDecoration(labelText: '対象車両 (必須)', border: OutlineInputBorder()))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _plateNoCtrl, decoration: const InputDecoration(labelText: 'ナンバー', border: OutlineInputBorder()))),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: '入庫区分', border: OutlineInputBorder()),
                items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (val) => setState(() => _category = val!),
              ),
              const SizedBox(height: 24),

              const Text('日程', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
              const Divider(),
              ListTile(
                title: const Text('入庫・納車期間を選択'),
                subtitle: Text(_dates.isEmpty ? '未選択' : '${_dates[0]?.toIso8601String().split('T')[0]} ～ ${_dates.length > 1 ? _dates[1]?.toIso8601String().split('T')[0] : ''}'),
                trailing: const Icon(Icons.calendar_month),
                shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4)),
                onTap: _selectDates,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: DropdownButtonFormField<String>(initialValue: _entryPeriod, decoration: const InputDecoration(labelText: '入庫時間'), items: ['AM', 'PM'].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(), onChanged: (v) => setState(() => _entryPeriod = v!))),
                  const SizedBox(width: 8),
                  Expanded(child: DropdownButtonFormField<String>(initialValue: _exitPeriod, decoration: const InputDecoration(labelText: '納車時間'), items: ['AM', 'PM'].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(), onChanged: (v) => setState(() => _exitPeriod = v!))),
                ],
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                title: const Text('🔵 大型車両として登録', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                subtitle: const Text('1日1台限定の枠を使用します', style: TextStyle(fontSize: 11)),
                value: _isLarge,
                activeColor: Colors.blue,
                contentPadding: EdgeInsets.zero,
                onChanged: (val) => setState(() => _isLarge = val ?? false),
              ),
              const SizedBox(height: 24),

              const Text('代車手配', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
              const Divider(),
              SwitchListTile(
                title: const Text('代車を利用する', style: TextStyle(fontWeight: FontWeight.bold)),
                value: _needsLoaner,
                activeThumbColor: Colors.orange,
                onChanged: (val) {
                  setState(() => _needsLoaner = val);
                  if (val && _dates.isNotEmpty) _fetchAvailableLoaners();
                },
              ),
              if (_needsLoaner) ...[
                if (_dates.isEmpty || _dates[0] == null)
                  const Text('※先にカレンダーで入庫期間を選択してください', style: TextStyle(color: Colors.red, fontSize: 12))
                else if (_isLoadingLoaners)
                  const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()))
                else if (_availableLoaners.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    color: Colors.red.shade50,
                    child: const Text('指定期間に空いている代車がありません！', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  )
                else ...[
                  DropdownButtonFormField<int>(
                    initialValue: _selectedLoanerId,
                    decoration: const InputDecoration(labelText: '貸出する代車を選択', border: OutlineInputBorder()),
                    items: _availableLoaners.map((v) => DropdownMenuItem<int>(
                      value: v['id'], 
                      child: Text(
                        '${v['name']} ${_toJpYear(v['model_year'])} ${v['color'] ?? ''} [${_getLast4Digits(v['plate_no'])}] ${_toJpDate(v['inspection_expiry'])}'
                        .trim()
                      )
                    )).toList(),
                    onChanged: (val) => setState(() => _selectedLoanerId = val),
                  ),
                   const SizedBox(height: 8),
                   Builder(builder: (context) {
                    final selCar = _availableLoaners.firstWhere((c) => c['id'] == _selectedLoanerId, orElse: () => {});
                    final bool isRental = selCar['type'] == 'rental' || (selCar['category']?.toString().contains('レンタ') ?? false);
                    if (!isRental) return const SizedBox.shrink();
                    return DropdownButtonFormField<String>(
                      initialValue: _rentalCondition,
                      decoration: const InputDecoration(labelText: 'レンタカー条件', border: OutlineInputBorder()),
                      items: ['有料', '無料'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                      onChanged: (v) => setState(() => _rentalCondition = v!),
                    );
                  }),
                ]
              ],
              const SizedBox(height: 24),

              TextField(controller: _remarksCtrl, decoration: const InputDecoration(labelText: '備考', border: OutlineInputBorder()), maxLines: 2),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(onPressed: widget.onCancel, child: const Text('キャンセル')),
        ElevatedButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check),
          label: const Text('予約確定', style: TextStyle(fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade800, foregroundColor: Colors.white),
        ),
      ],
    );
  }
}