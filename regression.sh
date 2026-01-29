#!/usr/bin/env bash
# JibJab Full Regression Test Suite
# Usage: ./regression.sh           (just runs tests, prints total)
#        ./regression.sh -v        (verbose - line by line results)
#        ./regression.sh -g        (grid - ASCII spreadsheet to file)
#        ./regression.sh -vg       (both verbose + grid)
#        ./regression.sh -v go     (run only the 'go' target)
#        ./regression.sh -vg c     (grid + verbose for 'c' target only)
set -o pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RD="/tmp/jj_reg_$$"
mkdir -p "$RD"
TOTAL_P=0; TOTAL_F=0
GRID="/tmp/jj_regression_grid.txt"
VERBOSE=0; DOGRID=0; FILTER=""
for arg in "$@"; do
    case "$arg" in
        -vg|-gv) VERBOSE=1; DOGRID=1 ;;
        -v)      VERBOSE=1 ;;
        -g)      DOGRID=1 ;;
        -*)      ;;
        *)       FILTER="$arg" ;;
    esac
done



if [ "$VERBOSE" -eq 1 ]; then
    echo ""
    echo "JibJab Regression Suite"
    echo "======================="
    echo ""
fi

for impl in jjpy jjswift; do
    [ "$VERBOSE" -eq 1 ] && echo "[$impl]"
    for ex in numbers fizzbuzz fibonacci variables enums dictionaries tuples arrays comparisons hello; do
        if [ -z "$FILTER" ]; then
            for mode in run compile asm; do
                if "$SCRIPT_DIR/test_example.sh" "$impl" "$mode" "$ex" "" >/dev/null 2>&1; then
                    echo "P" > "$RD/${impl}_${ex}_${mode}"
                    TOTAL_P=$((TOTAL_P + 1))
                else
                    echo "F" > "$RD/${impl}_${ex}_${mode}"
                    TOTAL_F=$((TOTAL_F + 1))
                fi
            done
        fi
        for tgt in py js c cpp swift objc objcpp go; do
            [ -n "$FILTER" ] && [ "$tgt" != "$FILTER" ] && continue
            if "$SCRIPT_DIR/test_example.sh" "$impl" "build" "$ex" "$tgt" >/dev/null 2>&1; then
                echo "P" > "$RD/${impl}_${ex}_build_${tgt}"
                TOTAL_P=$((TOTAL_P + 1))
            else
                echo "F" > "$RD/${impl}_${ex}_build_${tgt}"
                TOTAL_F=$((TOTAL_F + 1))
            fi
            if "$SCRIPT_DIR/test_example.sh" "$impl" "exec" "$ex" "$tgt" >/dev/null 2>&1; then
                echo "P" > "$RD/${impl}_${ex}_exec_${tgt}"
                TOTAL_P=$((TOTAL_P + 1))
            else
                echo "F" > "$RD/${impl}_${ex}_exec_${tgt}"
                TOTAL_F=$((TOTAL_F + 1))
            fi
        done
        if [ "$VERBOSE" -eq 1 ]; then
            ep=0; ef=0
            for f in "$RD/${impl}_${ex}_"*; do
                v=$(cat "$f")
                [ "$v" = "P" ] && ep=$((ep+1))
                [ "$v" = "F" ] && ef=$((ef+1))
            done
            if [ "$ef" -eq 0 ]; then
                echo "  $ex: $ep/$ep PASS"
            else
                echo "  $ex: $ep passed, $ef FAILED"
            fi
        fi
    done
    [ "$VERBOSE" -eq 1 ] && echo ""
done

echo "TOTAL: $TOTAL_P passed, $TOTAL_F failed"

# Build ASCII grid (only with -g or -vg)
if [ "$DOGRID" -eq 1 ]; then
    sym() {
        if [ ! -f "$RD/$1" ]; then
            echo -n "➖"
            return
        fi
        v=$(cat "$RD/$1" 2>/dev/null)
        [ "$v" = "P" ] && echo -n "✅" || echo -n "❌"
    }

    HDR="              run  comp asm  py   js   c    cpp  swft objc ocpp go  "
    SEP="              ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ----"

    {
    for impl in jjpy jjswift; do
        echo "[$impl]"
        echo "$HDR"
        echo "$SEP"
        for ex in numbers fizzbuzz fibonacci variables enums dictionaries tuples arrays comparisons hello; do
            pad="$(printf '%-13s' "$ex")"
            row="$pad"
            for m in run compile asm; do
                row="$row $(sym "${impl}_${ex}_${m}")  "
            done
            for tgt in py js c cpp swift objc objcpp go; do
                row="$row $(sym "${impl}_${ex}_exec_${tgt}")  "
            done
            echo "$row"
        done
        echo ""
    done
    echo "TOTAL: $TOTAL_P passed, $TOTAL_F failed"
    } > "$GRID"

    echo "Grid saved to $GRID"
    echo ""
    cat "$GRID"
fi

rm -rf "$RD"
