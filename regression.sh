#!/usr/bin/env bash
# JibJab Full Regression Test Suite
set -o pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RD="/tmp/jj_reg_$$"
mkdir -p "$RD"
TOTAL_P=0; TOTAL_F=0

echo ""
echo "JibJab Regression Suite"
echo "======================="
echo ""

for impl in jjpy jjswift; do
    echo "[$impl]"
    for ex in numbers fizzbuzz fibonacci variables enums dictionaries tuples arrays comparisons hello; do
        line=$(bash "$SCRIPT_DIR/test_all.sh" "$impl" "$ex" 2>&1 | tail -1)
        p=$(echo "$line" | sed 's/.*: \([0-9]*\) passed.*/\1/')
        f=$(echo "$line" | sed 's/.*, \([0-9]*\) failed.*/\1/')
        TOTAL_P=$((TOTAL_P + p))
        TOTAL_F=$((TOTAL_F + f))
        echo "$p $f" > "$RD/${impl}_${ex}"
        if [ "$f" -eq 0 ]; then
            echo "  $ex: $p/$p PASS"
        else
            echo "  $ex: $p passed, $f FAILED"
        fi
    done
    echo ""
done

echo "======================="
echo "TOTAL: $TOTAL_P passed, $TOTAL_F failed"
echo ""
echo ""
echo "SUMMARY GRID"
echo "============"
echo ""
echo "Example        jjpy          jjswift"
echo "-------------- ------------- -------------"
for ex in numbers fizzbuzz fibonacci variables enums dictionaries tuples arrays comparisons hello; do
    py_data=$(cat "$RD/jjpy_${ex}" 2>/dev/null)
    sw_data=$(cat "$RD/jjswift_${ex}" 2>/dev/null)
    py_p=$(echo "$py_data" | cut -d' ' -f1)
    py_f=$(echo "$py_data" | cut -d' ' -f2)
    sw_p=$(echo "$sw_data" | cut -d' ' -f1)
    sw_f=$(echo "$sw_data" | cut -d' ' -f2)
    if [ "$py_f" -eq 0 ]; then py_str="$py_p/$py_p PASS"; else py_str="$py_p ok $py_f FAIL"; fi
    if [ "$sw_f" -eq 0 ]; then sw_str="$sw_p/$sw_p PASS"; else sw_str="$sw_p ok $sw_f FAIL"; fi
    echo "$ex $py_str $sw_str" | awk '{ printf "%-14s  %-13s %-13s\n", $1, $2" "$3, $4" "$5 }'
done
echo ""
echo "TOTAL: $TOTAL_P passed, $TOTAL_F failed"
echo ""

rm -rf "$RD"
