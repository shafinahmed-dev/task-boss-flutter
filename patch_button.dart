import 'dart:io';

void main() {
  final file = File('lib/screens/capture_movement_screen.dart');
  var content = file.readAsStringSync();
  content = content.replaceAll(
    'child: ElevatedButton(\n                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGradientFallback, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),\n                  onPressed: _saving ? null : _submit,\n                  child: _saving ? const CircularProgressIndicator(color: Colors.white) : const Text(\'Save\', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),\n                ),',
    '''child: Container(
                  decoration: BoxDecoration(
                    gradient: AppTheme.slateButtonGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _saving ? null : _submit,
                    child: _saving ? const CircularProgressIndicator(color: Colors.white) : const Text('Save', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),'''
  );
  file.writeAsStringSync(content);
}
