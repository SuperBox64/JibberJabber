#!/bin/bash
# Usage: ./test_example.sh <impl> <mode> <example> [target]
# Impl: jjpy, jjswift
# Mode: run, compile, asm, exec, build, transpile
# Examples:
#   ./test_example.sh jjpy run numbers
#   ./test_example.sh jjswift exec enums c
#   ./test_example.sh jjpy exec fizzbuzz swift

IMPL="${1:-jjpy}"
MODE="${2:-run}"
EXAMPLE="${3:-numbers}"
TARGET="${4:-c}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Testing: $EXAMPLE | impl: $IMPL | mode: $MODE"
[ "$MODE" = "exec" ] || [ "$MODE" = "build" ] || [ "$MODE" = "transpile" ] && echo "Target: $TARGET"
echo "=========================================="

run_test() {
    case "$IMPL" in
        jjpy)
            cd "$SCRIPT_DIR/jibjab/jjpy" || exit 1
            case "$MODE" in
                run)      python3 jj.py run "../examples/$EXAMPLE.jj" ;;
                compile)  python3 jj.py compile "../examples/$EXAMPLE.jj" "/tmp/${EXAMPLE}_py" && "/tmp/${EXAMPLE}_py" ;;
                asm)      python3 jj.py asm "../examples/$EXAMPLE.jj" "/tmp/${EXAMPLE}_py_asm" && "/tmp/${EXAMPLE}_py_asm" ;;
                exec)     python3 jj.py exec "../examples/$EXAMPLE.jj" "$TARGET" ;;
                build)    python3 jj.py build "../examples/$EXAMPLE.jj" "$TARGET" "/tmp/${EXAMPLE}_${TARGET}" ;;
                transpile) python3 jj.py transpile "../examples/$EXAMPLE.jj" "$TARGET" ;;
            esac
            ;;
        jjswift)
            cd "$SCRIPT_DIR/jibjab/jjswift" || exit 1
            case "$MODE" in
                run)      swift run jjswift run "../examples/$EXAMPLE.jj" ;;
                compile)  swift run jjswift compile "../examples/$EXAMPLE.jj" "/tmp/${EXAMPLE}_swift" && "/tmp/${EXAMPLE}_swift" ;;
                asm)      swift run jjswift asm "../examples/$EXAMPLE.jj" "/tmp/${EXAMPLE}_swift_asm" && "/tmp/${EXAMPLE}_swift_asm" ;;
                exec)     swift run jjswift exec "../examples/$EXAMPLE.jj" "$TARGET" ;;
                build)    swift run jjswift build "../examples/$EXAMPLE.jj" "$TARGET" "/tmp/${EXAMPLE}_${TARGET}" ;;
                transpile) swift run jjswift transpile "../examples/$EXAMPLE.jj" "$TARGET" ;;
            esac
            ;;
        *)
            echo "Unknown impl: $IMPL (use jjpy or jjswift)"
            return 1
            ;;
    esac
}

if run_test 2>&1; then
    echo ""
    echo "=========================================="
    echo "PASS: $EXAMPLE ($IMPL $MODE $TARGET)"
else
    echo ""
    echo "=========================================="
    echo "FAIL: $EXAMPLE ($IMPL $MODE $TARGET)"
    exit 1
fi
