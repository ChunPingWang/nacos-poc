#!/bin/bash
# Nacos PoC Test Suite
# Nacos v3.1.1 API Tests:
#   - Service Registration/Discovery (v3 Client API)
#   - Configuration Management (v1 API for publish/delete, v3 for read)
#   - Service Lifecycle (deregistration)

set -euo pipefail

NACOS_URL="http://localhost:8848/nacos"
PASS=0
FAIL=0
TOTAL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_test() {
    TOTAL=$((TOTAL + 1))
    echo -e "\n${YELLOW}[TEST $TOTAL] $1${NC}"
}

log_pass() {
    PASS=$((PASS + 1))
    echo -e "${GREEN}  PASS: $1${NC}"
}

log_fail() {
    FAIL=$((FAIL + 1))
    echo -e "${RED}  FAIL: $1${NC}"
}

echo "========================================"
echo "  Nacos PoC Test Suite (v3.1.1)"
echo "  Target: $NACOS_URL"
echo "  Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"

# ==========================================
# Category 1: Health Check
# ==========================================
echo -e "\n${CYAN}--- Category 1: Health Check ---${NC}"

log_test "Nacos Console Accessibility"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$NACOS_URL/")
if [ "$HTTP_CODE" = "200" ]; then
    log_pass "Nacos Console responds HTTP 200"
else
    log_fail "Nacos Console responds HTTP $HTTP_CODE (expected 200)"
fi

# ==========================================
# Category 2: Service Registration (v3 API)
# ==========================================
echo -e "\n${CYAN}--- Category 2: Service Registration ---${NC}"

log_test "Register service-a instance 1 (192.168.1.10:8080)"
RESULT=$(curl -s -X POST "$NACOS_URL/v3/client/ns/instance" \
    -d "serviceName=service-a&ip=192.168.1.10&port=8080&weight=1&enabled=true&healthy=true&ephemeral=true" 2>&1)
echo "  Response: $RESULT"
if echo "$RESULT" | grep -q '"code":0'; then
    log_pass "service-a instance 1 registered"
else
    log_fail "service-a instance 1 registration failed"
fi

log_test "Register service-a instance 2 (192.168.1.11:8080)"
RESULT=$(curl -s -X POST "$NACOS_URL/v3/client/ns/instance" \
    -d "serviceName=service-a&ip=192.168.1.11&port=8080&weight=1&enabled=true&healthy=true&ephemeral=true" 2>&1)
echo "  Response: $RESULT"
if echo "$RESULT" | grep -q '"code":0'; then
    log_pass "service-a instance 2 registered"
else
    log_fail "service-a instance 2 registration failed"
fi

log_test "Register service-b (192.168.2.10:9090)"
RESULT=$(curl -s -X POST "$NACOS_URL/v3/client/ns/instance" \
    -d "serviceName=service-b&ip=192.168.2.10&port=9090&weight=1&enabled=true&healthy=true&ephemeral=true" 2>&1)
echo "  Response: $RESULT"
if echo "$RESULT" | grep -q '"code":0'; then
    log_pass "service-b registered"
else
    log_fail "service-b registration failed"
fi

# ==========================================
# Category 3: Service Discovery (v3 API)
# ==========================================
sleep 2  # Wait for ephemeral instances to propagate
echo -e "\n${CYAN}--- Category 3: Service Discovery ---${NC}"

log_test "Discover service-a instances (expect 2)"
RESULT=$(curl -s "$NACOS_URL/v3/client/ns/instance/list?serviceName=service-a" 2>&1)
echo "  Response: $(echo "$RESULT" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin),indent=2))" 2>/dev/null || echo "$RESULT")"
INSTANCE_COUNT=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('data',[])))" 2>/dev/null || echo "0")
if [ "$INSTANCE_COUNT" = "2" ]; then
    log_pass "Found 2 instances of service-a"
else
    log_fail "Expected 2 instances, found $INSTANCE_COUNT"
fi

log_test "Discover service-b instances (expect 1)"
RESULT=$(curl -s "$NACOS_URL/v3/client/ns/instance/list?serviceName=service-b" 2>&1)
INSTANCE_COUNT=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('data',[])))" 2>/dev/null || echo "0")
echo "  Instance count: $INSTANCE_COUNT"
if [ "$INSTANCE_COUNT" = "1" ]; then
    log_pass "Found 1 instance of service-b"
