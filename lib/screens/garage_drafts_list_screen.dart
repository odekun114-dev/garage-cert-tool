
import 'package:flutter/material.dart';
import '../services/garage_draft_service.dart';

class GarageDraftsListScreen extends StatefulWidget {
  const GarageDraftsListScreen({super.key});

  @override
  State<GarageDraftsListScreen> createState() => _GarageDraftsListScreenState();
}

class _GarageDraftsListScreenState extends State<GarageDraftsListScreen> {
  bool _isLoading = true;
  List<GarageDraft> _drafts = [];

  @override
  void initState() {
    super.initState();
    _fetchDrafts();
  }

  Future<void> _fetchDrafts() async {
    setState(() => _isLoading = true);
    try {
      final data = await GarageDraftService.fetchAllDrafts();
      setState(() {
        _drafts = data;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Fetch drafts error: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('保存済みデータ一覧'),
        backgroundColor: Colors.teal.shade50,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _drafts.isEmpty
              ? const Center(child: Text('保存されている下書きはありません'))
              : ListView.builder(
                  itemCount: _drafts.length,
                  itemBuilder: (context, index) {
                    final d = _drafts[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading: Icon(
                          d.isLightCar ? Icons.minor_crash : Icons.directions_car,
                          color: Colors.teal,
                        ),
                        title: Text('${d.ownerName.isEmpty ? "名前なし" : d.ownerName} 様'),
                        subtitle: Text('${d.vehicleName} / ${d.vin.length > 5 ? "...${d.vin.substring(d.vin.length - 5)}" : d.vin}'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${d.updatedAt.month}/${d.updatedAt.day} ${d.updatedAt.hour}:${d.updatedAt.minute.toString().padLeft(2, "0")}',
                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                            const Icon(Icons.arrow_forward_ios, size: 14),
                          ],
                        ),
                        onTap: () {
                          Navigator.pop(context, d);
                        },
                        onLongPress: () async {
                           final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('削除の確認'),
                                content: const Text('この下書きを削除しますか？'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
                                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('削除')),
                                ],
                              ),
                           );
                           if (confirm == true) {
                              await GarageDraftService.deleteDraft(d.id);
                              _fetchDrafts();
                           }
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
