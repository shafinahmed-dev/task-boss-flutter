const fs = require('fs');

const parts = ['p1.txt', 'p2.txt', 'p3a.txt', 'p3b.txt', 'p4a1.txt', 'p4a2.txt', 'p4b.txt'];
let combined = '';

for (const p of parts) {
  if (fs.existsSync(p)) {
    combined += fs.readFileSync(p, 'utf-8') + '\n';
  } else {
    console.error('Missing part:', p);
  }
}

fs.writeFileSync('lib/screens/suite/ledger_details_screen.dart', combined, 'utf-8');
console.log('Successfully combined ledger_details_screen.dart');

for (const p of parts) {
  if (fs.existsSync(p)) fs.unlinkSync(p);
}
if (fs.existsSync('write_screen.js')) fs.unlinkSync('write_screen.js');
if (fs.existsSync('build_screen.js')) fs.unlinkSync('build_screen.js');
if (fs.existsSync('create_ledger_screen.py')) fs.unlinkSync('create_ledger_screen.py');
