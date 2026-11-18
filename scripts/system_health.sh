#!/usr/bin/env bash
#
# system_health.sh - check CPU, memory, disk and load, log the result and
# exit with a status monitoring tools understand.
#
# Exit codes: 0 healthy, 1 warning, 2 critical (or bad arguments)

set -euo pipefail

VERSION="1.1.0"
MAX_LOG_SIZE=$((10 * 1024 * 1024))
MAX_ROTATIONS=5

DISK_THRESHOLD=80
CPU_THRESHOLD=90
MEM_THRESHOLD=85
CRIT_THRESHOLD=95
LOG_FILE="health_log.txt"
JSON_OUTPUT=false

WARNINGS=0
CRITICALS=0
ALERTS=()

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --disk PCT       disk usage warning threshold (default ${DISK_THRESHOLD})
  --cpu PCT        CPU usage warning threshold (default ${CPU_THRESHOLD})
  --mem PCT        memory usage warning threshold (default ${MEM_THRESHOLD})
  --crit PCT       any metric at or above this is critical (default ${CRIT_THRESHOLD})
  --log-file PATH  log file (default ${LOG_FILE}), rotated at 10 MB, 5 kept
  --json           print the report as JSON
  --help           show this help
  --version        show version

Exit codes: 0 healthy, 1 warning, 2 critical
EOF
}

die() { echo "Error: $*" >&2; exit 2; }

# Thresholds must be whole percentages; bash arithmetic would treat "abc" as 0
pct_arg() {
    if [[ ! "${2:-}" =~ ^[0-9]+$ ]] || (( $2 > 100 )); then
        die "$1 needs a number between 0 and 100"
    fi
    echo "$2"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --disk) DISK_THRESHOLD=$(pct_arg "$1" "${2:-}"); shift 2 ;;
            --cpu)  CPU_THRESHOLD=$(pct_arg "$1" "${2:-}"); shift 2 ;;
            --mem)  MEM_THRESHOLD=$(pct_arg "$1" "${2:-}"); shift 2 ;;
            --crit) CRIT_THRESHOLD=$(pct_arg "$1" "${2:-}"); shift 2 ;;
            --log-file) LOG_FILE="${2:?--log-file needs a path}"; shift 2 ;;
            --json) JSON_OUTPUT=true; shift ;;
            --help) usage; exit 0 ;;
            --version) echo "system_health.sh ${VERSION}"; exit 0 ;;
            *) usage >&2; die "unknown option '$1'" ;;
        esac
    done
}

rotate_log() {
    [[ -f "$LOG_FILE" ]] || return 0
    (( $(stat -c%s "$LOG_FILE") >= MAX_LOG_SIZE )) || return 0

    local i
    for (( i = MAX_ROTATIONS; i > 1; i-- )); do
        [[ -f "${LOG_FILE}.$(( i - 1 ))" ]] && mv "${LOG_FILE}.$(( i - 1 ))" "${LOG_FILE}.${i}"
    done
    mv "$LOG_FILE" "${LOG_FILE}.1"
    echo "rotated ${LOG_FILE}" >&2
}

# CPU busy % over a one second sample of /proc/stat
cpu_usage() {
    local u1 n1 s1 i1 w1 q1 sq1 u2 n2 s2 i2 w2 q2 sq2
    read -r _ u1 n1 s1 i1 w1 q1 sq1 _ < /proc/stat
    sleep 1
    read -r _ u2 n2 s2 i2 w2 q2 sq2 _ < /proc/stat
    local total=$(( (u2 + n2 + s2 + i2 + w2 + q2 + sq2) - (u1 + n1 + s1 + i1 + w1 + q1 + sq1) ))
    local idle=$(( i2 - i1 ))
    (( total > 0 )) && echo $(( (total - idle) * 100 / total )) || echo 0
}

mem_usage() {
    awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {printf "%d\n", (t-a)*100/t}' /proc/meminfo
}

