import re

def update_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 1. Update DropdownButtonFormField and TextField decoration inside forms
    # We'll specifically target common patterns.

    # 1a. Standard Input / Dropdowns (Recipient, Method, Note, normal textfields)
    # We hunt for:
    # decoration: const InputDecoration(
    #   filled: true,
    #   fillColor: AppTheme.inputBg,
    #   border: OutlineInputBorder(),
    # )
    
    # We replace with:
    # decoration: InputDecoration(
    #   filled: true,
    #   fillColor: const Color(0xFFF1F5F9),
    #   border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    #   contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    # )
    
    # Let's do a somewhat manual but regex-based approach for generic input decorators:
    input_pattern = r"(decoration:\s*(?:const\s*)?InputDecoration\([\s\S]*?)fillColor:\s*AppTheme\.inputBg,([\s\S]*?)border:\s*OutlineInputBorder\(\),([\s\S]*?)\)"
    
    def input_repl(m):
        full = m.group(0)
        # If it has prefixText: '৳ ', we need to treat it as amount/fee.
        if "prefixText: '৳ '" in full:
            # Drop the prefixText line
            updated = re.sub(r"prefixText:\s*'৳\s*',?", "", full)
            if "filled" not in updated:
                updated = updated.replace("InputDecoration(", "InputDecoration(\nfilled: true,\n")
            updated = re.sub(r"fillColor:\s*[A-Za-z0-9_\.]+,", "fillColor: const Color(0xFFF8FAFC),", updated)
            updated = re.sub(r"border:\s*OutlineInputBorder\(\),", "border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),\nprefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 0),\nprefixIcon: const Padding(padding: EdgeInsets.only(left: 14, right: 8), child: Text('৳', style: TextStyle(color: Color(0xFF64748B), fontSize: 22, fontWeight: FontWeight.bold))),", updated)
            if "contentPadding" not in updated:
                 updated = updated.replace("borderSide: BorderSide.none),", "borderSide: BorderSide.none),\ncontentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),")
            return updated.replace("const InputDecoration", "InputDecoration")
        else:
            updated = re.sub(r"fillColor:\s*[A-Za-z0-9_\.]+,", "fillColor: const Color(0xFFF1F5F9),", full)
            updated = re.sub(r"border:\s*OutlineInputBorder\(\),", "border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),\ncontentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),", updated)
            # Remove const if it became non-const due to BorderRadius/EdgeInsets (they are const but just in case)
            # Actually EdgeInsets and BorderRadius both have const constructors, so we can keep const BUT we can't if we don't know they are inside const.
            # Best is to remove const from `const InputDecoration` and let `dart lint` or manually ensure child consts.
            return updated.replace("const InputDecoration", "InputDecoration")

    content = re.sub(input_pattern, input_repl, content)

    # 1b. Buttons (Submit, Transfer, Create Wallet)
    # We want:
    # Full stadium capsule pill (StadiumBorder() or BorderRadius.circular(30)). Height: 50-54px.
    # Background: AppTheme.slateButtonGradient or Color(0xFF1E293B). Elevate with soft shadow.
    
    # In custody_handover_screen.dart button:
    # SizedBox(width: 280, height: 48, child: Container(decoration: BoxDecoration(gradient: AppTheme.slateButtonGradient, borderRadius: BorderRadius.circular(12)), ... ElevatedButton ... shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))

    def button_repl(m):
        full = m.group(0)
        updated = full.replace("BorderRadius.circular(12)", "BorderRadius.circular(30)")
        updated = updated.replace("height: 48", "height: 52")
        updated = updated.replace("width: 280", "width: double.infinity")
        if "BoxShadow" not in updated:
           updated = re.sub(r"gradient:\s*AppTheme\.slateButtonGradient,", r"gradient: AppTheme.slateButtonGradient,\nboxShadow: [BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))],", updated)
        return updated
        
    content = re.sub(r"SizedBox\(\s*width:\s*\d+,\s*height:\s*\d+,\s*child:\s*Container\(\s*decoration:\s*BoxDecoration\([\s\S]*?ElevatedButton.icon[\s\S]*?borderRadius:\s*BorderRadius\.circular\(12\)\),[\s\S]*?\)[\s\S]*?\)[\s\S]*?\)", button_repl, content)

    # In wallets_screen.dart modal buttons:
    # ElevatedButton(
    #   style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGradientFallback, minimumSize: const Size(double.infinity, 48)), ...

    def wallet_btn_repl(m):
         txt = m.group(0)
         txt = txt.replace("backgroundColor: AppTheme.primaryGradientFallback", "backgroundColor: const Color(0xFF1E293B)")
         txt = txt.replace("const Size(double.infinity, 48)", "const Size(double.infinity, 52)")
         if "shape:" not in txt:
             txt = txt.replace("minimumSize: const Size(double.infinity, 52)", "minimumSize: const Size(double.infinity, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), elevation: 8, shadowColor: const Color(0xFF0F172A).withValues(alpha: 0.25)")
         return txt
         
    content = re.sub(r"ElevatedButton\(\s*style:\s*ElevatedButton\.styleFrom\([\s\S]*?\),[\s\S]*?\)", wallet_btn_repl, content)

    # 1c. Wallets Screen TextFields mapping:
    # TextField(controller: nameCtl, decoration: const InputDecoration(labelText: 'Wallet Name', border: OutlineInputBorder())),
    # We want to change generic TextFields without filled: true
    def plain_textfield_repl(m):
        full = m.group(0)
        # We need to add filled, fillColor, border, etc.
        updated = full.replace("border: OutlineInputBorder()", "border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none), filled: true, fillColor: const Color(0xFFF1F5F9), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)")
        updated = updated.replace("border: const OutlineInputBorder()", "border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none), filled: true, fillColor: const Color(0xFFF1F5F9), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)")
        updated = updated.replace("const InputDecoration", "InputDecoration")
        
        # If it's amount field (Initial Balance, Transfer Amount)
        if "decimal: true" in full or "(৳)" in full:
             updated = updated.replace("fillColor: const Color(0xFFF1F5F9)", "fillColor: const Color(0xFFF8FAFC)")
             # We want bold 24px and prefix Icon
             updated = updated.replace("InputDecoration(", "InputDecoration(\nprefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 0),\nprefixIcon: const Padding(padding: EdgeInsets.only(left: 14, right: 8), child: Text('৳', style: TextStyle(color: Color(0xFF64748B), fontSize: 22, fontWeight: FontWeight.bold))),\n")
             # Also inject style into TextField if not present
             if "style:" not in updated:
                  updated = updated.replace("TextField(", "TextField(style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),\n")
        return updated
        
    content = re.sub(r"TextField\([\s\S]*?decoration:\s*(?:const)?\s*InputDecoration\([\s\S]*?border:\s*(?:const)?\s*OutlineInputBorder\(\)[\s\S]*?\)", plain_textfield_repl, content)
    content = re.sub(r"TextFormField\([\s\S]*?decoration:\s*(?:const)?\s*InputDecoration\([\s\S]*?border:\s*(?:const)?\s*OutlineInputBorder\(\)[\s\S]*?\)", plain_textfield_repl, content)

    # 1d. Label colors and sizes
    # Replace TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.secondaryText)
    # with TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF64748B
