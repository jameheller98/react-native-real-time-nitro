#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$SCRIPT_DIR/ios"
MBEDTLS_DIR="$IOS_DIR/mbedtls"
TEMP_DIR="$SCRIPT_DIR/temp_xcframework"

echo "Creating mbedTLS XCFrameworks..."

# Clean up old XCFrameworks and temp directory
rm -rf "$IOS_DIR/mbedcrypto.xcframework"
rm -rf "$IOS_DIR/mbedtls.xcframework"
rm -rf "$IOS_DIR/mbedx509.xcframework"
rm -rf "$TEMP_DIR"

# Create temp directories with properly named libraries
mkdir -p "$TEMP_DIR/device"
mkdir -p "$TEMP_DIR/simulator"

# Copy and rename libraries to have consistent names
cp "$MBEDTLS_DIR/lib/device-libmbedcrypto.a" "$TEMP_DIR/device/libmbedcrypto.a"
cp "$MBEDTLS_DIR/lib/simulator-libmbedcrypto.a" "$TEMP_DIR/simulator/libmbedcrypto.a"
cp "$MBEDTLS_DIR/lib/device-libmbedtls.a" "$TEMP_DIR/device/libmbedtls.a"
cp "$MBEDTLS_DIR/lib/simulator-libmbedtls.a" "$TEMP_DIR/simulator/libmbedtls.a"
cp "$MBEDTLS_DIR/lib/device-libmbedx509.a" "$TEMP_DIR/device/libmbedx509.a"
cp "$MBEDTLS_DIR/lib/simulator-libmbedx509.a" "$TEMP_DIR/simulator/libmbedx509.a"

# Create XCFramework for libmbedcrypto
xcodebuild -create-xcframework \
  -library "$TEMP_DIR/device/libmbedcrypto.a" \
  -headers "$MBEDTLS_DIR/include" \
  -library "$TEMP_DIR/simulator/libmbedcrypto.a" \
  -headers "$MBEDTLS_DIR/include" \
  -output "$IOS_DIR/mbedcrypto.xcframework"

# Create XCFramework for libmbedtls
xcodebuild -create-xcframework \
  -library "$TEMP_DIR/device/libmbedtls.a" \
  -headers "$MBEDTLS_DIR/include" \
  -library "$TEMP_DIR/simulator/libmbedtls.a" \
  -headers "$MBEDTLS_DIR/include" \
  -output "$IOS_DIR/mbedtls.xcframework"

# Create XCFramework for libmbedx509
xcodebuild -create-xcframework \
  -library "$TEMP_DIR/device/libmbedx509.a" \
  -headers "$MBEDTLS_DIR/include" \
  -library "$TEMP_DIR/simulator/libmbedx509.a" \
  -headers "$MBEDTLS_DIR/include" \
  -output "$IOS_DIR/mbedx509.xcframework"

# Clean up temp directory
rm -rf "$TEMP_DIR"

echo "✅ mbedTLS XCFrameworks created successfully!"
echo "   - mbedcrypto.xcframework"
echo "   - mbedtls.xcframework"
echo "   - mbedx509.xcframework"