# "mountpoint percent" per real filesystem; pseudo and read-only images skipped
disk_usage() {
    df -l --output=target,pcent \
        -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs -x iso9660 -x udf \
        | awk 'NR > 1 {sub(/%/, "", $2); print $1, $2}'
}

top_processes() {
    ps -eo pid,user,%mem,%cpu,comm --sort=-%mem --no-headers | head -n 5
}

# Compare a value with its threshold and record the result.
# Not called in $(...) on purpose: a subshell would lose the counters.
check() {
    local label="$1" value="$2" threshold="$3"
    if (( value >= CRIT_THRESHOLD )); then
        CRITICALS=$(( CRITICALS + 1 ))
        ALERTS+=("[CRITICAL] ${label}: ${value}% (critical at ${CRIT_THRESHOLD}%)")
    elif (( value >= threshold )); then
        WARNINGS=$(( WARNINGS + 1 ))
        ALERTS+=("[WARNING] ${label}: ${value}% (threshold ${threshold}%)")
    fi
}

json_escape() {
    local s="${1//\\/\\\\}"
    printf '%s' "${s//\"/\\\"}"
}

main() {
    parse_args "$@"
    rotate_log

    local timestamp host cpu mem load procs a
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    host=$(hostname)
    cpu=$(cpu_usage)
    mem=$(mem_usage)
    load=$(cut -d' ' -f1-3 /proc/loadavg)
    procs=$(top_processes)

    local -a mounts=() pcts=()
    local mount pct
    while read -r mount pct; do
        mounts+=("$mount")
        pcts+=("$pct")
    done < <(disk_usage)

    check "CPU" "$cpu" "$CPU_THRESHOLD"
    check "Memory" "$mem" "$MEM_THRESHOLD"
    local i
    for i in "${!mounts[@]}"; do
        check "Disk ${mounts[$i]}" "${pcts[$i]}" "$DISK_THRESHOLD"
    done

    local status=HEALTHY code=0
    if (( CRITICALS > 0 )); then status=CRITICAL; code=2
    elif (( WARNINGS > 0 )); then status=WARNING; code=1
    fi

    local report
    if [[ "$JSON_OUTPUT" == true ]]; then
        local disks="" alerts="" top="" sep p_pid p_user p_mem p_cpu p_cmd
        sep=""; for i in "${!mounts[@]}"; do
            disks+="${sep}{\"mount\":\"$(json_escape "${mounts[$i]}")\",\"usage_pct\":${pcts[$i]}}"; sep=","
        done
        sep=""; for a in "${ALERTS[@]}"; do alerts+="${sep}\"$(json_escape "$a")\""; sep=","; done
        sep=""; while read -r p_pid p_user p_mem p_cpu p_cmd; do
            top+="${sep}{\"pid\":${p_pid},\"user\":\"$(json_escape "$p_user")\",\"mem_pct\":${p_mem},\"cpu_pct\":${p_cpu},\"command\":\"$(json_escape "$p_cmd")\"}"; sep=","
        done <<< "$procs"
        report="{\"timestamp\":\"${timestamp}\",\"hostname\":\"${host}\",\"status\":\"${status}\",\"cpu_pct\":${cpu},\"memory_pct\":${mem},\"load_average\":\"${load}\",\"disk\":[${disks}],\"alerts\":[${alerts}],\"top_processes\":[${top}]}"
    else
        local disks_line=""
        for i in "${!mounts[@]}"; do disks_line+="${disks_line:+, }${mounts[$i]} ${pcts[$i]}%"; done
        report="== ${timestamp} ${host} status=${status}
CPU ${cpu}% | Memory ${mem}% | Load ${load}
Disk: ${disks_line}"
        for a in "${ALERTS[@]}"; do report+=$'\n'"$a"; done
        report+=$'\n'"Top processes by memory (PID USER %MEM %CPU COMMAND):"$'\n'"  ${procs//$'\n'/$'\n'  }"
    fi

    printf '%s\n' "$report" | tee -a "$LOG_FILE"
    exit "$code"
}

main "$@"
