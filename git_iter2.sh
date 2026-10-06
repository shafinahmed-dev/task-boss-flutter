commits=$(git log --format="%H" lib/screens/capture_movement_screen.dart)
for commit in $commits; do
  git checkout $commit -- lib/screens/capture_movement_screen.dart
  echo "Checking $commit"
  powershell -Command "C:\flutter\bin\flutter.bat analyze lib/screens/capture_movement_screen.dart" > result.txt 2>&1
  if grep -q "No issues found!" result.txt; then
    echo "Found clean commit: $commit"
    break
  fi
done
