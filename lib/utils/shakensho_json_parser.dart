
import 'dart:convert';

class ShakenshoJsonParser {
  /// 車検証閲覧アプリから出力されたJSONをパースして、各種項目をMapで返す
  static Map<String, String> parse(String jsonString) {
    try {
      final dynamic decoded = jsonDecode(jsonString);
      
      // JSONがリストでくる場合（複数の車両データを含む場合）と、単一オブジェクトの場合両方に対応
      final Map<String, dynamic> item = decoded is List ? decoded.first : decoded;
      
      // 電子車検証特有の "CertInfo" や "CarInfo" というキーで一段ネストされているケースを平坦化
      final Map<String, dynamic> searchTarget = {};
      searchTarget.addAll(item);
      item.forEach((key, value) {
        if (value is Map) {
          searchTarget.addAll(Map<String, dynamic>.from(value));
        }
      });
      
      // 住所が「大字等(Char)」と「番地(NumValue)」に分かれている場合があるため結合する
      String getAddress(String baseKey) {
        final charPart = _findValue(searchTarget, ['${baseKey}Char']);
        final numPart = _findValue(searchTarget, ['${baseKey}NumValue']);
        final fullStr = '$charPart$numPart'.trim();
        // 文字列が空だった場合や、"＊＊＊"（同上）などの場合はそのまま返すか元を探す
        return fullStr.replaceAll('＊＊＊', ''); 
      }

      String useBase = getAddress('Useheadqrter');
      if (useBase.isEmpty) {
        useBase = _findValue(searchTarget, ['使用の本拠の位置', 'useBaseAddress', 'useBase']);
      }

      String ownerName = _findValue(searchTarget, ['OwnernameHighLevelChar', 'OwnernameLowLevelChar', '所有者の氏名又は名称', 'ownerName']);
      String ownerAddress = getAddress('OwnerAddress');

      // 使用者が明記されている場合（"＊＊＊" でない場合）はそのまま使用
      final userName = _findValue(searchTarget, ['UsernameHighLevelChar', 'UsernameLowLevelChar']);
      if (userName.isNotEmpty && userName != '＊＊＊') {
        ownerName = userName;
      }
      final userAddress = getAddress('UserAddress');
      if (userAddress.isNotEmpty && userAddress != '＊＊＊') {
        ownerAddress = userAddress;
      }

      return {
        'vehicleName': _findValue(searchTarget, ['CarName', '車名', 'vehicleName', 'make']),
        'modelCode': _findValue(searchTarget, ['Model', '型式', 'model', 'vehicleModel']),
        'vin': _findValue(searchTarget, ['CarNo', '車台番号', 'chassisNumber', 'vin']),
        'length': _findValue(searchTarget, ['Length', '長さ', 'length']),
        'width': _findValue(searchTarget, ['Width', '幅', 'width']),
        'height': _findValue(searchTarget, ['Height', '高さ', 'height']),
        'ownerName': ownerName,
        'ownerAddress': ownerAddress,
        'useBaseAddress': useBase,
      };
    } catch (e) {
      return {};
    }
  }

  /// 複数のキー候補から値を探し出す
  static String _findValue(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      if (map.containsKey(key) && map[key] != null) {
        return map[key].toString();
      }
    }
    return '';
  }
}

