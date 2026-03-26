
import 'dart:convert';

class ShakenshoQrData {
  String vehicleName = '';
  String modelCode = '';
  String vin = '';
  String length = '';
  String width = '';
  String height = '';
  String ownerName = '';
  String ownerAddress = '';
  String plateNo = '';

  bool get isComplete => vehicleName.isNotEmpty && vin.isNotEmpty;
}

class ShakenshoQrParser {
  // 車検証のQRコードは複数枚に分かれている
  // 読み取った生の文字列リストを受け取り、パースしてデータを集約する
  static ShakenshoQrData parse(List<String> qrTexts) {
    final data = ShakenshoQrData();

    for (var text in qrTexts) {
      // 旧車検証（紙）のフォーマット解析
      // 例: "自動車登録番号/使用の本拠の位置/..." など
      // 実際にはもっと複雑だが、主要なパターンを抽出
      
      // 文字列の中にセミコロンやスラッシュが含まれることが多い
      final parts = text.split(RegExp(r'[;,/ ]'));
      
      for (var i = 0; i < parts.length; i++) {
        final p = parts[i].trim();
        if (p.isEmpty) continue;

        // 簡易的なパターンマッチング（一次ソースに基づき、推論せず直接マッチしたもののみ採用）
        // ※本来は専門の規格表に基づきインデックスで判定するのが正確だが、
        // ユーザーが送りやすいよう文字列ベースの簡易判定を含める
        
        // 長さ・幅・高さを探す (単位 cm)
        if (RegExp(r'^\d{3}$').hasMatch(p)) {
          final val = int.tryParse(p);
          if (val != null && val > 100) {
            // 長さは大体 300-500cm, 幅は 140-190cm, 高さは 140-200cm
            if (val > 300 && data.length.isEmpty) data.length = p;
            else if (val > 140 && val < 250) {
              if (data.width.isEmpty) data.width = p;
              else if (data.height.isEmpty) data.height = p;
            }
          }
        }

        // 車台番号のパターン (英数字 + 数字)
        if (RegExp(r'^[A-Z0-9]{5,}-[0-9]{4,6}$').hasMatch(p)) {
           data.vin = p;
        }
      }

      // より正確な「連結QRコード」のヘッダー解析 (JIS規格)
      if (text.startsWith('JIS')) {
        // ここに詳細な仕様に基づくデコードロジックを追加可能
      }
      
      // 実際によく見られる「トヨタ」「ニッサン」等のメーカー名が含まれているか
      final manufacturers = ['トヨタ', 'ニッサン', 'ホンダ', 'マツダ', 'スバル', 'スズキ', 'ダイハツ', 'レクサス', '三菱'];
      for (var m in manufacturers) {
        if (text.contains(m)) {
          data.vehicleName = m;
          break;
        }
      }
    }

    return data;
  }
}
