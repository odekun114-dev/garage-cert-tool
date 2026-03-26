import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'action_dialogs.dart';
import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';
import 'dart:convert';
import 'package:csv/csv.dart' as csv;
import 'package:charset_converter/charset_converter.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:fl_chart/fl_chart.dart';

class InspectionListScreen extends StatefulWidget {
  const InspectionListScreen({super.key});

  @override
  State<InspectionListScreen> createState() => _InspectionListScreenState();
}

class _InspectionListScreenState extends State<InspectionListScreen> {
  bool _isLoading = true;
  bool _isAdmin = false;
  String? _currentUserName;
  List<Map<String, dynamic>> _targets = [];
  List<Map<String, dynamic>> _allStaff = [];
  String? _selectedStaffName;
  DateTime _selectedMonth = DateTime.now();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isChartVisible = false;
  bool _isListView = false; // 表示モード切り替え用

  String _convertJapaneseDateToIso(String japaneseDate) {
    final cleanDate = japaneseDate.replaceAll(RegExp(r'\s+'), '');
    final match = RegExp(r'^([RHS])(\d+)\.(\d+)\.(\d+)$').firstMatch(cleanDate);

    if (match == null) return japaneseDate;

    final era = match.group(1);
    int year = int.parse(match.group(2)!);
    final month = match.group(3)!.padLeft(2, '0');
    final day = match.group(4)!.padLeft(2, '0');

    if (era == 'R') {
      year += 2018;
    } else if (era == 'H')
      year += 1988;
    else if (era == 'S')
      year += 1925;

    return '$year-$month-$day';
  }

  String _convertToJapaneseDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      int year = date.year;
      String era = '';
      int jpYear = 0;

