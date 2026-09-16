#!/usr/bin/env bash
# Golden-output tests for utils/table.sh. stdout is captured, so no colors and no terminal width.
ROLL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export ROLL_DIR
. "$ROLL_DIR/utils/core.sh"
. "$ROLL_DIR/utils/table.sh"

pass=0; fail=0
check() {
    if [[ "$2" == "$3" ]]; then
        echo "  PASS  $1"; pass=$((pass + 1))
    else
        echo "  FAIL  $1"; fail=$((fail + 1))
        echo "--- expected"; printf '%s\n' "$3"
        echo "--- got"; printf '%s\n' "$2"
    fi
}

tableNew
tableHeader "A" "BB"
tableRow "x" "yyy"
tableRow "long" "z"
check "plain columns" "$(tableRender)" "$(cat <<'EOF'
┌──────┬─────┐
│ A    │ BB  │
├──────┼─────┤
│ x    │ yyy │
│ long │ z   │
└──────┴─────┘
EOF
)"

tableNew
tableTitle "T"
tableHeader "A" "B"
tableRow "1" "2"
tableSpan "S"
tableRow "3" "4"
check "title, span rows and junctions" "$(tableRender)" "$(cat <<'EOF'
┌───────┐
│ T     │
├───┬───┤
│ A │ B │
├───┼───┤
│ 1 │ 2 │
├───┴───┤
│ S     │
├───┬───┤
│ 3 │ 4 │
└───┴───┘
EOF
)"

tableNew
tableHeader "K" "VALUE"
tableRow "a" "one two three four five six"
check "wrap on spaces within COLUMNS" "$(COLUMNS=20 tableRender)" "$(cat <<'EOF'
┌───┬──────────────┐
│ K │ VALUE        │
├───┼──────────────┤
│ a │ one two      │
│   │ three four   │
│   │ five six     │
└───┴──────────────┘
EOF
)"

tableNew
tableHeader "K" "V"
tableRow "a" "abcdefghijklmnopqrstuvwxyz"
check "cut a word longer than its column" "$(COLUMNS=20 tableRender)" "$(cat <<'EOF'
┌───┬──────────────┐
│ K │ V            │
├───┼──────────────┤
│ a │ abcdefghijkl │
│   │ mnopqrstuvwx │
│   │ yz           │
└───┴──────────────┘
EOF
)"

tableNew
tableHeader "S"
tableRow "$(tableColor green OK)"
output="$(tableRender)"
check "colored cell measured and stripped" "$output" "$(cat <<'EOF'
┌────┐
│ S  │
├────┤
│ OK │
└────┘
EOF
)"
case "$output" in *$'\033'*) r=escape ;; *) r=clean ;; esac
check "no escape codes without a terminal" "$r" "clean"

tableNew
tableTitle "Wide title here"
tableHeader "A" "B"
tableRow "1" "2"
check "title wider than the columns grows the last column" "$(tableRender)" "$(cat <<'EOF'
┌─────────────────┐
│ Wide title here │
├───┬─────────────┤
│ A │ B           │
├───┼─────────────┤
│ 1 │ 2           │
└───┴─────────────┘
EOF
)"

tableNew
tableTitle "$(printf 'x%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40)"
tableHeader "K" "URL" "INFO"
tableRow "a" "aaaaaaaaaaaaaaaaaaaa" "bbbbbbbbbbb"
check "a wide title wraps instead of padding a column the others need" "$(COLUMNS=40 tableRender)" "$(cat <<'EOF'
┌──────────────────────────────────────┐
│ xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx │
│ xxxx                                 │
├───┬────────────────────┬─────────────┤
│ K │ URL                │ INFO        │
├───┼────────────────────┼─────────────┤
│ a │ aaaaaaaaaaaaaaaaaa │ bbbbbbbbbbb │
│   │ aa                 │             │
└───┴────────────────────┴─────────────┘
EOF
)"

tableNew
tableHeader "A"
tableSeparator
tableRow "1"
tableSeparator
tableSeparator
tableRow "2"
tableSeparator
check "separators never double up" "$(tableRender)" "$(cat <<'EOF'
┌───┐
│ A │
├───┤
│ 1 │
├───┤
│ 2 │
└───┘
EOF
)"

long="$(printf '%070d' 0)"
tableNew
tableHeader "K" "V"
tableRow "a" "$long"
unset COLUMNS
check "no maximum without COLUMNS or a terminal" "$(tableRender | wc -l | tr -d ' ')" "5"

tableNew
tableHeader "A"
( tableRow "1" "2" ) >/dev/null 2>&1
check "more cells than columns is an error" "$?" "1"

tableNew
check "empty table prints nothing" "$(tableRender)" ""

echo ""
echo "passed=$pass failed=$fail"
[[ $fail -eq 0 ]]
