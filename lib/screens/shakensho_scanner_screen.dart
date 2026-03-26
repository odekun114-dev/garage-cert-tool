
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../utils/shakensho_qr_parser.dart';

class ShakenshoScannerScreen extends StatefulWidget {
  const ShakenshoScannerScreen({super.key});

  @override
  State<ShakenshoScannerScreen> createState() => _ShakenshoScannerScreenState();
}

class _ShakenshoScannerScreenState extends State<ShakenshoScannerScreen> {
  final List<String> _scannedTexts = [];
  bool _isFinished = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('車検証QRスキャン'),
        actions: [
          TextButton(
            onPressed: () {
              final data = ShakenshoQrParser.parse(_scannedTexts);
              Navigator.pop(context, data);
            },
            child: const Text('完了', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                const Icon(Icons.qr_code_scanner, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '車検証に印字されているQRコードを順番にかざしてください (${_scannedTexts.length}個 読取済み)',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: MobileScanner(
              onDetect: (capture) {
                final List<Barcode> barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  final String? code = barcode.rawValue;
                  if (code != null && !_scannedTexts.contains(code)) {
                    setState(() {
                      _scannedTexts.add(code);
                    });
                    // フィードバック
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('読取成功: $code'), duration: const Duration(milliseconds: 500)),
                    );
                  }
                }
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text('読取済みの内容:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                SizedBox(
                  height: 100,
                  child: ListView.builder(
                    itemCount: _scannedTexts.length,
                    itemBuilder: (context, index) => Text(
                      '${index + 1}: ${_scannedTexts[index].substring(0, _scannedTexts[index].length > 20 ? 20 : _scannedTexts[index].length)}...',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      final data = ShakenshoQrParser.parse(_scannedTexts);
                      Navigator.pop(context, data);
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                    child: const Text('全ての読取を完了して反映'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