else
    log_fail "Expected 1 instance, found $INSTANCE_COUNT"
fi

log_test "List all services (v1 API)"
RESULT=$(curl -s "$NACOS_URL/v1/ns/service/list?pageNo=1&pageSize=10" 2>&1)
echo "  Response: $RESULT"
if echo "$RESULT" | grep -q "service-a" && echo "$RESULT" | grep -q "service-b"; then
    log_pass "Both services found in service list"
else
    log_fail "Services not found in service list"
fi

# ==========================================
# Category 4: Configuration Management
# ==========================================
echo -e "\n${CYAN}--- Category 4: Configuration Management ---${NC}"

log_test "Publish config: app.properties (v1 API)"
RESULT=$(curl -s -X POST "$NACOS_URL/v1/cs/configs" \
    -d "dataId=app.properties&group=DEFAULT_GROUP&content=server.port=8080%0Aspring.datasource.url=jdbc:mysql://localhost:3306/mydb%0Aapp.name=demo-app" 2>&1)
echo "  Response: $RESULT"
if [ "$RESULT" = "true" ]; then
    log_pass "app.properties published"
else
    log_fail "app.properties publish failed: $RESULT"
fi

log_test "Publish YAML config: application.yaml (v1 API)"
YAML_CONTENT="server:
  port: 9090
spring:
  application:
    name: demo-service
  redis:
    host: redis-server
    port: 6379"
RESULT=$(curl -s -X POST "$NACOS_URL/v1/cs/configs" \
    --data-urlencode "dataId=application.yaml" \
    --data-urlencode "group=DEFAULT_GROUP" \
    --data-urlencode "content=$YAML_CONTENT" \
    --data-urlencode "type=yaml" 2>&1)
echo "  Response: $RESULT"
if [ "$RESULT" = "true" ]; then
    log_pass "application.yaml published"
else
    log_fail "application.yaml publish failed"
fi

sleep 1

log_test "Read config: app.properties (v3 Client API)"
RESULT=$(curl -s "$NACOS_URL/v3/client/cs/config?dataId=app.properties&groupName=DEFAULT_GROUP" 2>&1)
echo "  Response: $(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('content','N/A'))" 2>/dev/null || echo "$RESULT")"
if echo "$RESULT" | grep -q "server.port=8080"; then
    log_pass "Config content verified via v3 API"
else
    log_fail "Config content mismatch"
fi

log_test "Read config: app.properties (v1 API cross-verify)"
RESULT=$(curl -s "$NACOS_URL/v1/cs/configs?dataId=app.properties&group=DEFAULT_GROUP" 2>&1)
echo "  Response: $RESULT"
if echo "$RESULT" | grep -q "server.port=8080"; then
    log_pass "Config content verified via v1 API"
else
    log_fail "Config content mismatch via v1 API"
fi

log_test "Read YAML config (v3 Client API)"
RESULT=$(curl -s "$NACOS_URL/v3/client/cs/config?dataId=application.yaml&groupName=DEFAULT_GROUP" 2>&1)
CONTENT=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('content','N/A'))" 2>/dev/null || echo "N/A")
echo "  Content: $CONTENT"
if echo "$CONTENT" | grep -q "demo-service"; then
    log_pass "YAML config read successfully"
else
    log_fail "YAML config content mismatch"
fi

# ==========================================
# Category 5: Configuration Update
# ==========================================
echo -e "\n${CYAN}--- Category 5: Configuration Update ---${NC}"

log_test "Update config: app.properties (v1 API)"
RESULT=$(curl -s -X POST "$NACOS_URL/v1/cs/configs" \
    -d "dataId=app.properties&group=DEFAULT_GROUP&content=server.port=9090%0Aspring.datasource.url=jdbc:mysql://localhost:3306/mydb%0Aapp.name=demo-app-v2%0Aapp.version=2.0" 2>&1)
echo "  Response: $RESULT"
if [ "$RESULT" = "true" ]; then
    log_pass "Config updated"
else
    log_fail "Config update failed"
fi

sleep 1

