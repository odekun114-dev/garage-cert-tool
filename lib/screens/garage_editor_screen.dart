import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as ll;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import '../models/garage_models.dart';

// Mock AiVisionService since the original file is missing
class AiVisionService {
  Future<Map<String, dynamic>> analyzeGarageImage(dynamic bytes) async {
    return {};
  }
}

// Mock CoordinateUtils since the original file is missing
class CoordinateUtils {
  static List<ll.LatLng> convertAiBoxToLatLng(
      ll.LatLng center, double zoom, List<int> box, double width, double height) {
    // Return mock points (a small rectangle around the center)
    return [
      ll.LatLng(center.latitude - 0.0001, center.longitude - 0.0001),
      ll.LatLng(center.latitude + 0.0001, center.longitude - 0.0001),
      ll.LatLng(center.latitude + 0.0001, center.longitude + 0.0001),
      ll.LatLng(center.latitude - 0.0001, center.longitude + 0.0001),
    ];
  }
}

class GarageEditorScreen extends StatefulWidget {
  final String? initialAddress;
  const GarageEditorScreen({super.key, this.initialAddress});

  @override
  State<GarageEditorScreen> createState() => _GarageEditorScreenState();
}

class _GarageEditorScreenState extends State<GarageEditorScreen> {
  final fmap.MapController _mapController = fmap.MapController();
  // Assuming AiVisionService is defined elsewhere or will be defined.
  // For now, let's keep it as is, but it might need a mock or actual implementation.
  final AiVisionService _aiService = AiVisionService();

  ll.LatLng _center = const ll.LatLng(35.681236, 139.767125); // 東京駅
  bool _isLoading = false;
  final TextEditingController _addressController = TextEditingController();

  List<DrawingElement> _elements = [];
  DrawingMode _currentMode = DrawingMode.freehand;
  DrawingElement? _currentElement;
  