      if (year >= 2019) {
        era = 'R';
        jpYear = year - 2018;
      } else if (year >= 1989) {
        era = 'H';
        jpYear = year - 1988;
      } else {
        era = 'S';
        jpYear = year - 1925;
      }
      return '$era$jpYear.${date.month}.${date.day}';
    } catch (e) {
      return isoDate;
    }
  }

  @override
  void initState() {
    super.initState();
    _initAuthAndFetch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initAuthAndFetch() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final profile = await Supabase.instance.client
        .from('profiles')
        .select('role, full_name')
        .eq('id', user.id)
        .single();

    setState(() {
      _isAdmin = profile['role'] == 'admin';
      _currentUserName = profile['full_name'];
      if (!_isAdmin) {
        _selectedStaffName = _currentUserName;
      }
    });

    if (_isAdmin) {
      await _fetchAllStaff();
    }

    await _fetchTargets();
  }

  Future<void> _fetchAllStaff() async {
    final activeStaffResponse = await Supabase.instance.client
        .from('inspection_targets')
        .select('assigned_staff_id');
    
    final List<dynamic> rawList = activeStaffResponse as List;
    final Set<String> activeStaffNames = rawList
        .map((item) => item['assigned_staff_id']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();

    final List<String> sortedNames = activeStaffNames.toList()..sort();

    setState(() {
      _allStaff = sortedNames.map((name) => {'full_name': name}).toList();
    });
  }

  Future<void> _fetchTargets() async {
    setState(() => _isLoading = true);
    try {
      final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);

      var query = Supabase.instance.client
          .from('inspection_targets')
          .select()
          .gte('inspection_due_date', firstDay.toIso8601String())
          .lte('inspection_due_date', lastDay.toIso8601String());

      if (!_isAdmin) {
        query = query.or('assigned_staff_id.eq.${_currentUserName!},reserved_by.eq.${_currentUserName!}');
      } else if (_selectedStaffName != null && _selectedStaffName != 'すべて') {
        query = query.or('assigned_staff_id.eq.${_selectedStaffName!},reserved_by.eq.${_selectedStaffName!}');
      }

      if (_searchQuery.isNotEmpty) {
        query = query.or('customer_name.ilike.%$_searchQuery%,plate_no.ilike.%$_searchQuery%');
      }

      final data = await query.order('inspection_due_date', ascending: true).order('customer_name', ascending: true);
      setState(() {
        _targets = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Fetch error: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _importPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );

    if (result == null) return;

    setState(() => _isLoading = true);

    try {
      final file = result.files.single;
      final List<int> bytes;
      
      if (kIsWeb) {
        if (file.bytes == null) throw 'ファイルデータの取得に失敗しました（Web）';
        bytes = file.bytes!;
      } else {
        if (file.path == null) throw 'ファイルパスの取得に失敗しました';
        bytes = await io.File(file.path!).readAsBytes();
      }

      final apiKey = dotenv.env['GEMINI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty || apiKey == 'your_api_key_here') {
        throw 'Gemini APIキーが設定されていません。.envファイルを確認してください。';
      }

      final model = GenerativeModel(
        model: 'gemini-2.0-flash',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
        ),
      );

      const prompt = '''
あなたは高度なデータ抽出アシスタントです。以下の厳格なルールに従ってPDFから情報を抽出してください：

【最重要ルール】
1. AIの推論や一般的な通説だけで回答せず、必ずPDF内の一次ソースをベースに情報を精査すること。
2. 誤った情報をもっともらしく回答する（ハルシネーション）することを厳禁とする。
3. 不確かな場合は、不明であると明記（nullを返す）すること。
4. 使用する技術スタックにおいて、常に最新の安定板および公式が推奨するベストプラクティスを優先すること。

以下の車検ターゲットリスト（PDF）から、各車両の情報を抽出してJSON形式のリストで出力してください。

出力フォーマット（JSON）:
[
  {
    "customer_name": "お客様名",
    "vehicle_name": "車種名",
    "plate_no": "ナンバープレート（例：浜松 500 あ 1234）",
    "inspection_due_date": "車検満了日（PDF内の「満期日」という項目から抽出してください。YYYY-MM-DD形式）",
    "assigned_staff_id": "担当者名（PDF内の「担当」「担当者」「(担当)」などの横にある名前を抽出してください）",
    "address": "住所",
    "phone_number": "電話番号",
    "fax_number": "FAX番号",
    "mobile_phone": "携帯番号",
    "model_code": "型式",
    "vin": "車台番号",
    "classification_no": "類別番号",
    "first_registration_date": "初度登録年月（YYYY-MM-DD形式。日は01としてください。例：2021-03-01）",
    "registration_date": "登録年月日（PDF内の「登録年月日」項目。H20. 3.27 のようにスペースが含まれる場合も確実に抽出してYYYY-MM-DD形式に変換してください）",
    "last_inspection_date": "前回点検日（YYYY-MM-DD形式）",
    "last_shaken_date": "前回車検日（YYYY-MM-DD形式）",
    "last_inspection_type": "前回点検区分",
    "total_expenses": "諸費用合計（数値。不明な場合は0）",
    "liability_insurance": "自賠責（数値。不明な場合は0）",
    "weight_tax": "重量税（数値。不明な場合は0）",
    "application_fee": "申請費用（数値。不明な場合は0）",
    "consumption_tax": "消費税（数値。不明な場合は0）"
  }
]

注意事項:
1. 日付項目（H20. 3.27 など）にスペースが含まれている場合は、スペースを無視して正しく日付として解釈してください。
2. 日付項目に日付以外の文字列（「AFリース」など）を絶対に含めないでください。
3. 日付は必ず和暦（R, H, S）を西暦（YYYY-MM-DD）に変換して抽出してください。
4. 日付が読み取れない、または日付として不適切な文字列しかない場合は、nullを返してください。
5. 初度登録年月などで「日」が不明な場合は「01」として、必ずYYYY-MM-DD形式にしてください。
6. 金額（数値）はカンマを除いた数値のみを抽出してください。
7. JSON以外のテキストは出力しないでください。
''';

      final content = [
        Content.multi([
          TextPart(prompt),
          DataPart('application/pdf', Uint8List.fromList(bytes)),
        ]),
      ];

      final response = await model.generateContent(content);
      final responseText = response.text;

      if (responseText == null || responseText.isEmpty) {
        throw 'Geminiからの応答が空でした。';
      }

      final List<dynamic> decodedJson = json.decode(responseText);
      final List<Map<String, dynamic>> extractedTargets = 
          decodedJson.map((item) => Map<String, dynamic>.from(item)).toList();

      if (extractedTargets.isEmpty) {
        _showSnackBar('データが検出されませんでした。', isError: true);
        setState(() => _isLoading = false);
        return;
      }

      final List<Map<String, dynamic>> uniqueTargets = [];
      final Set<String> seenPlates = {};

      for (var target in extractedTargets) {
        if (target['inspection_due_date'] == null || 
            target['inspection_due_date'] == "null") {
          continue;
        }

        if (!seenPlates.contains(target['plate_no'])) {
          seenPlates.add(target['plate_no']);
          final Map<String, dynamic> sanitizedTarget = target.map((key, value) {
            if (value == "null" || value == "NULL") return MapEntry(key, null);
            return MapEntry(key, value);
          });

          uniqueTargets.add({
            ...sanitizedTarget,
            'status': '未対応',
          });
        }
      }

      final existingRecords = await Supabase.instance.client
          .from('inspection_targets')
          .select('plate_no');
      final Set<String> existingPlates = existingRecords
          .map((row) => row['plate_no'].toString())
          .toSet();
      
      uniqueTargets.removeWhere(
        (target) => existingPlates.contains(target['plate_no']),
      );

      if (uniqueTargets.isEmpty) {
        _showSnackBar('追加する新規データはありません（すべて登録済み）');
        setState(() => _isLoading = false);
        return;
      }

      await Supabase.instance.client
          .from('inspection_targets')
          .insert(uniqueTargets);

      _showSnackBar('Geminiにより${uniqueTargets.length}件の新規データをインポートしました');
      if (_isAdmin) await _fetchAllStaff();
      _fetchTargets();
    } catch (e) {
      _showSnackBar('エラー: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _importCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );

    if (result == null) return;

    setState(() => _isLoading = true);

    try {
      final file = result.files.single;
      if (file.bytes == null) throw 'ファイルデータの取得に失敗しました';

      String csvString;
      try {
        csvString = await CharsetConverter.decode('Shift_JIS', file.bytes!);
      } catch (e) {
        csvString = utf8.decode(file.bytes!, allowMalformed: true);
      }

      final List<List<dynamic>> csvData = const csv.CsvToListConverter(
        shouldParseNumbers: false,
      ).convert(csvString);

      if (csvData.isEmpty) throw 'CSVデータが空です';

      final List<Map<String, dynamic>> extractedTargets = [];
      const int colCustomerName = 0;
      const int colVehicleName = 1;
      const int colPlateNo = 2;
      const int colDueDate = 3;
      const int colStaffName = 4;

      for (int i = 1; i < csvData.length; i++) {
        final row = csvData[i];
        if (row.length <= 4) continue;

        final customerName = row[colCustomerName].toString().trim();
        final vehicleName = row[colVehicleName].toString().trim();
        final plateNo = row[colPlateNo].toString().trim();
        final dueDateRaw = row[colDueDate].toString().trim();
        final staffName = row[colStaffName].toString().trim();

        if (customerName.isNotEmpty && plateNo.isNotEmpty && dueDateRaw.isNotEmpty) {
          extractedTargets.add({
            'customer_name': customerName,
            'vehicle_name': vehicleName.isNotEmpty ? vehicleName : '不明',
            'plate_no': plateNo,
            'inspection_due_date': _convertJapaneseDateToIso(dueDateRaw), 
            'status': '未対応',
            'assigned_staff_id': staffName.isNotEmpty ? staffName : '不明',
          });
        }
      }

      final List<Map<String, dynamic>> uniqueTargets = [];
      final Set<String> seenPlates = {};

      for (var target in extractedTargets) {
        if (!seenPlates.contains(target['plate_no'])) {
          seenPlates.add(target['plate_no']);
          uniqueTargets.add(target);
        }
      }

      final existingRecords = await Supabase.instance.client
          .from('inspection_targets')
          .select('plate_no');
      final Set<String> existingPlates = existingRecords
          .map((row) => row['plate_no'].toString())
          .toSet();
      uniqueTargets.removeWhere(
        (target) => existingPlates.contains(target['plate_no']),
      );

      if (uniqueTargets.isEmpty) {
        _showSnackBar('追加する新規データはありません（すべて登録済み）');
        setState(() => _isLoading = false);
        return;
      }

      await Supabase.instance.client.from('inspection_targets').insert(uniqueTargets);
      _showSnackBar('CSVから${uniqueTargets.length}件の新規データをインポートしました');
      _fetchTargets();
    } catch (e) {
      _showSnackBar('CSVエラー: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _deleteTarget(dynamic id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除の確認'),
        content: const Text('この車検ターゲットを削除してもよろしいですか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await Supabase.instance.client.from('inspection_targets').delete().eq('id', id);
      _showSnackBar('削除しました');
      _fetchTargets();
    } catch (e) {
      _showSnackBar('削除エラー: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('車検リスト', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_isListView ? Icons.grid_view : Icons.view_headline),
            onPressed: () => setState(() => _isListView = !_isListView),
            tooltip: _isListView ? 'カード表示に切替' : '一行表示に切替',
          ),
          if (_isAdmin) ...[
            IconButton(icon: const Icon(Icons.grid_on, color: Colors.green), onPressed: _importCsv, tooltip: 'CSV読み込み'),
            IconButton(icon: const Icon(Icons.picture_as_pdf, color: Colors.red), onPressed: _importPdf, tooltip: 'PDF読み込み'),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildCollapsibleSummary()),
                SliverToBoxAdapter(child: _buildMonthPicker()),
                SliverToBoxAdapter(child: _buildSearchBox()),
                if (_isAdmin) SliverToBoxAdapter(child: _buildStaffFilter()),
                _targets.isEmpty
                    ? const SliverFillRemaining(child: Center(child: Text('対象の車検予定はありません')))
                    : SliverPadding(
                        padding: const EdgeInsets.only(bottom: 20),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _isListView ? _buildCompactRow(_targets[index]) : _buildTargetCard(_targets[index]),
                            childCount: _targets.length,
                          ),
                        ),
                      ),
              ],
            ),
    );
  }

  Widget _buildCollapsibleSummary() {
    if (_targets.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _isChartVisible = !_isChartVisible),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: Colors.blue.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_isChartVisible ? Icons.expand_less : Icons.expand_more, color: Colors.blue.shade800, size: 20),
                const SizedBox(width: 8),
                Text('達成率・統計を確認', style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          ),
        ),
        if (_isChartVisible) _buildSummaryChart(),
      ],
    );
  }

  Widget _buildSummaryChart() {
    if (_targets.isEmpty) return const SizedBox.shrink();
    final reservedCount = _targets.where((t) => t['status'] == '予約済').length;
    final otherCount = _targets.where((t) => t['status'] == '他社実施').length;
    final waitingCount = _targets.where((t) => t['status'] == '連絡待ち').length;
    final unreachableCount = _targets.where((t) => t['status'] == '連絡取れない').length;
    final total = _targets.length;
    final pendingCount = total - reservedCount - otherCount - waitingCount - unreachableCount;
    final reservedRate = total > 0 ? (reservedCount / total * 100).toStringAsFixed(1) : '0';

    return Container(
      height: 140,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: PieChart(
              PieChartData(
                sectionsSpace: 0,
                centerSpaceRadius: 25,
                sections: [
                  PieChartSectionData(color: Colors.blue.shade400, value: reservedCount.toDouble(), title: '', radius: 15),
                  PieChartSectionData(color: Colors.orange.shade400, value: otherCount.toDouble(), title: '', radius: 15),
                  PieChartSectionData(color: Colors.amber.shade400, value: waitingCount.toDouble(), title: '', radius: 15),
                  PieChartSectionData(color: Colors.red.shade300, value: unreachableCount.toDouble(), title: '', radius: 15),
                  PieChartSectionData(color: Colors.grey.shade200, value: pendingCount.toDouble(), title: '', radius: 15),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('達成率: $reservedRate%', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _chartLegend(Colors.blue.shade400, '予約済:$reservedCount'),
                    _chartLegend(Colors.orange.shade400, '他社:$otherCount'),
                    _chartLegend(Colors.amber.shade400, '待機:$waitingCount'),
                    _chartLegend(Colors.red.shade300, '不能:$unreachableCount'),
                  ],
                ),
                const SizedBox(height: 4),
                _chartLegend(Colors.grey.shade400, '未対応: $pendingCount / 合計: $total'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartLegend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
      ],
    );
  }

  Widget _buildCompactRow(Map<String, dynamic> target) {
    final dueDateStr = target['inspection_due_date'];
    DateTime? dueDate;
    if (dueDateStr != null) {
      try {
        dueDate = DateTime.parse(dueDateStr);
      } catch (e) {
        dueDate = null;
      }
    }
    final isUrgent = dueDate != null && dueDate.isBefore(DateTime.now().add(const Duration(days: 30)));
    final String status = target['status'] ?? '未対応';
    final bool isReserved = status == '予約済';
    final bool isOther = status == '他社実施';
    final bool isWaiting = status == '連絡待ち';
    final bool isUnreachable = status == '連絡取れない';

    Color rowBg = Colors.white;
    if (isReserved) rowBg = Colors.blue.shade50;
    else if (isOther) rowBg = Colors.orange.shade50;
    else if (isWaiting) rowBg = Colors.amber.shade50;
    else if (isUnreachable) rowBg = Colors.red.shade50;

    return Container(
      decoration: BoxDecoration(color: rowBg, border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.5))),
      child: InkWell(
        onTap: () => _showDetailDialog(target),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: isReserved ? Colors.blue : (isOther ? Colors.orange : (isWaiting ? Colors.amber : (isUnreachable ? Colors.red : Colors.grey.shade300))),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(target['customer_name'] ?? '-', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${target['vehicle_name'] ?? '-'} (${target['plate_no'] ?? '-'})', style: const TextStyle(fontSize: 10, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(target['assigned_staff_id'] ?? '-', style: const TextStyle(fontSize: 10, color: Colors.blueGrey), textAlign: TextAlign.center, maxLines: 1),
              ),
              SizedBox(
                width: 65,
                child: Text(
                  target['inspection_due_date'] != null ? _convertToJapaneseDate(target['inspection_due_date']) : '-',
                  style: TextStyle(fontSize: 10, fontWeight: isUrgent ? FontWeight.bold : FontWeight.normal, color: isUrgent ? Colors.red : Colors.black),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTargetCard(Map<String, dynamic> target) {
    final dueDateStr = target['inspection_due_date'];
    DateTime? dueDate;
    if (dueDateStr != null) {
      try {
        dueDate = DateTime.parse(dueDateStr);
      } catch (e) {
        dueDate = null;
      }
    }
    final isUrgent = dueDate != null && dueDate.isBefore(DateTime.now().add(const Duration(days: 30)));
    final String status = target['status'] ?? '未対応';
    final bool isReserved = status == '予約済';
    final bool isOther = status == '他社実施';
    final bool isWaiting = status == '連絡待ち';
    final bool isUnreachable = status == '連絡取れない';

    Color cardBg = Colors.white;
    Color borderColor = Colors.grey.shade300;
    if (isReserved) {
      cardBg = Colors.blue.shade50;
      borderColor = Colors.blue.shade200;
    } else if (isOther) {
      cardBg = Colors.orange.shade50;
      borderColor = Colors.orange.shade200;
    } else if (isWaiting) {
      cardBg = Colors.amber.shade50;
      borderColor = Colors.amber.shade200;
    } else if (isUnreachable) {
      cardBg = Colors.red.shade50;
      borderColor = Colors.red.shade200;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      color: cardBg,
      shape: RoundedRectangleBorder(side: BorderSide(color: borderColor), borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: () => _showDetailDialog(target),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(target['customer_name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            if (status != '未対応')
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: _StatusBadge(label: status, color: isReserved ? Colors.blue : (isOther ? Colors.orange : (isWaiting ? Colors.amber : Colors.red))),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.directions_car, size: 12, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(child: Text('${target['vehicle_name'] ?? '-'} (${target['plate_no'] ?? '-'})', style: const TextStyle(fontSize: 12, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(target['inspection_due_date'] != null ? _convertToJapaneseDate(target['inspection_due_date']) : '-', style: TextStyle(fontSize: 13, fontWeight: isUrgent ? FontWeight.bold : FontWeight.normal, color: isUrgent ? Colors.red : Colors.black)),
                      const Text('車検満了', style: TextStyle(fontSize: 9, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, thickness: 0.5)),
              Row(
                children: [
                  const Icon(Icons.badge, size: 14, color: Colors.blueGrey),
                  const SizedBox(width: 4),
                  Text('担当: ${target['assigned_staff_id'] ?? '-'}', style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                  const Spacer(),
                  if (isReserved && target['reservation_date'] != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(4)),
                      child: Text('予約: ${_convertToJapaneseDate(target['reservation_date'])}', style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold)),
                    ),
                  if (_isAdmin)
                    IconButton(icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20), onPressed: () => _deleteTarget(target['id']), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDetailDialog(Map<String, dynamic> target) async {
    final String status = target['status'] ?? '未対応';
    final bool isReserved = status == '予約済';
    final bool isOther = status == '他社実施';
    final bool isWaiting = status == '連絡待ち';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // ヘッダー
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    target['customer_name'] ?? '詳細情報',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            
            // メインコンテンツ
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (status != '未対応') ...[
                      _sectionHeader('現在のステータス'),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (isReserved ? Colors.blue : (isOther ? Colors.orange : (isWaiting ? Colors.amber : Colors.red))).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (isReserved ? Colors.blue : (isOther ? Colors.orange : (isWaiting ? Colors.amber : Colors.red))).withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            _StatusBadge(
                              label: status, 
                              color: isReserved ? Colors.blue : (isOther ? Colors.orange : (isWaiting ? Colors.amber : Colors.red))
                            ),
                            const SizedBox(width: 12),
                            if (isReserved)
                              Expanded(
                                child: Text(
                                  '予約者: ${target['reserved_by'] ?? '-'}\n予約日: ${target['reservation_date'] != null ? _convertToJapaneseDate(target['reservation_date']) : '-'}',
                                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    _sectionHeader('車両・基本情報'),
                    _modernDetailTile(Icons.directions_car, '車種名', target['vehicle_name']),
                    _modernDetailTile(Icons.pin, '登録番号', target['plate_no']),
                    _modernDetailTile(Icons.badge, '担当者', target['assigned_staff_id']),
                    _modernDetailTile(Icons.calendar_today, '車検満了日', 
                        target['inspection_due_date'] != null 
                        ? _convertToJapaneseDate(target['inspection_due_date']) 
                        : '-'),
                    
                    const SizedBox(height: 20),
                    _sectionHeader('連絡先'),
                    _modernDetailTile(Icons.home, '住所', target['address']),
                    _modernDetailTile(Icons.phone, '電話番号', target['phone_number']),
                    _modernDetailTile(Icons.smartphone, '携帯番号', target['mobile_phone']),
                    
                    const SizedBox(height: 20),
                    _sectionHeader('車両詳細'),
                    _modernDetailTile(Icons.settings, '型式', target['model_code']),
                    _modernDetailTile(Icons.numbers, '車台番号', target['vin']),
                    
                    const SizedBox(height: 20),
                    _sectionHeader('諸費用'),
                    _modernDetailTile(Icons.payments, '諸費用合計', _formatCurrency(target['total_expenses'])),
                    
                    const SizedBox(height: 20),
                    _sectionHeader('備考'),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Text(
                        target['remarks'] ?? '備考なし',
                        style: const TextStyle(fontSize: 13, color: Colors.black87),
                      ),
                    ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),

            // アクションエリア
            Container(
              padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (status == '未対応') ...[
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          final completed = await showEntryReceptionDialog(
                            context: context,
                            currentUserName: _currentUserName!,
                            initialCustomerName: target['customer_name'],
                            initialVehicleName: target['vehicle_name'],
                            initialPlateNo: target['plate_no'],
                            initialCategory: '車検',
                            inspectionTargetId: int.tryParse(target['id'].toString()),
                          );
                          if (completed) _fetchTargets();
                        },
                        icon: const Icon(Icons.login),
                        label: const Text('この車両の入庫受付をする', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('ステータスを更新', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _modernStatusButton(target, '予約済', Colors.blue, Icons.check_circle_outline),
                          const SizedBox(width: 8),
                          _modernStatusButton(target, '他社実施', Colors.orange, Icons.business_outlined),
                          const SizedBox(width: 8),
                          _modernStatusButton(target, '連絡待ち', Colors.amber, Icons.hourglass_empty),
                          const SizedBox(width: 8),
                          _modernStatusButton(target, '連絡取れない', Colors.red, Icons.phone_disabled),
                        ],
                      ),
                    ),
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final bool? confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('ステータスの取消'),
                              content: const Text('現在のステータスを解除して「未対応」に戻しますか？'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                  child: const Text('未対応に戻す'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            Navigator.pop(context);
                            _resetTargetStatus(target);
                          }
                        },
                        icon: const Icon(Icons.undo),
                        label: const Text('ステータスを解除して未対応に戻す', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modernDetailTile(IconData icon, String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: Colors.blue.shade700),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                Text(value?.toString() ?? '-', style: const TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _modernStatusButton(Map<String, dynamic> target, String newStatus, Color color, IconData icon) {
    return InkWell(
      onTap: () async {
        final bool? confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('$newStatusの登録'),
            content: Text('この車両を「$newStatus」としてマークしますか？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: color),
                child: Text(newStatus),
              ),
            ],
          ),
        );
        if (confirm == true) {
          Navigator.pop(context);
          _updateTargetStatus(target, newStatus);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(newStatus, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Future<void> _updateTargetStatus(Map<String, dynamic> target, String newStatus) async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.from('inspection_targets').update({'status': newStatus, 'remarks': '[$newStatus登録済み]'}).eq('id', target['id'].toString());
      if (newStatus == '予約済') {
        final List<Map<String, dynamic>> optionalUpdates = [{'reserved_by': _currentUserName}, {'reserved_at': DateTime.now().toIso8601String()}];
        for (var update in optionalUpdates) {
          try {
            await Supabase.instance.client.from('inspection_targets').update(update).eq('id', target['id'].toString());
          } catch (e) {
            debugPrint('⚠️ カラム更新スキップ: $e');
          }
        }
      }
      _showSnackBar('$newStatusとしてマークしました');
      _fetchTargets();
    } catch (e) {
      _showSnackBar('エラー: $e', isError: true);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _resetTargetStatus(Map<String, dynamic> target) async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.from('inspection_targets').update({'status': '未対応'}).eq('id', target['id'].toString());
      final List<Map<String, dynamic>> optionalClears = [{'reservation_date': null}, {'reserved_by': null}, {'reserved_at': null}];
      for (var update in optionalClears) {
        try {
          await Supabase.instance.client.from('inspection_targets').update(update).eq('id', target['id'].toString());
        } catch (e) {
          debugPrint('⚠️ カラムクリアスキップ: $e');
        }
      }
      _showSnackBar('未対応に戻しました');
      _fetchTargets();
    } catch (e) {
      _showSnackBar('エラー: $e', isError: true);
      setState(() => _isLoading = false);
    }
  }

  Widget _buildMonthPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () { setState(() => _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1)); _fetchTargets(); }),
          Text('${_selectedMonth.year}年${_selectedMonth.month}月', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () { setState(() => _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1)); _fetchTargets(); }),
        ],
      ),
    );
  }

  Widget _buildSearchBox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'お客様名または登録番号で検索',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 20), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); _fetchTargets(); }) : null,
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Colors.grey.shade300)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Colors.grey.shade200)),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
        onChanged: (val) { setState(() => _searchQuery = val); _fetchTargets(); },
      ),
    );
  }

  Widget _buildStaffFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Colors.grey.shade50,
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 20, color: Colors.blueGrey),
          const SizedBox(width: 8),
          const Text('担当者:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButton<String>(
              value: _selectedStaffName ?? 'すべて',
              isExpanded: true,
              underline: const SizedBox(),
              style: const TextStyle(color: Colors.black87, fontSize: 14),
              items: [
                const DropdownMenuItem(value: 'すべて', child: Text('すべて')),
                ..._allStaff.map((s) => DropdownMenuItem(value: s['full_name'] as String, child: Text(s['full_name'] as String))),
              ],
              onChanged: (val) { setState(() => _selectedStaffName = val); _fetchTargets(); },
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue)));
  }

  String _formatCurrency(dynamic value) {
    if (value == null) return '-';
    try {
      final amount = int.parse(value.toString());
      return '¥${amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
    } catch (e) { return value.toString(); }
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }
}