log_test "Verify updated config (v3 Client API)"
RESULT=$(curl -s "$NACOS_URL/v3/client/cs/config?dataId=app.properties&groupName=DEFAULT_GROUP" 2>&1)
CONTENT=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('content','N/A'))" 2>/dev/null || echo "N/A")
echo "  Content: $CONTENT"
if echo "$CONTENT" | grep -q "app.version=2.0" && echo "$CONTENT" | grep -q "server.port=9090"; then
    log_pass "Updated config verified (port=9090, version=2.0)"
else
    log_fail "Updated config content mismatch"
fi

# ==========================================
# Category 6: Service Deregistration
# ==========================================
echo -e "\n${CYAN}--- Category 6: Service Deregistration ---${NC}"

log_test "Deregister service-a instance 2 (192.168.1.11:8080)"
RESULT=$(curl -s -X DELETE "$NACOS_URL/v3/client/ns/instance?serviceName=service-a&ip=192.168.1.11&port=8080&ephemeral=true" 2>&1)
echo "  Response: $RESULT"
if echo "$RESULT" | grep -q '"code":0'; then
    log_pass "Instance deregistered"
else
    log_fail "Instance deregistration failed"
fi

sleep 1

log_test "Verify service-a has 1 instance after deregistration"
RESULT=$(curl -s "$NACOS_URL/v3/client/ns/instance/list?serviceName=service-a" 2>&1)
INSTANCE_COUNT=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('data',[])))" 2>/dev/null || echo "0")
echo "  Instance count: $INSTANCE_COUNT"
if [ "$INSTANCE_COUNT" = "1" ]; then
    log_pass "1 instance remaining after deregistration"
else
    log_fail "Expected 1 instance, found $INSTANCE_COUNT"
fi

# ==========================================
# Category 7: Configuration Deletion
# ==========================================
echo -e "\n${CYAN}--- Category 7: Configuration Deletion ---${NC}"

log_test "Delete config: app.properties (v1 API)"
RESULT=$(curl -s -X DELETE "$NACOS_URL/v1/cs/configs?dataId=app.properties&group=DEFAULT_GROUP" 2>&1)
echo "  Response: $RESULT"
if [ "$RESULT" = "true" ]; then
    log_pass "Config deleted"
else
    log_fail "Config deletion failed"
fi

sleep 1

log_test "Verify config deleted (v3 Client API)"
RESULT=$(curl -s "$NACOS_URL/v3/client/cs/config?dataId=app.properties&groupName=DEFAULT_GROUP" 2>&1)
echo "  Response: $RESULT"
if echo "$RESULT" | grep -q '"code":20004'; then
    log_pass "Deleted config returns 20004 (resource not found)"
else
    log_fail "Deleted config should return 20004"
fi

# ==========================================
# Category 8: Cleanup & Final Verification
# ==========================================
echo -e "\n${CYAN}--- Category 8: Cleanup ---${NC}"

log_test "Delete remaining config: application.yaml"
RESULT=$(curl -s -X DELETE "$NACOS_URL/v1/cs/configs?dataId=application.yaml&group=DEFAULT_GROUP" 2>&1)
if [ "$RESULT" = "true" ]; then
    log_pass "application.yaml deleted"
else
    log_fail "application.yaml deletion failed"
fi

log_test "Deregister all remaining instances"
curl -s -X DELETE "$NACOS_URL/v3/client/ns/instance?serviceName=service-a&ip=192.168.1.10&port=8080&ephemeral=true" > /dev/null 2>&1
curl -s -X DELETE "$NACOS_URL/v3/client/ns/instance?serviceName=service-b&ip=192.168.2.10&port=9090&ephemeral=true" > /dev/null 2>&1
log_pass "All test instances deregistered"

# ==========================================
# Summary
# ==========================================
echo ""
echo "========================================"
echo "  Test Summary"
echo "========================================"
echo "  Total:  $TOTAL"
echo -e "  ${GREEN}Pass:   $PASS${NC}"
echo -e "  ${RED}Fail:   $FAIL${NC}"
echo -e "  Rate:   $(( PASS * 100 / TOTAL ))%"
echo "========================================"

if [ $FAIL -gt 0 ]; then
    exit 1
fi
