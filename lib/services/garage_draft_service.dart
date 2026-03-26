
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class GarageDraft {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final bool isLightCar;
  final String addressMain;
  final String addressParking;
  final String ownerName;
  final String ownerAddress;
  final String ownerPhone;
  final String vehicleName;
  final String modelCode;
  final String vin;
  final String length;
  final String width;
  final String height;
  final String policeStation;
  final String roadWidth;
  final String parkingWidth;
  final String parkingDepth;

  GarageDraft({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.isLightCar,
    required this.addressMain,
    required this.addressParking,
    required this.ownerName,
    required this.ownerAddress,
    required this.ownerPhone,
    required this.vehicleName,
    required this.modelCode,
    required this.vin,
    required this.length,
    required this.width,
    required this.height,
    required this.policeStation,
    required this.roadWidth,
    required this.parkingWidth,
    required this.parkingDepth,
  });

  factory GarageDraft.fromMap(Map<String, dynamic> map) {
    return GarageDraft(
      id: map['id'],
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
      createdBy: map['created_by'] ?? '',
      isLightCar: map['is_light_car'] ?? false,
      addressMain: map['address_main'] ?? '',
      addressParking: map['address_parking'] ?? '',
      ownerName: map['owner_name'] ?? '',
      ownerAddress: map['owner_address'] ?? '',
      ownerPhone: map['owner_phone'] ?? '',
      vehicleName: map['vehicle_name'] ?? '',
      modelCode: map['model_code'] ?? '',
      vin: map['vin'] ?? '',
      length: map['length'] ?? '',
      width: map['width'] ?? '',
      height: map['height'] ?? '',
      policeStation: map['police_station'] ?? '',
      roadWidth: map['road_width'] ?? '',
      parkingWidth: map['parking_width'] ?? '',
      parkingDepth: map['parking_depth'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'created_by': createdBy,
      'is_light_car': isLightCar,
      'address_main': addressMain,
      'address_parking': addressParking,
      'owner_name': ownerName,
      'owner_address': ownerAddress,
      'owner_phone': ownerPhone,
      'vehicle_name': vehicleName,
      'model_code': modelCode,
      'vin': vin,
      'length': length,
      'width': width,
      'height': height,
      'police_station': policeStation,
      'road_width': roadWidth,
      'parking_width': parkingWidth,
      'parking_depth': parkingDepth,
    };
  }
}

class GarageDraftService {
  static const String tableName = 'garage_drafts';

  static Future<void> saveDraft(GarageDraft draft) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    
    final Map<String, dynamic> data = draft.toMap();
    if (user != null) {
      data['created_by'] = user.id;
    }

    await client.from(tableName).upsert(data);
  }

  static Future<List<GarageDraft>> fetchAllDrafts() async {
    final client = Supabase.instance.client;
    final data = await client.from(tableName).select().order('updated_at', ascending: false);
    
    return (data as List).map((map) => GarageDraft.fromMap(map)).toList();
  }

  static Future<void> deleteDraft(String id) async {
    final client = Supabase.instance.client;
    await client.from(tableName).delete().eq('id', id);
  }
}
