with open("f74.dart") as f:
    lines = f.readlines()
count = 0
for i, line in enumerate(lines):
    count += line.count('{') - line.count('}')
    if count == 0 and i > 30:
        print(f"Brace hits 0 at line {i+1}")
        break
    if count < 0:
        print(f"Negative brace count at line {i+1}")
        break
