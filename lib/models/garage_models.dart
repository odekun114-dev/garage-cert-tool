import 'package:latlong2/latlong.dart';

enum DrawingMode { freehand, rectangle, line, polygon, text, select, entrance, road }

class DrawingElement {
  final DrawingMode mode;
  List<LatLng> points;
  String? text;
  bool isSelected;
  double? estimatedWidthMeter;
  double? estimatedHeightMeter;

  DrawingElement({
    required this.mode,
    required this.points,
    this.text,
    this.isSelected = false,
    this.estimatedWidthMeter,
    this.estimatedHeightMeter,
  });

  Map<String, dynamic> toJson() {
    return {
      'mode': mode.index,
      'points': points.map((p) => [p.latitude, p.longitude]).toList(),
      'text': text,
      'width': estimatedWidthMeter,
      'height': estimatedHeightMeter,
    };
  }
}

class GarageData {
  String address;
  String ownerName;
  String vehicleInfo;
  double? roadWidth;
  double? parkingWidth;
  double? parkingDepth;
  List<DrawingElement> elements;

  GarageData({
    this.address = '',
    this.ownerName = '',
    this.vehicleInfo = '',
    this.roadWidth,
    this.parkingWidth,
    this.parkingDepth,
    this.elements = const [],
  });
}
