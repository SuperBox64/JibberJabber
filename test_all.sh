#!/bin/bash
# Usage: ./test_all.sh <impl> <example>
# Tests all modes for a given example
# Examples:
#   ./test_all.sh jjpy enums
#   ./test_all.sh jjswift numbers

IMPL="${1:-jjpy}"
EXAMPLE="${2:-numbers}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASSED=0
FAILED=0
FAILED_LIST=""

echo "Testing $EXAMPLE with $IMPL"
echo "=========================================="

run_test() {
    local mode="$1"
    local target="$2"
    local label="$mode"
    [ -n "$target" ] && label="$mode:$target"

    printf "  %-20s " "$label"

    if "$SCRIPT_DIR/test_example.sh" "$IMPL" "$mode" "$EXAMPLE" "$target" > /dev/null 2>&1; then
        echo "PASS"
        ((PASSED++))
    else
        echo "FAIL"
        ((FAILED++))
        FAILED_LIST="$FAILED_LIST $label"
    fi
}

# Core modes
run_test run
run_test compile
run_test asm

# Build and exec with all targets
for target in py js c cpp swift objc objcpp; do
    run_test build "$target"
    run_test exec "$target"
done

echo "=========================================="
echo "Results: $PASSED passed, $FAILED failed"
[ $FAILED -gt 0 ] && echo "Failed:$FAILED_LIST"
exit $FAILED
