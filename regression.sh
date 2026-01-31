#!/usr/bin/env bash
# JibJab Full Regression Test Suite
# Usage: ./regression.sh                    (runs everything)
#        ./regression.sh -v                 (verbose)
#        ./regression.sh -g                 (grid)
#        ./regression.sh -vg                (both)
#
# Filters (mix and match any combination):
#   base               = run, compile, asm
#   match              = jjpy vs jjswift runtime output comparison
#   <target>            = build + exec for that target
#                         (py js c cpp swift objc objcpp go)
#   (no filters)        = everything
#
# Examples:
#        ./regression.sh -vg go             (go only)
#        ./regression.sh -vg base           (run, compile, asm only)
#        ./regression.sh -vg match          (cross-impl comparison only)
#        ./regression.sh -vg base go        (run, compile, asm, go)
#        ./regression.sh -vg c go swift     (c, go, swift)
set -o pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RD="/tmp/jj_reg_$$"
mkdir -p "$RD"
TOTAL_P=0; TOTAL_F=0
GRID="/tmp/jj_regression_grid.txt"
VERBOSE=0; DOGRID=0
FILTERS=()
for arg in "$@"; do
    case "$arg" in
        -vg|-gv) VERBOSE=1; DOGRID=1 ;;
        -v)      VERBOSE=1 ;;
        -g)      DOGRID=1 ;;
        -*)      ;;
        *)       FILTERS+=("$arg") ;;
    esac
done

in_filters() {
    [ ${#FILTERS[@]} -eq 0 ] && return 0
    for f in "${FILTERS[@]}"; do
        [ "$f" = "$1" ] && return 0
    done
    return 1
}

if [ "$VERBOSE" -eq 1 ]; then
    echo ""
    echo "JibJab Regression Suite"
    echo "======================="
    echo ""
fi

for impl in jjpy jjswift; do
    [ "$VERBOSE" -eq 1 ] && echo "[$impl]"
    for ex in numbers fizzbuzz fibonacci variables enums dictionaries tuples arrays comparisons hello; do
        if in_filters "base"; then
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
            in_filters "$tgt" || continue
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
                [ -f "$f" ] || continue
                v=$(cat "$f")
                [ "$v" = "P" ] && ep=$((ep+1))
                [ "$v" = "F" ] && ef=$((ef+1))
            done
            if [ "$ep" -eq 0 ] && [ "$ef" -eq 0 ]; then
                :  # no tests ran for this example
            elif [ "$ef" -eq 0 ]; then
                echo "  $ex: $ep/$ep PASS"
            else
                echo "  $ex: $ep passed, $ef FAILED"
            fi
        fi
    done
    [ "$VERBOSE" -eq 1 ] && echo ""
done

# Cross-implementation comparison: jjpy run vs jjswift run
if in_filters "base" || in_filters "match"; then
    JJPY_DIR="$SCRIPT_DIR/jibjab/jjpy"
    JJSWIFT_DIR="$SCRIPT_DIR/jibjab/jjswift"
    JJSWIFT="$JJSWIFT_DIR/.build/debug/jjswift"
    [ "$VERBOSE" -eq 1 ] && echo "[jjpy vs jjswift]"
    for ex in numbers fizzbuzz fibonacci variables enums dictionaries tuples arrays comparisons hello; do
        py_out=$(cd "$JJPY_DIR" && python3 jj.py run "../examples/$ex.jj" 2>&1)
        sw_out=$(cd "$JJSWIFT_DIR" && "$JJSWIFT" run "../examples/$ex.jj" 2>&1)
        if [ "$py_out" = "$sw_out" ]; then
            echo "P" > "$RD/match_${ex}"
            TOTAL_P=$((TOTAL_P + 1))
            [ "$VERBOSE" -eq 1 ] && echo "  $ex: MATCH"
        else
            echo "F" > "$RD/match_${ex}"
            TOTAL_F=$((TOTAL_F + 1))
            [ "$VERBOSE" -eq 1 ] && echo "  $ex: MISMATCH"
        fi
    done
    [ "$VERBOSE" -eq 1 ] && echo ""
fi

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

    # Cross-implementation match grid
    echo "[jjpy vs jjswift runtime match]"
    echo "              match"
    echo "              -----"
    for ex in numbers fizzbuzz fibonacci variables enums dictionaries tuples arrays comparisons hello; do
        pad="$(printf '%-13s' "$ex")"
        echo "$pad $(sym "match_${ex}")"
    done
    echo ""

    echo "TOTAL: $TOTAL_P passed, $TOTAL_F failed"
    } > "$GRID"

    echo "Grid saved to $GRID"
    echo ""
    cat "$GRID"
fi

rm -rf "$RD"