  // 編集用の状態
  int? _selectedElementIndex;
  int? _selectedPointIndex;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialAddress != null) {
      _addressController.text = widget.initialAddress!;
      _searchAddress();
    }
  }

  Future<void> _searchAddress() async {
    if (_addressController.text.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      String address = _addressController.text.trim();
      // 🚨 住所クレンジング
      address = address.replaceAllMapped(RegExp(r'[０-９]'), (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0xFEE0));
      address = address.replaceAll(RegExp(r'丁目|番地|番|号'), '-');
      address = address.replaceAll(RegExp(r'-+'), '-');
      address = address.replaceAll(RegExp(r'-$'), '');

      // 🚨 Yahoo! ジオコーダ API を使用（詳細な番地検索に強い）
      const String yahooAppId = 'dj00aiZpPThidXp6RGp6RjZpYyZzPWNvbnN1bWVyc2VjcmV0Jng9YmU-';
      // 2026年仕様: より詳細な結果を得るために al=7 (詳細レベル3) と ar=ge (それ以上) を指定
      final yahooUrl = Uri.parse('https://map.yahooapis.jp/geocode/V2/geoCoder'
          '?appid=$yahooAppId'
          '&query=${Uri.encodeComponent(address)}'
          '&output=json'
          '&results=1'
          '&al=7'
          '&ar=ge');

      try {
        final yahooResponse = await http.get(yahooUrl);
        debugPrint('Yahoo! Geocoder Response Status: ${yahooResponse.statusCode}');
        
        if (yahooResponse.statusCode == 200) {
          final data = json.decode(yahooResponse.body);
          if (data['Feature'] != null && data['Feature'].isNotEmpty) {
            final feature = data['Feature'][0];
            final geometry = feature['Geometry'];
            final coordinates = geometry['Coordinates']?.split(',');
            
            if (coordinates != null && coordinates.length == 2) {
              final lon = double.parse(coordinates[0]);
              final lat = double.parse(coordinates[1]);
              
              setState(() {
                _center = ll.LatLng(lat, lon);
                _mapController.move(_center, 18.0);
              });
              debugPrint('Yahoo! Geocoder Success: $lat, $lon (Address: ${feature['Name']})');
              return; // Yahooで成功したら終了
            }
          } else {
            debugPrint('Yahoo! Geocoder: No features found for "$address"');
          }
        } else {
          debugPrint('Yahoo! Geocoder Error: ${yahooResponse.statusCode} ${yahooResponse.body}');
        }
      } catch (e) {
        debugPrint('Yahoo! Geocoder Exception: $e');
        // Web版でのCORSエラーなどの場合はここに来る可能性があるため、GSI APIにフォールバック
      }

      // 🚨 国土地理院 (GSI) ジオコーディング API を使用（Webに強く、日本の詳細検索に対応）
      final gsiUrl = Uri.parse('https://msearch.gsi.go.jp/address-search/AddressSearch?q=${Uri.encodeComponent(address)}');
      try {
        final gsiResponse = await http.get(gsiUrl);
        debugPrint('GSI Geocoder Response Status: ${gsiResponse.statusCode}');
        if (gsiResponse.statusCode == 200) {
          final List<dynamic> data = json.decode(gsiResponse.body);
          if (data.isNotEmpty) {
            // 最も一致度の高い最初の結果を使用
            final firstResult = data[0];
            final geometry = firstResult['geometry'];
            final coordinates = geometry['coordinates']; // [lon, lat]
            if (coordinates != null && coordinates.length == 2) {
              final lon = coordinates[0].toDouble();
              final lat = coordinates[1].toDouble();
              setState(() {
                _center = ll.LatLng(lat, lon);
                _mapController.move(_center, 18.0);
              });
              debugPrint('GSI Geocoder Success: $lat, $lon (Address: ${firstResult['properties']['title']})');
              return; // GSIで成功したら終了
            }
          } else {
            debugPrint('GSI Geocoder: No results found for "$address"');
          }
        }
      } catch (e) {
        debugPrint('GSI Geocoder Exception: $e');
      }

      // 🚨 Yahoo! / GSI で失敗した場合の最終フォールバック（広域検索用の Nominatim）
      final query = Uri.encodeComponent(address);
      final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=5&countrycodes=jp&addressdetails=1');
      
      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'DaishaApp/1.0 (amonc@example.com)',
          'Accept-Language': 'ja'
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data.isNotEmpty) {
          final lat = double.parse(data[0]['lat']);
          final lon = double.parse(data[0]['lon']);
          setState(() {
            _center = ll.LatLng(lat, lon);
            _mapController.move(_center, 18.0);
          });
          debugPrint('Nominatim Success: $lat, $lon');
        } else {
          debugPrint('Nominatim: No results for "$address". Trying fallback...');
          // 🚨 さらに曖昧な検索を試みる
          final parts = address.split(RegExp(r'[市区町村]'));
          if (parts.length > 1) {
            final fallbackQuery = Uri.encodeComponent(parts[0] + address.substring(parts[0].length, parts[0].length + 1));
            final fallbackUrl = Uri.parse('https://nominatim.openstreetmap.org/search?q=$fallbackQuery&format=json&limit=1&countrycodes=jp');
            final fallbackResponse = await http.get(fallbackUrl, headers: {'User-Agent': 'DaishaApp/1.0'});
            final fallbackData = json.decode(fallbackResponse.body);
            if (fallbackData.isNotEmpty) {
              final lat = double.parse(fallbackData[0]['lat']);
              final lon = double.parse(fallbackData[0]['lon']);
              setState(() {
                _center = ll.LatLng(lat, lon);
                _mapController.move(_center, 15.0);
              });
              debugPrint('Nominatim Fallback Success: $lat, $lon');
              _showSnackBar('詳細な番地が見つからなかったため、付近を表示しています');
              return;
            }
          }
          debugPrint('Nominatim Fallback: No results found.');
          _showSnackBar('住所が見つかりませんでした。都道府県から入力してみてください。', isError: true);
        }
      } else {
        debugPrint('Nominatim Error: ${response.statusCode} ${response.body}');
        _showSnackBar('検索サーバーエラー', isError: true);
      }
    } catch (e) {
      debugPrint('Error searching address: $e');
      _showSnackBar('住所が見つかりませんでした: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _autoTraceWithAi() async {
    setState(() => _isLoading = true);
    try {
      _showSnackBar('AIによる自動トレースを開始します...');
      
      // AI解析の実行（2026年仕様：Gemini 2.0 Flash Vision を使用）
      // 本来は地図のキャプチャ画像を渡しますが、ここではデモ用のモックロジックを動作させます
      // final result = await _aiService.analyzeGarageImage(imageBytes);
      debugPrint('AI Service initialized: ${_aiService.runtimeType}');
      
      // 暫定的なモックデータ（AIからの応答を想定）
      final mockResult = {
        "elements": [
          {
            "label": "building",
            "box_2d": [400, 400, 600, 600],
            "estimated_width_m": 10.0,
            "estimated_height_m": 15.0
          },
          {
            "label": "road",
            "box_2d": [700, 100, 800, 900],
            "estimated_width_m": 6.0,
            "estimated_height_m": 50.0
          }
        ]
      };

      final size = MediaQuery.of(context).size;
      final screenWidth = size.width;
      final screenHeight = size.height - 200; // AppBarやツールバーを除いた高さ

      setState(() {
        for (var item in mockResult['elements'] as List) {
          final box = List<int>.from(item['box_2d']);
          final points = CoordinateUtils.convertAiBoxToLatLng(
            _mapController.camera.center,
            _mapController.camera.zoom,
            box,
            screenWidth,
            screenHeight,
          );

          _elements.add(DrawingElement(
            mode: DrawingMode.rectangle,
            points: points,
            estimatedWidthMeter: item['estimated_width_m'],
            estimatedHeightMeter: item['estimated_height_m'],
          ));
        }
      });

      _showSnackBar('AIトレースが完了しました。微調整を行ってください。');
    } catch (e) {
      _showSnackBar('AIトレースエラー: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.blue,
      ),
    );
  }

  ll.LatLng? _hoverLatLng;

  void _handleTap(ll.LatLng latLng) {
    if (_currentMode == DrawingMode.select) {
      // 既存の要素の点を選択
      for (int i = 0; i < _elements.length; i++) {
        for (int j = 0; j < _elements[i].points.length; j++) {
          final distance = const ll.Distance().as(ll.LengthUnit.Meter, _elements[i].points[j], latLng);
          // ズームレベルに応じてヒット判定距離を調整 (18以上なら1m以内)
          final threshold = _mapController.camera.zoom > 18 ? 0.5 : 2.0;
          if (distance < threshold) {
            setState(() {
              _selectedElementIndex = i;
              _selectedPointIndex = j;
              _showSnackBar('点を選択しました。ドラッグして移動できます。');
            });
            return;
          }
        }
      }
      setState(() {
        _selectedElementIndex = null;
        _selectedPointIndex = null;
      });
      return;
    }

    setState(() {
      switch (_currentMode) {
        case DrawingMode.freehand:
          if (_currentElement == null || _currentElement!.mode != DrawingMode.freehand) {
            _currentElement = DrawingElement(mode: DrawingMode.freehand, points: [latLng]);
          } else {
            _currentElement!.points.add(latLng);
          }
          break;
        case DrawingMode.rectangle:
          if (_currentElement == null) {
            _currentElement = DrawingElement(mode: DrawingMode.rectangle, points: [latLng]);
          } else if (_currentElement!.points.length == 1) {
            // 2点目：1点目と2点目から暫定的な長方形を作成
            final p1 = _currentElement!.points[0];
            final p2 = latLng;
            final south = math.min(p1.latitude, p2.latitude);
            final north = math.max(p1.latitude, p2.latitude);
            final west = math.min(p1.longitude, p2.longitude);
            final east = math.max(p1.longitude, p2.longitude);
            
            final pLeftTop = ll.LatLng(north, west);
            final pRightTop = ll.LatLng(north, east);
            final pLeftBottom = ll.LatLng(south, west);
            
            final width = const ll.Distance().as(ll.LengthUnit.Meter, pLeftTop, pRightTop);
            final height = const ll.Distance().as(ll.LengthUnit.Meter, pLeftTop, pLeftBottom);

            setState(() {
              _elements.add(DrawingElement(
                mode: DrawingMode.rectangle,
                points: [
                  ll.LatLng(south, west),
                  ll.LatLng(north, west),
                  ll.LatLng(north, east),
                  ll.LatLng(south, east),
                ],
                estimatedWidthMeter: width,
                estimatedHeightMeter: height,
              ));
              _currentElement = null;
              // 作成直後に選択状態にする（すぐに微調整できるように）
              _selectedElementIndex = _elements.length - 1;
              _showSnackBar('長方形を作成しました。角をドラッグして斜めに調整できます。');
            });
          }
          break;
        case DrawingMode.line:
          if (_currentElement == null) {
            _currentElement = DrawingElement(mode: DrawingMode.line, points: [latLng]);
          } else {
            _currentElement!.points.add(latLng);
            _elements.add(_currentElement!);
            _currentElement = null;
            _selectedElementIndex = _elements.length - 1;
          }
          break;
        case DrawingMode.polygon:
          if (_currentElement == null) {
            _currentElement = DrawingElement(mode: DrawingMode.polygon, points: [latLng]);
          } else {
            // 最初の点に近い場合は閉じる
            final distance = const ll.Distance().as(ll.LengthUnit.Meter, _currentElement!.points[0], latLng);
            if (distance < 1.0 && _currentElement!.points.length >= 3) {
              _elements.add(_currentElement!);
              _currentElement = null;
              _selectedElementIndex = _elements.length - 1;
            } else {
              _currentElement!.points.add(latLng);
            }
          }
          break;
        case DrawingMode.road:
          if (_currentElement == null) {
            _currentElement = DrawingElement(mode: DrawingMode.road, points: [latLng]);
          } else if (_currentElement!.points.length == 1) {
            // 2点目：長方形として確定
            final p1 = _currentElement!.points[0];
            final p2 = latLng;
            final south = math.min(p1.latitude, p2.latitude);
            final north = math.max(p1.latitude, p2.latitude);
            final west = math.min(p1.longitude, p2.longitude);
            final east = math.max(p1.longitude, p2.longitude);
            
            final pLeftTop = ll.LatLng(north, west);
            final pRightTop = ll.LatLng(north, east);
            final pLeftBottom = ll.LatLng(south, west);
            
            final width = const ll.Distance().as(ll.LengthUnit.Meter, pLeftTop, pRightTop);
            final height = const ll.Distance().as(ll.LengthUnit.Meter, pLeftTop, pLeftBottom);

            setState(() {
              _elements.add(DrawingElement(
                mode: DrawingMode.road,
                points: [
                  ll.LatLng(south, west),
                  ll.LatLng(north, west),
                  ll.LatLng(north, east),
                  ll.LatLng(south, east),
                ],
                text: '道路',
                estimatedWidthMeter: width,
                estimatedHeightMeter: height,
              ));
              _currentElement = null;
              _selectedElementIndex = _elements.length - 1;
              _selectedPointIndex = null;
              _showSnackBar('道路を作成しました。角をドラッグして調整できます。');
            });
          }
          break;
        case DrawingMode.entrance:
          if (_currentElement == null) {
            _currentElement = DrawingElement(mode: DrawingMode.entrance, points: [latLng]);
          } else {
            _currentElement!.points.add(latLng);
            _currentElement!.text = '入口';
            _elements.add(_currentElement!);
            _currentElement = null;
            _selectedElementIndex = _elements.length - 1;
          }
          break;
        default:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('車庫証明 配置図エディタ (OpenStreetMap)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_fix_high, color: Colors.amber),
            tooltip: 'AI自動トレース',
            onPressed: _isLoading ? null : _autoTraceWithAi,
          ),
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: _elements.isEmpty ? null : () => setState(() {
              _elements.removeLast();
            }),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            tooltip: '選択中の図形を削除',
            onPressed: (_currentMode == DrawingMode.select && _selectedElementIndex != null) 
              ? () => setState(() {
                  _elements.removeAt(_selectedElementIndex!);
                  _selectedElementIndex = null;
                  _selectedPointIndex = null;
                  _showSnackBar('図形を削除しました');
                })
              : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'すべて削除',
            onPressed: () => setState(() {
              _elements.clear();
              _currentElement = null;
              _selectedElementIndex = null;
              _selectedPointIndex = null;
            }),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, _elements);
            },
            child: const Text('完了'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      hintText: '住所を入力して検索',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _searchAddress,
                  child: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('検索'),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.grey[200],
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildToolButton(DrawingMode.freehand, Icons.edit, 'ライン追加'),
                  _buildToolButton(DrawingMode.rectangle, Icons.crop_square, '車庫/建物'),
                  _buildToolButton(DrawingMode.entrance, Icons.door_front_door, '入口'),
                  _buildToolButton(DrawingMode.road, Icons.add_road, '道路'),
                  _buildToolButton(DrawingMode.polygon, Icons.pentagon, '斜め/多角形'),
                  _buildToolButton(DrawingMode.line, Icons.horizontal_rule, '直線'),
                  _buildToolButton(DrawingMode.select, Icons.near_me, '選択/修正'),
                ],
              ),
            ),
          ),
          Expanded(
            child: _buildFlutterMap(),
          ),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('※地図上をタップして点を打ち、図形を作成してください。', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _buildFlutterMap() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return fmap.FlutterMap(
          mapController: _mapController,
          options: fmap.MapOptions(
            initialCenter: _center,
            initialZoom: 18.0,
            onTap: (tapPos, point) => _handleTap(point),
            onPointerHover: (event, point) {
              if (_currentElement != null) {
                setState(() {
                  _hoverLatLng = point;
                });
              }
            },
            interactionOptions: fmap.InteractionOptions(
              flags: fmap.InteractiveFlag.all,
            ),
          ),
          children: [
            fmap.TileLayer(
              urlTemplate: 'https://cyberjapandata.gsi.go.jp/xyz/seamlessphoto/{z}/{x}/{y}.jpg',
              userAgentPackageName: 'com.example.daisha_app',
              maxZoom: 24,
              maxNativeZoom: 18,
            ),
            fmap.PolylineLayer(
              polylines: [
                for (int i = 0; i < _elements.length; i++)
                  if (_elements[i].mode == DrawingMode.freehand || _elements[i].mode == DrawingMode.line || _elements[i].mode == DrawingMode.entrance)
                    fmap.Polyline(
                      points: _elements[i].points,
                      color: _selectedElementIndex == i ? Colors.orange : (_elements[i].mode == DrawingMode.entrance ? Colors.green : Colors.blue),
                      strokeWidth: _elements[i].mode == DrawingMode.entrance ? 5 : 3,
                    ),
                // 道路のセンターライン（点線）
                for (int i = 0; i < _elements.length; i++)
                  if (_elements[i].mode == DrawingMode.road && _elements[i].points.length >= 4)
                    for (var polyline in _createDashedCenterLine(_elements[i]))
                      polyline,
                if (_currentElement != null && (_currentElement!.mode == DrawingMode.freehand || _currentElement!.mode == DrawingMode.line || _currentElement!.mode == DrawingMode.entrance) && _currentElement!.points.length >= 1 && _hoverLatLng != null)
                  fmap.Polyline(
                    points: [..._currentElement!.points, _hoverLatLng!],
                    color: Colors.red.withOpacity(0.5),
                    strokeWidth: _currentElement!.mode == DrawingMode.entrance ? 5 : 3,
                  ),
              ],
            ),
            fmap.PolygonLayer(
              polygons: [
                for (int i = 0; i < _elements.length; i++)
                  if ((_elements[i].mode == DrawingMode.rectangle || _elements[i].mode == DrawingMode.polygon || _elements[i].mode == DrawingMode.road) && _elements[i].points.isNotEmpty)
                    fmap.Polygon(
                      points: _elements[i].points,
                      borderColor: _selectedElementIndex == i ? Colors.orange : (_elements[i].mode == DrawingMode.road ? Colors.grey : Colors.blue),
                      borderStrokeWidth: _elements[i].mode == DrawingMode.road ? 1 : 3,
                      color: (_selectedElementIndex == i ? Colors.orange : (_elements[i].mode == DrawingMode.road ? Colors.grey : Colors.blue)).withOpacity(0.4),
                    ),
                if (_currentElement != null && (_currentElement!.mode == DrawingMode.polygon) && _currentElement!.points.length >= 1 && _hoverLatLng != null)
                  fmap.Polygon(
                    points: [..._currentElement!.points, _hoverLatLng!],
                    borderColor: Colors.red.withOpacity(0.5),
                    borderStrokeWidth: 2,
                    color: Colors.red.withOpacity(0.1),
                  ),
                // 道路の作成中のプレビュー
                if (_currentElement != null && _currentElement!.mode == DrawingMode.road && _currentElement!.points.length == 1 && _hoverLatLng != null)
                  fmap.Polygon(
                    points: [
                      ll.LatLng(math.min(_currentElement!.points[0].latitude, _hoverLatLng!.latitude), math.min(_currentElement!.points[0].longitude, _hoverLatLng!.longitude)),
                      ll.LatLng(math.max(_currentElement!.points[0].latitude, _hoverLatLng!.latitude), math.min(_currentElement!.points[0].longitude, _hoverLatLng!.longitude)),
                      ll.LatLng(math.max(_currentElement!.points[0].latitude, _hoverLatLng!.latitude), math.max(_currentElement!.points[0].longitude, _hoverLatLng!.longitude)),
                      ll.LatLng(math.min(_currentElement!.points[0].latitude, _hoverLatLng!.latitude), math.max(_currentElement!.points[0].longitude, _hoverLatLng!.longitude)),
                    ],
                    borderColor: Colors.red.withOpacity(0.5),
                    borderStrokeWidth: 2,
                    color: Colors.red.withOpacity(0.1),
                  ),
              ],
            ),
            // 四角形の作成中のプレビュー（2点目が決まるまで）
            if (_currentElement != null && _currentElement!.mode == DrawingMode.rectangle && _currentElement!.points.length == 1)
              fmap.CircleLayer(
                circles: [
                  fmap.CircleMarker(
                    point: _currentElement!.points[0],
                    radius: 5,
                    color: Colors.red,
                  ),
                ],
              ),
            // マウス移動中のプレビュー（2点目決定前）
            if (_currentElement != null && _currentElement!.mode == DrawingMode.rectangle && _currentElement!.points.length == 1 && _hoverLatLng != null)
              fmap.PolygonLayer(
                polygons: [
                  fmap.Polygon(
                    points: [
                      ll.LatLng(math.min(_currentElement!.points[0].latitude, _hoverLatLng!.latitude), math.min(_currentElement!.points[0].longitude, _hoverLatLng!.longitude)),
                      ll.LatLng(math.max(_currentElement!.points[0].latitude, _hoverLatLng!.latitude), math.min(_currentElement!.points[0].longitude, _hoverLatLng!.longitude)),
                      ll.LatLng(math.max(_currentElement!.points[0].latitude, _hoverLatLng!.latitude), math.max(_currentElement!.points[0].longitude, _hoverLatLng!.longitude)),
                      ll.LatLng(math.min(_currentElement!.points[0].latitude, _hoverLatLng!.latitude), math.max(_currentElement!.points[0].longitude, _hoverLatLng!.longitude)),
                    ],
                    borderColor: Colors.red.withOpacity(0.5),
                    borderStrokeWidth: 2,
                    color: Colors.red.withOpacity(0.1),
                  ),
                ],
              ),
            if (_currentMode == DrawingMode.select)
              fmap.MarkerLayer(
                markers: [
                  for (int i = 0; i < _elements.length; i++)
                    for (int j = 0; j < _elements[i].points.length; j++)
                      fmap.Marker(
                        point: _elements[i].points[j],
                        width: 40, // タップ範囲を広げる
                        height: 40,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (_) {
                            setState(() {
                              _selectedElementIndex = i;
                              _selectedPointIndex = j;
                              _isDragging = true;
                            });
                          },
                          onPanUpdate: (details) {
                            // LayoutBuilder の context を使用して、FlutterMap 自体の RenderBox を取得
                            final RenderBox mapBox = context.findRenderObject() as RenderBox;
                            final localPoint = mapBox.globalToLocal(details.globalPosition);
                            
                            // マップの表示領域内での相対座標を LatLng に変換
                            final point = _mapController.camera.screenOffsetToLatLng(localPoint);
                            
                            setState(() {
                              _elements[i].points[j] = point;
                            });
                          },
                          onPanEnd: (_) {
                            setState(() {
                              _isDragging = false;
                            });
                          },
                          child: Center(
                            child: Container(
                              width: 12, // 見た目のサイズ
                              height: 12,
                              decoration: BoxDecoration(
                                color: (_selectedElementIndex == i && _selectedPointIndex == j) ? Colors.orange : Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.blue, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 4,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            // テキストラベルの表示
            fmap.MarkerLayer(
              markers: [
                for (int i = 0; i < _elements.length; i++)
                  if (_elements[i].text != null && _elements[i].points.isNotEmpty)
                    fmap.Marker(
                      point: _calculateCenter(_elements[i].points),
                      width: 100,
                      height: 30,
                      child: IgnorePointer(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey, width: 0.5),
                            ),
                            child: Text(
                              _elements[i].text!,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ],
        );
      },
    );
  }

  ll.LatLng _calculateCenter(List<ll.LatLng> points) {
    if (points.isEmpty) return const ll.LatLng(0, 0);
    double lat = 0;
    double lng = 0;
    for (final p in points) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return ll.LatLng(lat / points.length, lng / points.length);
  }

  List<fmap.Polyline> _createDashedCenterLine(DrawingElement element) {
    if (element.points.length < 4) return [];

    // 道路の形状に基づいて、長辺を特定しセンターラインを引く
    // 0-1 と 2-3 が短辺、1-2 と 3-0 が長辺と仮定（またはその逆）
    final d01 = const ll.Distance().as(ll.LengthUnit.Meter, element.points[0], element.points[1]);
    final d12 = const ll.Distance().as(ll.LengthUnit.Meter, element.points[1], element.points[2]);

    ll.LatLng start;
    ll.LatLng end;

    if (d01 < d12) {
      // 0-1が短辺 -> 0-1の中点から2-3の中点へ
      start = ll.LatLng(
        (element.points[0].latitude + element.points[1].latitude) / 2,
        (element.points[0].longitude + element.points[1].longitude) / 2,
      );
      end = ll.LatLng(
        (element.points[2].latitude + element.points[3].latitude) / 2,
        (element.points[2].longitude + element.points[3].longitude) / 2,
      );
    } else {
      // 1-2が短辺 -> 1-2の中点から3-0の中点へ
      start = ll.LatLng(
        (element.points[1].latitude + element.points[2].latitude) / 2,
        (element.points[1].longitude + element.points[2].longitude) / 2,
      );
      end = ll.LatLng(
        (element.points[3].latitude + element.points[0].latitude) / 2,
        (element.points[3].longitude + element.points[0].longitude) / 2,
      );
    }

    // 点線を生成
    final List<fmap.Polyline> dashes = [];
    final totalDistance = const ll.Distance().as(ll.LengthUnit.Meter, start, end);
    const dashMeter = 2.0; // 点の長さ
    const gapMeter = 2.0;  // 空白の長さ

    double currentPos = 0;
    while (currentPos < totalDistance) {
      final dashStartPercent = currentPos / totalDistance;
      final dashEndPercent = math.min((currentPos + dashMeter) / totalDistance, 1.0);

      final dashStart = ll.LatLng(
        start.latitude + (end.latitude - start.latitude) * dashStartPercent,
        start.longitude + (end.longitude - start.longitude) * dashStartPercent,
      );
      final dashEnd = ll.LatLng(
        start.latitude + (end.latitude - start.latitude) * dashEndPercent,
        start.longitude + (end.longitude - start.longitude) * dashEndPercent,
      );

      dashes.add(fmap.Polyline(
        points: [dashStart, dashEnd],
        color: Colors.white.withOpacity(0.8),
        strokeWidth: 2,
      ));

      currentPos += dashMeter + gapMeter;
    }

    return dashes;
  }

  Widget _buildToolButton(DrawingMode mode, IconData icon, String label) {
    final isSelected = _currentMode == mode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          if (selected) setState(() {
            _currentMode = mode;
            _currentElement = null;
          });
        },
        avatar: Icon(icon, size: 18, color: isSelected ? Colors.white : Colors.black),
      ),
    );
  }
}
