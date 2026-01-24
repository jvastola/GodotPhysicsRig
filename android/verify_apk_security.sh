#!/bin/bash
# =============================================================================
# Meta VRC Security Verification Script
# =============================================================================
# This script verifies that the APK doesn't contain classes flagged by Meta VRC:
# 1. ConscryptPlatform (Insecure HostnameVerifier)
# 2. JAIN-SIP SSL classes (Unsafe SSL TrustManager)
#
# Usage: ./verify_apk_security.sh [path_to_apk]
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default APK path
APK_PATH="${1:-android/scenetree.apk}"

echo "=============================================="
echo "Meta VRC Security Verification"
echo "=============================================="
echo ""

# Check if APK exists
if [ ! -f "$APK_PATH" ]; then
    echo -e "${RED}ERROR: APK not found at: $APK_PATH${NC}"
    echo "Usage: $0 [path_to_apk]"
    exit 1
fi

echo "Analyzing APK: $APK_PATH"
echo ""

# Create temp directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Extract APK
echo "Extracting APK..."
unzip -q "$APK_PATH" -d "$TEMP_DIR"

# Find all DEX files
DEX_FILES=$(find "$TEMP_DIR" -name "*.dex" 2>/dev/null)

if [ -z "$DEX_FILES" ]; then
    echo -e "${RED}ERROR: No DEX files found in APK${NC}"
    exit 1
fi

echo "Found DEX files:"
for dex in $DEX_FILES; do
    echo "  - $(basename $dex)"
done
echo ""

# Initialize counters
ISSUES_FOUND=0

# Function to check for class in DEX files
check_class() {
    local class_pattern="$1"
    local description="$2"
    local found=0
    
    for dex in $DEX_FILES; do
        # Use strings to search for class references in DEX
        if strings "$dex" 2>/dev/null | grep -q "$class_pattern"; then
            found=1
            break
        fi
    done
    
    if [ $found -eq 1 ]; then
        echo -e "${RED}✗ FOUND: $description${NC}"
        echo "  Pattern: $class_pattern"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
        return 1
    else
        echo -e "${GREEN}✓ NOT FOUND: $description${NC}"
        return 0
    fi
}

# More thorough check using grep on raw bytes
check_class_thorough() {
    local class_pattern="$1"
    local description="$2"
    local found=0
    
    for dex in $DEX_FILES; do
        if grep -q "$class_pattern" "$dex" 2>/dev/null; then
            found=1
            break
        fi
    done
    
    if [ $found -eq 1 ]; then
        echo -e "${RED}✗ FOUND: $description${NC}"
        echo "  Pattern: $class_pattern"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
        return 1
    else
        echo -e "${GREEN}✓ NOT FOUND: $description${NC}"
        return 0
    fi
}

echo "=============================================="
echo "Checking for Meta VRC Security Issues"
echo "=============================================="
echo ""

echo "--- Issue 1: Insecure HostnameVerifier ---"
check_class "ConscryptPlatform" "OkHttp ConscryptPlatform class"
check_class "okhttp3/internal/platform/ConscryptPlatform" "ConscryptPlatform (full path)"
check_class "ConscryptSocketAdapter" "OkHttp ConscryptSocketAdapter class"
check_class "okhttp3/internal/platform/android/ConscryptSocketAdapter" "ConscryptSocketAdapter (full path)"
echo ""

echo "--- Issue 2: Unsafe SSL TrustManager ---"
check_class "android/gov/nist" "JAIN-SIP android.gov.nist package"
check_class "SslNetworkLayer" "JAIN-SIP SslNetworkLayer class"
check_class "NioTlsMessageProcessor" "JAIN-SIP NioTlsMessageProcessor class"
check_class "gov/nist/javax/sip" "JAIN-SIP gov.nist.javax.sip package"
echo ""

echo "=============================================="
echo "Additional Security Checks"
echo "=============================================="
echo ""

# Check for Conscrypt library
check_class "org/conscrypt" "Conscrypt library"
check_class "libconscrypt" "Conscrypt native library"

# Check for any remaining JAIN-SIP references
check_class "javax/sip" "javax.sip package"
check_class "jain-sip" "JAIN-SIP library reference"

echo ""
echo "=============================================="
echo "Summary"
echo "=============================================="

if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}✓ SUCCESS: No Meta VRC security issues found!${NC}"
    echo ""
    echo "Your APK should pass Meta VRC security checks for:"
    echo "  - Insecure HostnameVerifier"
    echo "  - Unsafe SSL TrustManager"
    exit 0
else
    echo -e "${RED}✗ FAILED: Found $ISSUES_FOUND potential security issue(s)${NC}"
    echo ""
    echo "These issues may cause Meta VRC to flag your app."
    echo ""
    echo "Recommended actions:"
    echo "  1. Ensure minifyEnabled=true in build.gradle for release builds"
    echo "  2. Verify ProGuard/R8 rules are being applied"
    echo "  3. Check that dependency exclusions are working"
    echo "  4. Clean and rebuild: rm -rf android/build/build && re-export from Godot"
    exit 1
fi
