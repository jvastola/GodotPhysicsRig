#!/bin/bash
# Nakama Server Test Script
# Tests authentication, matchmaking, and basic API functionality

echo "========================================="
echo "Nakama Server Test Suite"
echo "========================================="
echo

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

test_passed() {
    echo -e "${GREEN}✓${NC} $1"
    ((TESTS_PASSED++))
}

test_failed() {
    echo -e "${RED}✗${NC} $1"
    ((TESTS_FAILED++))
}

# Test 1: Server is running
echo "Test 1: Checking if Nakama server is running..."
if docker ps | grep -q nakama; then
    test_passed "Nakama container is running"
else
    test_failed "Nakama container is NOT running"
    exit 1
fi

# Test 2: API port is accessible
echo "Test 2: Testing API port 7350..."
if curl -sf http://localhost:7350/ > /dev/null 2>&1; then
    test_passed "API port 7350 is accessible"
else
    test_failed "API port 7350 is NOT accessible"
fi

# Test 3: Console port is accessible
echo "Test 3: Testing Console port 7351..."
if curl -sf http://localhost:7351/ > /dev/null 2>&1; then
    test_passed "Console port 7351 is accessible"
else
    test_failed "Console port 7351 is NOT accessible"
fi

# Test 4: Device Authentication
echo "Test 4: Testing device authentication..."
RESPONSE=$(curl -s 'http://localhost:7350/v2/account/authenticate/device?create=true' \
    -H 'Content-Type: application/json' \
    -H 'Authorization: Basic ZGVmYXVsdGtleTo=' \
    -d '{"id":"test-device-12345"}')

if echo "$RESPONSE" | grep -q "token"; then
    test_passed "Device authentication successful"
    TOKEN=$(echo "$RESPONSE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    echo "   Auth token: ${TOKEN:0:20}..."
else
    test_failed "Device authentication failed"
    echo "   Response: $RESPONSE"
fi

# Test 5: Create multiple test users
echo "Test 5: Creating multiple test users..."
USER_COUNT=0
for i in {1..3}; do
    RESPONSE=$(curl -s 'http://localhost:7350/v2/account/authenticate/device?create=true' \
        -H 'Content-Type: application/json' \
        -H 'Authorization: Basic ZGVmYXVsdGtleTo=' \
        -d "{\"id\":\"synthetic-player-$i\"}")
    
    if echo "$RESPONSE" | grep -q "token"; then
        ((USER_COUNT++))
    fi
done

if [ $USER_COUNT -eq 3 ]; then
    test_passed "Created 3 synthetic players"
else
    test_failed "Only created $USER_COUNT/3 synthetic players"
fi

# Test 6: PostgreSQL is healthy
echo "Test 6: Checking PostgreSQL status..."
if docker ps | grep postgres | grep -q "healthy"; then
    test_passed "PostgreSQL is healthy"
else
    test_failed "PostgreSQL is NOT healthy"
fi

# Summary
echo
echo "========================================="
echo "Test Summary"
echo "========================================="
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
echo "========================================="

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed! ✓${NC}"
    echo
    echo "Next steps:"
    echo "1. Open admin console: http://localhost:7351 (admin/password)"
    echo "2. Test from Godot with NakamaManager"
    echo "3. Create matches and test multiplayer"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    echo "Check logs: docker logs nakama"
    exit 1
fi
