with open('lib/screens/capture_movement_screen.dart', 'r') as f:
    lines = f.readlines()

editIdx = -1
for i, l in enumerate(lines):
    if "void _showEditCategoryModal(" in l:
        editIdx = i
        break

b = 0
editEndIdx = editIdx
for i in range(editIdx, len(lines)):
    b += lines[i].count('{') - lines[i].count('}')
    if b == 0:
        editEndIdx = i
        break

rep = """  void _showEditCategoryModal(BuildContext context, AppState app, Map<String, dynamic> category) {
    final nameCtrl = TextEditingController(text: category['name']?.toString() ?? '');
    String selectedType = category['type']?.toString() ?? 'BOTH';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 16, left: 16, right: 16, top: 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Manage Category', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)), onPressed: () async {
                final confirm = await showDialog<bool>(context: context, builder: (dC) => AlertDialog(title: const Text('Delete Category'), content: Text('Are you sure you want to delete "${category['name']}"?'), actions: [TextButton(onPressed: () => Navigator.pop(dC, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(dC, true), child: const Text('Delete', style: TextStyle(color: Colors.red)))]));
                if (confirm == true) {
                  final success = await app.deleteCategory(category['id'].toString());
                  if (mounted) {
                    Navigator.pop(ctx);
                    if (success) {
                      setState(() { if (_selectedCategory?['id'] == category['id']) _selectedCategory = null; });
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category deleted')));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(app.errorMessage ?? 'Failed to delete category')));
                    }
                  }
                }
              }),
            ]),
            const SizedBox(height: 16),
            TextField(controller: nameCtrl, decoration: InputDecoration(labelText: 'Category Name', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 16),
            const Text('Applies To', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
            const SizedBox(height: 8),
            Row(children: [
              ChoiceChip(label: const Text('Both'), selected: selectedType == 'BOTH', onSelected: (v) => setModalState(() => selectedType = 'BOTH')),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('Inflow Only'), selected: selectedType == 'INFLOW', onSelected: (v) => setModalState(() => selectedType = 'INFLOW')),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('Outflow Only'), selected: selectedType == 'OUTFLOW', onSelected: (v) => setModalState(() => selectedType = 'OUTFLOW')),
            ]),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  final success = await app.updateCategory(id: category['id'].toString(), name: name, type: selectedType);
                  if (mounted) {
                    Navigator.pop(ctx);
                    if (success) {
                      setState(() { if (_selectedCategory?['id'] == category['id']) _selectedCategory = {..._selectedCategory!, 'name': name, 'type': selectedType}; });
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category updated')));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(app.errorMessage ?? 'Failed to update category')));
                    }
                  }
                },
                child: const Text('Update Category', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
"""

lines = lines[:editIdx] + [rep] + lines[editEndIdx + 1:]
with open('lib/screens/capture_movement_screen.dart', 'w') as f:
    f.writelines(l if l.endswith('\n') else l + '\n' for l in lines)
