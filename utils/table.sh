#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## Buffered box tables: add titles, a header, rows, span rows and separators, then tableRender.
## Everything lives in flat global arrays because bash 3.2 has no nested or associative arrays, and
## helpers return through globals so rendering a table does not fork a subshell per cell.

function tableNew() {
    ROLL_TABLE_TITLES=()
    ROLL_TABLE_HEADERS=()
    ROLL_TABLE_KINDS=()
    ROLL_TABLE_TEXTS=()
    ROLL_TABLE_OFFSETS=()
    ROLL_TABLE_CELLS=()
    return 0
}
tableNew

## usage: tableTitle <text>
function tableTitle() {
    ROLL_TABLE_TITLES+=("$1")
    return 0
}

## usage: tableHeader <cell>...
function tableHeader() {
    ROLL_TABLE_HEADERS=("$@")
    return 0
}

## usage: tableRow <cell>...
function tableRow() {
    local columns=${#ROLL_TABLE_HEADERS[@]}
    local i=1

    if (( columns == 0 )); then
        error "tableRow called before tableHeader"
        return 1
    fi
    if (( $# > columns )); then
        error "tableRow got $# cells for ${columns} columns"
        return 1
    fi

    ROLL_TABLE_KINDS+=("row")
    ROLL_TABLE_TEXTS+=("")
    ROLL_TABLE_OFFSETS+=("${#ROLL_TABLE_CELLS[@]}")
    while (( i <= columns )); do
        if (( i <= $# )); then
            ROLL_TABLE_CELLS+=("${!i}")
        else
            ROLL_TABLE_CELLS+=("")
        fi
        i=$((i + 1))
    done
    return 0
}

## usage: tableSpan <text>
function tableSpan() {
    ROLL_TABLE_KINDS+=("span")
    ROLL_TABLE_TEXTS+=("$1")
    ROLL_TABLE_OFFSETS+=("-1")
    return 0
}

function tableSeparator() {
    ROLL_TABLE_KINDS+=("separator")
    ROLL_TABLE_TEXTS+=("")
    ROLL_TABLE_OFFSETS+=("-1")
    return 0
}

## usage: tableColor <green|red|yellow|cyan|dim|bold> <text>
function tableColor() {
    local code=""
    case "$1" in
        green) code=$'\033[32m' ;;
        red) code=$'\033[31m' ;;
        yellow) code=$'\033[33m' ;;
        cyan) code=$'\033[36m' ;;
        dim) code=$'\033[2m' ;;
        bold) code=$'\033[1m' ;;
    esac
    printf '%s%s%s' "${code}" "$2" $'\033[0m'
}

## Sets ROLL_TABLE_PLAIN to the text without color codes
function tableStripColors() {
    local text="$1" before=""
    while [[ "${text}" == *$'\033['* ]]; do
        before="${text%%$'\033['*}"
        text="${text#*$'\033['}"
        text="${before}${text#*m}"
    done
    ROLL_TABLE_PLAIN="${text}"
    return 0
}

## Sets ROLL_TABLE_PREFIX to the color codes the text starts with
function tableLeadingColors() {
    local rest="$1"
    ROLL_TABLE_PREFIX=""
    while [[ "${rest}" == $'\033['* ]]; do
        ROLL_TABLE_PREFIX="${ROLL_TABLE_PREFIX}${rest%%m*}m"
        rest="${rest#*m}"
    done
    return 0
}

