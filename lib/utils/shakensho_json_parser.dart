
import 'dart:convert';

class ShakenshoJsonParser {
  /// 車検証閲覧アプリから出力されたJSONをパースして、各種項目をMapで返す
  static Map<String, String> parse(String jsonString) {
    try {
      final dynamic decoded = jsonDecode(jsonString);
      
      // JSONがリストでくる場合（複数の車両データを含む場合）と、単一オブジェクトの場合両方に対応
      final Map<String, dynamic> item = decoded is List ? decoded.first : decoded;
      
      return {
        'vehicleName': _findValue(item, ['車名', 'vehicleName', 'make']),
        'modelCode': _findValue(item, ['型式', 'model', 'vehicleModel']),
        'vin': _findValue(item, ['車台番号', 'chassisNumber', 'vin']),
        'length': _findValue(item, ['長さ', 'length']),
        'width': _findValue(item, ['幅', 'width']),
        'height': _findValue(item, ['高さ', 'height']),
        'ownerName': _findValue(item, ['所有者の氏名又は名称', 'ownerName', '使用者の氏名又は名称', 'userName']),
        'ownerAddress': _findValue(item, ['所有者の住所', 'ownerAddress', '使用者の住所', 'userAddress']),
        'useBaseAddress': _findValue(item, ['使用の本拠の位置', 'useBaseAddress', 'useBase']),
      };
    } catch (e) {
      return {};
    }
  }

  /// 複数のキー候補から値を探し出し、ネスト（階層化）された中身も探索する
  static String _findValue(Map<String, dynamic> map, List<String> keys) {
    // 1. 直下のキーを探す
    for (final key in keys) {
      if (map.containsKey(key) && map[key] != null) {
        return map[key].toString();
      }
    }
    
    // 2. 1つ下の階層 (オブジェクトの中にある場合) も探索する
    for (final value in map.values) {
       if (value is Map<String, dynamic>) {
           for (final key in keys) {
               if (value.containsKey(key) && value[key] != null) {
                   return value[key].toString();
               }
           }
       }
    }
    return '';
  }
}
