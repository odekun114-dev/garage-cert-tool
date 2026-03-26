import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';
import '../models/garage_models.dart';
import '../services/excel_service.dart';
import '../services/garage_draft_service.dart';
import '../utils/shakensho_qr_parser.dart';
import '../utils/shakensho_json_parser.dart';
import 'garage_editor_screen.dart';
import 'shakensho_scanner_screen.dart';
import 'garage_drafts_list_screen.dart';


class GarageCertificateScreen extends StatefulWidget {
  const GarageCertificateScreen({super.key});

  @override
  State<GarageCertificateScreen> createState() => _GarageCertificateScreenState();
}

class _GarageCertificateScreenState extends State<GarageCertificateScreen> {
  final _formKey = GlobalKey<FormState>();
  String _currentDraftId = const Uuid().v4();
  
  // 基本情報
  bool _isLightCar = false;
  final _addressMainController = TextEditingController();
  final _addressParkingController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _ownerAddressController = TextEditingController();
  final _ownerPhoneController = TextEditingController();
  final _policeStationController = TextEditingController();
  
  // 車両詳細
  final _vehicleNameController = TextEditingController();
  final _modelCodeController = TextEditingController();
  final _vinController = TextEditingController();
  final _lengthController = TextEditingController();
  final _widthController = TextEditingController();
  final _heightController = TextEditingController();
  
  // AI推定寸法用のコントローラー（エディタ連携用）
  final _roadWidthController = TextEditingController();
  final _parkingWidthController = TextEditingController();
  final _parkingDepthController = TextEditingController();

