#!/bin/bash
# MusyncMIMO Setup Script
# Run this after installing Flutter SDK

set -e

echo "═══════════════════════════════════════════════════════"
echo "  MusyncMIMO — Project Setup"
echo "═══════════════════════════════════════════════════════"
echo ""

# Check Flutter
if ! command -v flutter &> /dev/null; then
    echo "ERROR: Flutter is not installed."
    echo "Install from: https://docs.flutter.dev/get-started/install"
    exit 1
fi

echo "Flutter version:"
flutter --version
echo ""

# Navigate to project
cd "$(dirname "$0")"

# Get dependencies
echo "Installing dependencies..."
flutter pub get
echo ""

# Run code generation if needed
echo "Checking for code generation..."
# flutter pub run build_runner build --delete-conflicting-outputs
echo ""

# Run analyzer
echo "Running analyzer..."
flutter analyze
echo ""

# Run tests
echo "Running tests..."
flutter test
echo ""

# Run sync analysis
echo "Running clock sync performance analysis..."
dart run bin/analyze_sync.dart
echo ""

echo "═══════════════════════════════════════════════════════"
echo "  Setup complete!"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Next steps:"
echo "  1. Connect an Android device or start an emulator"
echo "  2. Run: flutter run"
echo "  3. On a second device, do the same"
echo "  4. On one device, tap 'Créer un groupe'"
echo "  5. On the other, tap 'Rejoindre' on the discovered device"
echo "  6. Select an audio file and play!"
echo ""
