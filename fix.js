const fs = require('fs');

// 1. Get user's current file (ends at _showEditCategoryModal)
let userLines = fs.readFileSync('lib/screens/capture_movement_screen.dart', 'utf-8').replace(/\r/g, '').split('\n');
// Fix the missing closure at the end of _showEditCategoryModal
// Find `      );` near the end
let idx = userLines.length - 1;
while(idx > 0 && !userLines[idx].includes('      );')) idx--;
if (idx > 0) {
    userLines.splice(idx, 0, '        ),'); // Add missing StatefulBuilder closure
}

// 2. Get the rest from perfect_b97.dart which starts at Future<void> _submit
let baseLines = fs.readFileSync('perfect_b97.dart', 'utf-8').replace(/\r/g, '').split('\n');
let submitIdx = baseLines.findIndex(l => l.includes('Future<void> _submit()'));

// 3. Combine them!
let finalLines = [...userLines, '', ...baseLines.slice(submitIdx)];

fs.writeFileSync('final.dart', finalLines.join('\n'));
