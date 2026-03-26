import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ExcelService {
  static Future<void> generateGarageCertificate({
    required bool isLightCar,
    required String addressMain,
    required String addressParking,
    required String ownerName,
    required String ownerAddress,
    required String ownerPhone,
    required String vehicleName,
    required String modelCode,
    required String vin,
    required String length,
    required String width,
    required String height,
    required String policeStation,
  }) async {
    final String templatePath = isLightCar
        ? 'assets/templates/3-2hokanbasyotodoke0803.xlsx'
        : 'assets/templates/2-2syoumeisinsei0803.xlsx';

    // テンプレートの読み込み
    final ByteData data = await rootBundle.load(templatePath);
    final List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final Excel excel = Excel.decodeBytes(bytes);

    final String sheetName = excel.tables.keys.first;
    final Sheet? sheet = excel.tables[sheetName];

    if (sheet == null) return;

    final now = DateTime.now();

    if (!isLightCar) {
      // 普通車 (2-2syoumeisinsei0803.xlsx)
      // セル座標は inspect_excel.py の結果に基づく
      _setCellValue(sheet, 'B5', vehicleName);  // 車名 (A5ラベルの横)
      _setCellValue(sheet, 'N5', modelCode);    // 型式 (M5ラベルの横)
      _setCellValue(sheet, 'AA5', vin);         // 車台番号 (Z5ラベルの横)
      
      _setCellValue(sheet, 'AP7', length);      // 長さ
      _setCellValue(sheet, 'AP8', width);       // 幅
      _setCellValue(sheet, 'AP9', height);      // 高さ

      _setCellValue(sheet, 'A11', addressMain);    // 使用の本拠
      _setCellValue(sheet, 'A12', addressParking); // 保管場所

      _setCellValue(sheet, 'J15', policeStation);  // 警察署長

      // 申請者
      _setCellValue(sheet, 'AC16', ownerAddress);  // 住所
      _setCellValue(sheet, 'AC19', ownerName);     // 氏名
      _setCellValue(sheet, 'AU18', ownerPhone);    // 電話 (AM18の横あたり)

      // 日付
      _setCellValue(sheet, 'AN14', now.year.toString());
      _setCellValue(sheet, 'AT14', now.month.toString());
      _setCellValue(sheet, 'BB14', now.day.toString());
    } else {
      // 軽自動車 (3-2hokanbasyotodoke0803.xlsx)
      _setCellValue(sheet, 'B5', vehicleName);
      _setCellValue(sheet, 'N5', modelCode);
      _setCellValue(sheet, 'Z5', vin);

      _setCellValue(sheet, 'AM7', length);
      _setCellValue(sheet, 'AM8', width);
      _setCellValue(sheet, 'AM9', height);

      _setCellValue(sheet, 'A11', addressMain);
      _setCellValue(sheet, 'A12', addressParking);

      _setCellValue(sheet, 'I16', policeStation);

      // 届出者
      _setCellValue(sheet, 'Z17', ownerAddress);
      _setCellValue(sheet, 'Z20', ownerName);
      _setCellValue(sheet, 'AK19', ownerPhone);

      // 日付
      _setCellValue(sheet, 'AK15', now.year.toString());
      _setCellValue(sheet, 'AO15', now.month.toString());
      _setCellValue(sheet, 'AW15', now.day.toString());
    }

    // 保存と共有
    final List<int>? fileBytes = excel.save();
    if (fileBytes != null) {
      final String fileName = "車庫証明_${isLightCar ? '軽' : '普通'}_${now.millisecondsSinceEpoch}.xlsx";
      final directory = await getTemporaryDirectory();
      final File file = File('${directory.path}/$fileName');
      await file.writeAsBytes(fileBytes);
      
      // Share 経由でユーザーに渡す（モバイル/デスクトップ共通で使いやすい）
      await Share.shareXFiles([XFile(file.path)], text: '車庫証明Excelデータ');
    }
  }

  static void _setCellValue(Sheet sheet, String address, String value) {
    // excel package の cellAddress 変換
    // 列記号(A, B, ...)をインデックスに変換
    final int col = _columnToIndex(address.replaceAll(RegExp(r'[0-9]'), ''));
    final int row = int.parse(address.replaceAll(RegExp(r'[A-Z]'), '')) - 1;
    
    var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    cell.value = TextCellValue(value);
  }

  static int _columnToIndex(String column) {
    int index = 0;
    for (int i = 0; i < column.length; i++) {
      index *= 26;
      index += column.codeUnitAt(i) - 'A'.codeUnitAt(0) + 1;
    }
    return index - 1;
  }
}
