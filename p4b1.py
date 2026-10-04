with open('lib/screens/manager/manager_overview_screen.dart', 'a', encoding='utf-8') as f:
    f.write('''              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('Staff', style: TextStyle(color: darkSlate, fontSize: 15, fontWeight: FontWeight.bold)),
                            SizedBox(height: 2),
                            Text('Top 3 by Balance', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: Color(0xFF64748B), size: 20),
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManagerStaffScreen())),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (topEmployees.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No staff assigned to this concern.', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                      )
                    else
                      ...topEmployees.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final emp = entry.value;
                        final name = emp['name'] ?? 'Staff';
                        final handle = emp['handle'] ?? 'handle';
                        final bal = emp['balance'] ?? 0.0;
                        Color rankColor = const Color(0xFF64748B);
                        if (idx == 0) rankColor = const Color(0xFFD97706);
                        if (idx == 1) rankColor = const Color(0xFF64748B);
                        if (idx == 2) rankColor = const Color(0xFFB45309);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(color: rankColor.withOpacity(0.15), shape: BoxShape.circle),
                                child: Center(child: Text('#\${idx + 1}', style: TextStyle(color: rankColor, fontSize: 12, fontWeight: FontWeight.bold))),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, style: const TextStyle(color: darkSlate, fontSize: 14, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text('@\$handle', style: const TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                              Text(
                                '৳ \${_formatAmount(bal)}',
                                style: const TextStyle(color: darkSlate, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
''')