## usage: tableWrap <plain text> <width>; sets ROLL_TABLE_LINES
function tableWrap() {
    local text="$1" width="$2" line="" word="" i=0
    local words
    words=()
    ROLL_TABLE_LINES=()

    (( width < 1 )) && width=1
    IFS=' ' read -r -a words <<< "${text}"

    while (( i < ${#words[@]} )); do
        word="${words[$i]}"
        while (( ${#word} > width )); do
            if [[ -n "${line}" ]]; then
                ROLL_TABLE_LINES+=("${line}")
                line=""
            fi
            ROLL_TABLE_LINES+=("${word:0:width}")
            word="${word:width}"
        done
        if [[ -z "${line}" ]]; then
            line="${word}"
        elif (( ${#line} + 1 + ${#word} <= width )); then
            line="${line} ${word}"
        else
            ROLL_TABLE_LINES+=("${line}")
            line="${word}"
        fi
        i=$((i + 1))
    done

    if [[ -n "${line}" || ${#ROLL_TABLE_LINES[@]} -eq 0 ]]; then
        ROLL_TABLE_LINES+=("${line}")
    fi
    return 0
}

## usage: tableCellLines <text> <width>; sets ROLL_TABLE_LINES (ready to print) and
## ROLL_TABLE_LINE_WIDTHS (visible width of each line)
function tableCellLines() {
    local text="$1" width="$2" plain="" i=0

    tableStripColors "${text}"
    plain="${ROLL_TABLE_PLAIN}"
    ROLL_TABLE_LINE_WIDTHS=()

    ## a cell that fits keeps its colors exactly as given, including codes in the middle
    if (( ${#plain} <= width )); then
        if (( ROLL_TABLE_COLOR )); then
            ROLL_TABLE_LINES=("${text}")
        else
            ROLL_TABLE_LINES=("${plain}")
        fi
        ROLL_TABLE_LINE_WIDTHS=("${#plain}")
        return 0
    fi

    tableWrap "${plain}" "${width}"
    ROLL_TABLE_PREFIX=""
    if (( ROLL_TABLE_COLOR )); then
        tableLeadingColors "${text}"
    fi
    while (( i < ${#ROLL_TABLE_LINES[@]} )); do
        ROLL_TABLE_LINE_WIDTHS+=("${#ROLL_TABLE_LINES[$i]}")
        if [[ -n "${ROLL_TABLE_PREFIX}" ]]; then
            ROLL_TABLE_LINES[$i]="${ROLL_TABLE_PREFIX}${ROLL_TABLE_LINES[$i]}"$'\033[0m'
        fi
        i=$((i + 1))
    done
    return 0
}

## usage: tableRepeat <count> <character>; sets ROLL_TABLE_FILL
function tableRepeat() {
    printf -v ROLL_TABLE_FILL '%*s' "$1" ''
    ROLL_TABLE_FILL="${ROLL_TABLE_FILL// /$2}"
    return 0
}

function tableEmitBorder() {
    if (( ROLL_TABLE_COLOR )); then
        printf '%s%s%s\n' $'\033[36m' "$1" $'\033[0m'
    else
        printf '%s\n' "$1"
    fi
    return 0
}

## usage: tableDrawLine <none|full|columns above> <none|full|columns below>
function tableDrawLine() {
    local above="$1" below="$2" left="├" right="┤" junction="─" line="" c=0
    local columns=${#ROLL_TABLE_HEADERS[@]}

    if [[ "${above}" == "none" ]]; then
        left="┌"; right="┐"
    elif [[ "${below}" == "none" ]]; then
        left="└"; right="┘"
    fi

    if [[ "${above}" == "columns" && "${below}" == "columns" ]]; then
        junction="┼"
    elif [[ "${below}" == "columns" ]]; then
        junction="┬"
    elif [[ "${above}" == "columns" ]]; then
        junction="┴"
    fi

    line="${left}"
    if (( columns == 0 )); then
        tableRepeat $((ROLL_TABLE_INNER + 2)) "─"
        line="${line}${ROLL_TABLE_FILL}"
    else
        while (( c < columns )); do
            if (( c > 0 )); then
                line="${line}${junction}"
            fi
            tableRepeat $((ROLL_TABLE_COL_WIDTHS[c] + 2)) "─"
            line="${line}${ROLL_TABLE_FILL}"
            c=$((c + 1))
        done
    fi
    tableEmitBorder "${line}${right}"
}

## Draws the line between the previous block and the next one, when one is needed
function tableBoundary() {
    local next="$1"
    if [[ "${ROLL_TABLE_PREV}" == "none" ]]; then
        tableDrawLine none "${next}"
    elif [[ "${ROLL_TABLE_PREV}" != "${next}" ]] || (( ROLL_TABLE_PENDING )); then
        tableDrawLine "${ROLL_TABLE_PREV}" "${next}"
    fi
    ROLL_TABLE_PREV="${next}"
    ROLL_TABLE_PENDING=0
    return 0
}

## usage: tableDrawFull <text>
function tableDrawFull() {
    local i=0 padding=""
    tableCellLines "$1" "${ROLL_TABLE_INNER}"
    while (( i < ${#ROLL_TABLE_LINES[@]} )); do
        printf -v padding '%*s' $((ROLL_TABLE_INNER - ROLL_TABLE_LINE_WIDTHS[i])) ''
        printf '%s %s%s %s\n' "${ROLL_TABLE_V}" "${ROLL_TABLE_LINES[$i]}" "${padding}" "${ROLL_TABLE_V}"
        i=$((i + 1))
    done
    return 0
}

## usage: tableDrawCells <bold 0|1> <cell>...
function tableDrawCells() {
    local bold="$1"
    shift
    local columns=$# c=0 n=0 l=0 height=1 cell="" text="" visible=0 line="" padding=""
    local lines widths starts counts
    lines=(); widths=(); starts=(); counts=()

    while (( c < columns )); do
        n=$((c + 1))
        cell="${!n}"
        if (( bold && ROLL_TABLE_COLOR )); then
            cell=$'\033[1m'"${cell}"$'\033[0m'
        fi
        tableCellLines "${cell}" "${ROLL_TABLE_COL_WIDTHS[c]}"
        starts[c]=${#lines[@]}
        counts[c]=${#ROLL_TABLE_LINES[@]}
        l=0
        while (( l < ${#ROLL_TABLE_LINES[@]} )); do
            lines+=("${ROLL_TABLE_LINES[$l]}")
            widths+=("${ROLL_TABLE_LINE_WIDTHS[$l]}")
            l=$((l + 1))
        done
        if (( counts[c] > height )); then
            height=${counts[c]}
        fi
        c=$((c + 1))
    done

    l=0
    while (( l < height )); do
        line="${ROLL_TABLE_V}"
        c=0
        while (( c < columns )); do
            text=""
            visible=0
            if (( l < counts[c] )); then
                text="${lines[$((starts[c] + l))]}"
                visible=${widths[$((starts[c] + l))]}
            fi
            printf -v padding '%*s' $((ROLL_TABLE_COL_WIDTHS[c] - visible)) ''
            line="${line} ${text}${padding} ${ROLL_TABLE_V}"
            c=$((c + 1))
        done
        printf '%s\n' "${line}"
        l=$((l + 1))
    done
    return 0
}

function tableRender() {
    local columns=${#ROLL_TABLE_HEADERS[@]}
    local c=0 i=0 total=0 widest=0 full=0 maxWidth=0
    local minimums
    minimums=()

    if (( columns == 0 && ${#ROLL_TABLE_TITLES[@]} == 0 && ${#ROLL_TABLE_KINDS[@]} == 0 )); then
        return 0
    fi

    ROLL_TABLE_COLOR=0
    if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]; then
        ROLL_TABLE_COLOR=1
    fi
    ROLL_TABLE_V="│"
    if (( ROLL_TABLE_COLOR )); then
        ROLL_TABLE_V=$'\033[36m│\033[0m'
    fi

    ROLL_TABLE_COL_WIDTHS=()
    while (( c < columns )); do
        tableStripColors "${ROLL_TABLE_HEADERS[$c]}"
        ROLL_TABLE_COL_WIDTHS[c]=${#ROLL_TABLE_PLAIN}
        minimums[c]=10
        if (( ${#ROLL_TABLE_PLAIN} > 10 )); then
            minimums[c]=${#ROLL_TABLE_PLAIN}
        fi
        c=$((c + 1))
    done

    while (( i < ${#ROLL_TABLE_KINDS[@]} )); do
        if [[ "${ROLL_TABLE_KINDS[$i]}" == "row" ]]; then
            c=0
            while (( c < columns )); do
                tableStripColors "${ROLL_TABLE_CELLS[$((ROLL_TABLE_OFFSETS[i] + c))]}"
                if (( ${#ROLL_TABLE_PLAIN} > ROLL_TABLE_COL_WIDTHS[c] )); then
                    ROLL_TABLE_COL_WIDTHS[c]=${#ROLL_TABLE_PLAIN}
                fi
                c=$((c + 1))
            done
        elif [[ "${ROLL_TABLE_KINDS[$i]}" == "span" ]]; then
            tableStripColors "${ROLL_TABLE_TEXTS[$i]}"
            if (( ${#ROLL_TABLE_PLAIN} > full )); then
                full=${#ROLL_TABLE_PLAIN}
            fi
        fi
        i=$((i + 1))
    done
    i=0
    while (( i < ${#ROLL_TABLE_TITLES[@]} )); do
        tableStripColors "${ROLL_TABLE_TITLES[$i]}"
        if (( ${#ROLL_TABLE_PLAIN} > full )); then
            full=${#ROLL_TABLE_PLAIN}
        fi
        i=$((i + 1))
    done

    ROLL_TABLE_INNER=${full}
    if (( columns > 0 )); then
        c=0
        while (( c < columns )); do
            total=$((total + ROLL_TABLE_COL_WIDTHS[c]))
            c=$((c + 1))
        done
        ROLL_TABLE_INNER=$((total + 3 * columns - 3))
    fi

    ## COLUMNS first, so a caller or test can fix the width; stty reads the real terminal size where
    ## tput inside a command substitution falls back to 80
    if [[ "${COLUMNS:-}" =~ ^[0-9]+$ ]] && (( COLUMNS > 0 )); then
        maxWidth=${COLUMNS}
    elif [[ -t 1 ]]; then
        ## braces: bash applies </dev/tty before 2>/dev/null, so a failing open would still print
        maxWidth="$({ stty size </dev/tty; } 2>/dev/null | awk '{print $2}')" || true
        if ! [[ "${maxWidth}" =~ ^[0-9]+$ ]]; then
            maxWidth="$(tput cols 2>/dev/null)" || true
        fi
        if ! [[ "${maxWidth}" =~ ^[0-9]+$ ]]; then
            maxWidth=0
        fi
    fi

    if (( maxWidth > 0 && columns > 0 )); then
        while (( ROLL_TABLE_INNER + 4 > maxWidth )); do
            widest=-1
            c=0
            while (( c < columns )); do
                if (( ROLL_TABLE_COL_WIDTHS[c] > minimums[c] )); then
                    if (( widest < 0 )) || (( ROLL_TABLE_COL_WIDTHS[c] > ROLL_TABLE_COL_WIDTHS[widest] )); then
                        widest=${c}
                    fi
                fi
                c=$((c + 1))
            done
            if (( widest < 0 )); then
                break
            fi
            ROLL_TABLE_COL_WIDTHS[widest]=$((ROLL_TABLE_COL_WIDTHS[widest] - 1))
            ROLL_TABLE_INNER=$((ROLL_TABLE_INNER - 1))
        done
    elif (( maxWidth > 0 && ROLL_TABLE_INNER + 4 > maxWidth && maxWidth - 4 >= 10 )); then
        ROLL_TABLE_INNER=$((maxWidth - 4))
    fi

    ## Titles and span rows widen the last column only after the terminal fit, and only up to the
    ## terminal width; widening first would pad that column with space the other columns needed
    if (( columns > 0 && full > ROLL_TABLE_INNER )); then
        total=${full}
        if (( maxWidth > 0 && total > maxWidth - 4 )); then
            total=$((maxWidth - 4))
        fi
        if (( total > ROLL_TABLE_INNER )); then
            ROLL_TABLE_COL_WIDTHS[columns - 1]=$((ROLL_TABLE_COL_WIDTHS[columns - 1] + total - ROLL_TABLE_INNER))
            ROLL_TABLE_INNER=${total}
        fi
    fi

    ROLL_TABLE_PREV="none"
    ROLL_TABLE_PENDING=0

    i=0
    while (( i < ${#ROLL_TABLE_TITLES[@]} )); do
        tableBoundary full
        tableDrawFull "${ROLL_TABLE_TITLES[$i]}"
        i=$((i + 1))
    done

    if (( columns > 0 )); then
        tableBoundary columns
        tableDrawCells 1 "${ROLL_TABLE_HEADERS[@]}"
        ROLL_TABLE_PENDING=1
    fi

    i=0
    while (( i < ${#ROLL_TABLE_KINDS[@]} )); do
        case "${ROLL_TABLE_KINDS[$i]}" in
            separator)
                if [[ "${ROLL_TABLE_PREV}" != "none" ]]; then
                    ROLL_TABLE_PENDING=1
                fi
                ;;
            row)
                tableBoundary columns
                tableDrawCells 0 "${ROLL_TABLE_CELLS[@]:$((ROLL_TABLE_OFFSETS[i])):columns}"
                ;;
            span)
                tableBoundary full
                tableDrawFull "${ROLL_TABLE_TEXTS[$i]}"
                ;;
        esac
        i=$((i + 1))
    done

    if [[ "${ROLL_TABLE_PREV}" != "none" ]]; then
        tableDrawLine "${ROLL_TABLE_PREV}" none
    fi
    return 0
}