  Future<void> _generatePdf() async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansJPRegular();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('自動車保管場所証明申請書', style: pw.TextStyle(font: font, fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
              pw.Text('使用の本拠: ${_addressMainController.text}', style: pw.TextStyle(font: font)),
              pw.Text('保管場所: ${_addressParkingController.text}', style: pw.TextStyle(font: font)),
              pw.Text('所有者: ${_ownerNameController.text}', style: pw.TextStyle(font: font)),
              pw.Text('車両項目: ${_vehicleNameController.text} / ${_modelCodeController.text}', style: pw.TextStyle(font: font)),
              pw.SizedBox(height: 10),
              pw.Row(
                children: [
                   if (_roadWidthController.text.isNotEmpty)
                     pw.Text('前面道路幅: ${_roadWidthController.text} m  ', style: pw.TextStyle(font: font)),
                   if (_parkingWidthController.text.isNotEmpty)
                     pw.Text('駐車枠: ${_parkingWidthController.text} x ${_parkingDepthController.text} m', style: pw.TextStyle(font: font)),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Container(
                height: 400,
                width: double.infinity,
                decoration: pw.BoxDecoration(border: pw.Border.all()),
                child: pw.Center(child: pw.Text('[所在図・配置図エリア]\n※Excel出力をご利用ください', style: pw.TextStyle(font: font), textAlign: pw.TextAlign.center)),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: '車庫証明_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  Future<void> _exportToExcel() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );
      
      await ExcelService.generateGarageCertificate(
        isLightCar: _isLightCar,
        addressMain: _addressMainController.text,
        addressParking: _addressParkingController.text,
        ownerName: _ownerNameController.text,
        ownerAddress: _ownerAddressController.text,
        ownerPhone: _ownerPhoneController.text,
        vehicleName: _vehicleNameController.text,
        modelCode: _modelCodeController.text,
        vin: _vinController.text,
        length: _lengthController.text,
        width: _widthController.text,
        height: _heightController.text,
        policeStation: _policeStationController.text,
      );
      
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Excel書き出しエラー: $e')));
    }
  }

  // QRスキャン機能の実行
  Future<void> _startQRScan() async {
    final ShakenshoQrData? result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ShakenshoScannerScreen()),
    );

    if (result != null) {
      setState(() {
        if (result.vehicleName.isNotEmpty) _vehicleNameController.text = result.vehicleName;
        if (result.vin.isNotEmpty) _vinController.text = result.vin;
        if (result.length.isNotEmpty) _lengthController.text = result.length;
        if (result.width.isNotEmpty) _widthController.text = result.width;
        if (result.height.isNotEmpty) _heightController.text = result.height;
        if (result.ownerName.isNotEmpty) _ownerNameController.text = result.ownerName;
        if (result.ownerAddress.isNotEmpty) _ownerAddressController.text = result.ownerAddress;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('車検証情報を反映しました')));
    }
  }

  // 電子車検証データの読み込み (JSON)
  Future<void> _importJson() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final jsonString = utf8.decode(result.files.single.bytes!);
        final data = ShakenshoJsonParser.parse(jsonString);
        
        setState(() {
          if (data['vehicleName']?.isNotEmpty == true) _vehicleNameController.text = data['vehicleName']!;
          if (data['modelCode']?.isNotEmpty == true) _modelCodeController.text = data['modelCode']!;
          if (data['vin']?.isNotEmpty == true) _vinController.text = data['vin']!;
          if (data['length']?.isNotEmpty == true) _lengthController.text = data['length']!;
          if (data['width']?.isNotEmpty == true) _widthController.text = data['width']!;
          if (data['height']?.isNotEmpty == true) _heightController.text = data['height']!;
          if (data['ownerName']?.isNotEmpty == true) {
             _ownerNameController.text = data['ownerName']!;
          }
          if (data['ownerAddress']?.isNotEmpty == true) _ownerAddressController.text = data['ownerAddress']!;
          if (data['useBaseAddress']?.isNotEmpty == true) _addressMainController.text = data['useBaseAddress']!;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSONデータを一発反映しました！', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.green));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('読み込みエラー: $e')));
    }
  }

  void _showImportOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('車両情報の入力方法', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: const Icon(Icons.upload_file, color: Colors.blue, size: 30),
                title: const Text('電子車検証データ (JSON) を読込む', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('車検証閲覧アプリから出力したファイルを使って一瞬で入力します'),
                onTap: () {
                  Navigator.pop(ctx);
                  _importJson();
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.qr_code_scanner, color: Colors.green, size: 30),
                title: const Text('紙の車検証のQRをカメラで読む'),
                subtitle: const Text('※QRが細かいため、カメラのピント合わせが難しい場合があります'),
                onTap: () {
                  Navigator.pop(ctx);
                  _startQRScan();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      }
    );
  }


  // クラウドへの一時保存
  Future<void> _saveAsDraft() async {
    setState(() {}); // ローディング表示用

    final draft = GarageDraft(
      id: _currentDraftId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      createdBy: '', // 後ろで設定
      isLightCar: _isLightCar,
      addressMain: _addressMainController.text,
      addressParking: _addressParkingController.text,
      ownerName: _ownerNameController.text,
      ownerAddress: _ownerAddressController.text,
      ownerPhone: _ownerPhoneController.text,
      vehicleName: _vehicleNameController.text,
      modelCode: _modelCodeController.text,
      vin: _vinController.text,
      length: _lengthController.text,
      width: _widthController.text,
      height: _heightController.text,
      policeStation: _policeStationController.text,
      roadWidth: _roadWidthController.text,
      parkingWidth: _parkingWidthController.text,
      parkingDepth: _parkingDepthController.text,
    );

    try {
      await GarageDraftService.saveDraft(draft);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('クラウドに一時保存しました')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存に失敗しました: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // 保存データの読み込み
  Future<void> _loadDraft() async {
    final GarageDraft? selected = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const GarageDraftsListScreen()),
    );

    if (selected != null) {
      setState(() {
        _currentDraftId = selected.id;
        _isLightCar = selected.isLightCar;
        _addressMainController.text = selected.addressMain;
        _addressParkingController.text = selected.addressParking;
        _ownerNameController.text = selected.ownerName;
        _ownerAddressController.text = selected.ownerAddress;
        _ownerPhoneController.text = selected.ownerPhone;
        _vehicleNameController.text = selected.vehicleName;
        _modelCodeController.text = selected.modelCode;
        _vinController.text = selected.vin;
        _lengthController.text = selected.length;
        _widthController.text = selected.width;
        _heightController.text = selected.height;
        _policeStationController.text = selected.policeStation;
        _roadWidthController.text = selected.roadWidth;
        _parkingWidthController.text = selected.parkingWidth;
        _parkingDepthController.text = selected.parkingDepth;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('データを読み込みました')));
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('車庫証明作成', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal.shade50,
        actions: [
          IconButton(onPressed: _loadDraft, icon: const Icon(Icons.cloud_download, color: Colors.teal), tooltip: '保存データの読込'),
          IconButton(onPressed: _saveAsDraft, icon: const Icon(Icons.cloud_upload_outlined, color: Colors.teal), tooltip: '現在を一時保存'),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showImportOptions,
        backgroundColor: Colors.blue.shade700,
        label: const Text('車検証読込', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        icon: const Icon(Icons.drive_folder_upload, color: Colors.white),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 車種選択
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('普通車'), icon: Icon(Icons.directions_car)),
                  ButtonSegment(value: true, label: Text('軽自動車'), icon: Icon(Icons.minor_crash)),
                ],
                selected: {_isLightCar},
                onSelectionChanged: (val) => setState(() => _isLightCar = val.first),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: Colors.teal,
                  selectedForegroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              
              _buildSectionHeader('1. 基本情報'),
              TextFormField(
                controller: _policeStationController,
                decoration: const InputDecoration(labelText: '提出先警察署', border: OutlineInputBorder(), hintText: '○○ 警察署'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressMainController,
                decoration: const InputDecoration(labelText: '使用の本拠の位置', border: OutlineInputBorder(), hintText: '住民票記載の住所など'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressParkingController,
                decoration: const InputDecoration(labelText: '保管場所の位置', border: OutlineInputBorder(), hintText: '駐車場の住所'),
              ),
              
              _buildSectionHeader('2. 申請者/届出者 情報'),
              TextFormField(
                controller: _ownerNameController,
                decoration: const InputDecoration(labelText: '氏名', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ownerAddressController,
                decoration: const InputDecoration(labelText: '住所', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ownerPhoneController,
                decoration: const InputDecoration(labelText: '電話番号', border: OutlineInputBorder()),
                keyboardType: TextInputType.phone,
              ),

              _buildSectionHeader('3. 車両情報'),
              Row(
                children: [
                  Expanded(child: TextFormField(controller: _vehicleNameController, decoration: const InputDecoration(labelText: '車名', border: OutlineInputBorder(), hintText: 'トヨタ'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextFormField(controller: _modelCodeController, decoration: const InputDecoration(labelText: '型式', border: OutlineInputBorder()))),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _vinController, decoration: const InputDecoration(labelText: '車台番号', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: TextFormField(controller: _lengthController, decoration: const InputDecoration(labelText: '長さ(cm)', border: OutlineInputBorder()), keyboardType: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(child: TextFormField(controller: _widthController, decoration: const InputDecoration(labelText: '幅(cm)', border: OutlineInputBorder()), keyboardType: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(child: TextFormField(controller: _heightController, decoration: const InputDecoration(labelText: '高さ(cm)', border: OutlineInputBorder()), keyboardType: TextInputType.number)),
                ],
              ),

              _buildSectionHeader('4. 配置図・AI推定寸法'),
              SizedBox(
                width: double.infinity,
                height: 120,
                child: Card(
                  color: Colors.teal.shade50,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.teal.shade200)),
                  child: InkWell(
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GarageEditorScreen(initialAddress: _addressParkingController.text),
                        ),
                      );
                      if (result != null && result is List<DrawingElement>) {
                        for (var el in result) {
                          if (el.mode == DrawingMode.rectangle) {
                            if (el.estimatedWidthMeter != null) {
                              setState(() {
                                if (el.estimatedWidthMeter! > 4.0) {
                                  _roadWidthController.text = el.estimatedWidthMeter!.toStringAsFixed(1);
                                } else {
                                  _parkingWidthController.text = el.estimatedWidthMeter!.toStringAsFixed(1);
                                  _parkingDepthController.text = el.estimatedHeightMeter?.toStringAsFixed(1) ?? '';
                                }
                              });
                            }
                          }
                        }
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('図面寸法が反映されました')));
                      }
                    },
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.map_outlined, size: 32, color: Colors.teal),
                        SizedBox(height: 4),
                        Text('地図エディタを開く', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: TextFormField(controller: _roadWidthController, decoration: const InputDecoration(labelText: '前面道路幅(m)', border: OutlineInputBorder()))),
                  const SizedBox(width: 8),
                  Expanded(child: TextFormField(controller: _parkingWidthController, decoration: const InputDecoration(labelText: '駐車枠幅(m)', border: OutlineInputBorder()))),
                  const SizedBox(width: 8),
                  Expanded(child: TextFormField(controller: _parkingDepthController, decoration: const InputDecoration(labelText: '駐車枠奥行(m)', border: OutlineInputBorder()))),
                ],
              ),

              const SizedBox(height: 40),
              
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _generatePdf,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('PDFプレビュー'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.grey.shade200,
                        foregroundColor: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _exportToExcel,
                      icon: const Icon(Icons.table_view),
                      label: const Text('Excelで出力'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }
}


