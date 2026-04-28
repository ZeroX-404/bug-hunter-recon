#!/bin/bash
# ============================================
# Progress Helper - Loading, Bar, ETA, Stats
# Version: 2.3 (fixed + enhanced)
# ============================================

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
WHITE='\033[1;37m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

# Global
SCRIPT_START_TIME=${SCRIPT_START_TIME:-$(date +%s)}
CURRENT_PHASE=0
TOTAL_PHASES=13
SPINNER_PID=""
PHASE_START_TIME=0
STEP_START_TIME=0
LOG_FILE=${LOG_FILE:-""}
DISCORD_WEBHOOK=${DISCORD_WEBHOOK:-""}

# ═══════════════════════════════════════════
# LOG TO FILE (opsional)
# ═══════════════════════════════════════════
_log() {
    if [ -n "$LOG_FILE" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
    fi
}

# ═══════════════════════════════════════════
# SPINNER (Loading Animation)
# ═══════════════════════════════════════════
start_spinner() {
    local msg=${1:-"Processing..."}
    (
        local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
        local i=0
        while true; do
            local c="${chars:i++%${#chars}:1}"
            printf "\r  ${CYAN}%s${NC} %s " "$c" "$msg"
            sleep 0.1
        done
    ) &
    SPINNER_PID=$!
    disown 2>/dev/null
}

stop_spinner() {
    if [ -n "${SPINNER_PID:-}" ]; then
        kill "$SPINNER_PID" 2>/dev/null
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
    fi
    printf "\r\033[K"
}

# ═══════════════════════════════════════════
# TIME HELPERS
# ═══════════════════════════════════════════
get_elapsed() { echo $(($(date +%s) - SCRIPT_START_TIME)); }

format_time() {
    local s=${1:-0}
    printf "%02d:%02d:%02d" $((s/3600)) $(((s%3600)/60)) $((s%60))
}

format_duration() {
    local s=${1:-0}
    if [ "$s" -lt 60 ]; then echo "${s}s"
    elif [ "$s" -lt 3600 ]; then echo "$((s/60))m $((s%60))s"
    else echo "$((s/3600))h $(((s%3600)/60))m"; fi
}

# ═══════════════════════════════════════════
# PROGRESS BAR
# ═══════════════════════════════════════════
draw_bar() {
    local cur=${1:-0} total=${2:-1} width=${3:-30}
    [ "$total" -eq 0 ] && total=1   # hindari division by zero
    local percent=$((cur * 100 / total))
    local filled=$((cur * width / total))
    local empty=$((width - filled))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    echo "${bar} ${percent}%"
}

# ═══════════════════════════════════════════
# PHASE HEADER
# ═══════════════════════════════════════════
phase_start() {
    local num=${1:-0} name=${2:-"Unknown"} est=${3:-"?"}
    CURRENT_PHASE=$num
    PHASE_START_TIME=$(date +%s)

    _log "=== PHASE $num/$TOTAL_PHASES: $name (est: $est) ==="

    echo ""
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
    printf "${MAGENTA}║${NC} ${BOLD}PHASE %d/%d${NC}: ${WHITE}%-44s${NC}${MAGENTA}║${NC}\n" "$num" "$TOTAL_PHASES" "$name"
    printf "${MAGENTA}║${NC} ${DIM}⏱  Est: %-49s${NC}${MAGENTA}║${NC}\n" "$est"
    printf "${MAGENTA}║${NC} ${DIM}⏰ Elapsed: %-45s${NC}${MAGENTA}║${NC}\n" "$(format_time "$(get_elapsed)")"
    printf "${MAGENTA}║${NC} ${DIM}⏳ ETA   : %-45s${NC}${MAGENTA}║${NC}\n" "$(show_eta)"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"

    echo -en "  ${CYAN}Overall: ${NC}"
    draw_bar "$num" "$TOTAL_PHASES" 40
    echo ""
}

phase_end() {
    local dur=$(($(date +%s) - PHASE_START_TIME))
    _log "Phase $CURRENT_PHASE done in $(format_duration $dur)"
    echo ""
    echo -e "  ${GREEN}✓ Phase $CURRENT_PHASE complete${NC} ${DIM}($(format_duration $dur))${NC}"
}

# ═══════════════════════════════════════════
# PHASE SUMMARY (ringkasan per phase)
# ═══════════════════════════════════════════
show_phase_summary() {
    local phase_name=${1:-"Phase $CURRENT_PHASE"}
    local found=${2:-0}
    local tool=${3:-""}
    local dur=$(($(date +%s) - PHASE_START_TIME))

    echo ""
    echo -e "  ${CYAN}┌─ Summary: $phase_name ─┐${NC}"
    printf "  ${CYAN}│${NC} Found  : ${WHITE}%-35s${NC}${CYAN}│${NC}\n" "$found item(s)"
    [ -n "$tool" ] && printf "  ${CYAN}│${NC} Tool   : ${WHITE}%-35s${NC}${CYAN}│${NC}\n" "$tool"
    printf "  ${CYAN}│${NC} Time   : ${WHITE}%-35s${NC}${CYAN}│${NC}\n" "$(format_duration $dur)"
    echo -e "  ${CYAN}└──────────────────────────────────────────┘${NC}"
    _log "[$phase_name] found=$found tool=$tool duration=$(format_duration $dur)"
}

# ═══════════════════════════════════════════
# STEP LOGGER WITH SPINNER
# ═══════════════════════════════════════════
step_start() {
    STEP_START_TIME=$(date +%s)
    start_spinner "${1:-Running...}"
    _log "  > START: ${1:-}"
}

step_ok() {
    stop_spinner
    local msg=${1:-"Done"} count=${2:-""}
    local dur=$(($(date +%s) - STEP_START_TIME))
    if [ -n "$count" ]; then
        echo -e "  ${GREEN}✓${NC} $msg ${WHITE}→ $count${NC} ${DIM}($(format_duration $dur))${NC}"
        _log "  > OK: $msg → $count ($(format_duration $dur))"
    else
        echo -e "  ${GREEN}✓${NC} $msg ${DIM}($(format_duration $dur))${NC}"
        _log "  > OK: $msg ($(format_duration $dur))"
    fi
}

step_warn() {
    stop_spinner
    echo -e "  ${YELLOW}⚠${NC} ${1:-Warning}"
    _log "  > WARN: ${1:-}"
}

step_fail() {
    stop_spinner
    echo -e "  ${RED}✗${NC} ${1:-Failed}"
    _log "  > FAIL: ${1:-}"
}

step_info() {
    echo -e "  ${BLUE}ℹ${NC} ${1:-}"
    _log "  > INFO: ${1:-}"
}

# ═══════════════════════════════════════════
# CHECK TOOL AVAILABILITY
# ═══════════════════════════════════════════
check_tool() {
    local tool=$1
    local required=${2:-"false"}   # "true" = wajib ada, exit kalau tidak
    if command -v "$tool" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $tool ${DIM}($(command -v "$tool"))${NC}"
        return 0
    else
        if [ "$required" = "true" ]; then
            echo -e "  ${RED}✗${NC} $tool ${RED}[REQUIRED - tidak ditemukan!]${NC}"
            return 1
        else
            echo -e "  ${YELLOW}⚠${NC} $tool ${YELLOW}[optional - tidak ditemukan]${NC}"
            return 1
        fi
    fi
}

check_all_tools() {
    echo -e "\n${BOLD}  🔧 Tool Check:${NC}"
    echo -e "${DIM}  ──────────────────────────────────────────${NC}"

    local failed=0

    # Required tools
    for t in subfinder httpx dnsx nuclei jq curl; do
        check_tool "$t" "true" || ((failed++)) || true
    done

    echo -e "${DIM}  ──────────────────────────────────────────${NC}"

    # Optional tools
    for t in amass assetfinder katana gau waybackurls waymore ffuf dalfox naabu trufflehog notify uro anew; do
        check_tool "$t" "false" || true
    done

    echo -e "${DIM}  ──────────────────────────────────────────${NC}"

    if [ "$failed" -gt 0 ]; then
        echo -e "  ${RED}✗ $failed required tool tidak ditemukan. Install dulu!${NC}"
        return 1
    else
        echo -e "  ${GREEN}✓ Semua required tool siap!${NC}"
        return 0
    fi
}

# ═══════════════════════════════════════════
# LIVE PROGRESS (untuk task panjang)
# ═══════════════════════════════════════════
live_progress() {
    local file=${1:-/dev/null} label=${2:-"Processing"} max_time=${3:-300}
    local start=$(date +%s)
    local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local i=0
    local bg_pid=${4:-""}   # PID background process yang ditunggu (opsional)

    # Gunakan PID yang diberikan, atau $! kalau tidak ada
    local watch_pid="${bg_pid:-${!:-""}}"

    while true; do
        # Cek apakah process masih jalan
        if [ -n "$watch_pid" ] && ! kill -0 "$watch_pid" 2>/dev/null; then
            break
        fi

        local count
        count=$(wc -l < "$file" 2>/dev/null || echo "0")
        local elapsed=$(($(date +%s) - start))
        local c="${chars:i++%${#chars}:1}"
        printf "\r  ${CYAN}%s${NC} %s: ${WHITE}%d${NC} ${DIM}[%s]${NC}  " \
            "$c" "$label" "$count" "$(format_duration $elapsed)"
        sleep 0.5

        [ "$elapsed" -gt "$max_time" ] && break
    done
    printf "\r\033[K"
}

# ═══════════════════════════════════════════
# STATS DISPLAY
# ═══════════════════════════════════════════
show_stats_inline() {
    local subs live urls js vulns
    subs=$([ -f subdomains/all_subdomains.txt ] && wc -l < subdomains/all_subdomains.txt || echo "0")
    live=$([ -f live/live_urls.txt ] && wc -l < live/live_urls.txt || echo "0")
    urls=$([ -f urls/all_urls_dedup.txt ] && wc -l < urls/all_urls_dedup.txt || echo "0")
    js=$([ -f js/js_live.txt ] && wc -l < js/js_live.txt || echo "0")
    # Aggregate semua hasil nuclei (bukan nuclei/results.txt yang tidak ada)
    vulns=$(grep -ch "\[critical\]\|\[high\]\|\[medium\]\|\[low\]\|\[info\]" nuclei/*.txt 2>/dev/null | awk '{s+=$1}END{print s+0}')

    echo -e "${DIM}  ─────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}📊 Stats:${NC} Subs:${WHITE}$subs${NC} | Live:${WHITE}$live${NC} | URLs:${WHITE}$urls${NC} | JS:${WHITE}$js${NC} | Vulns:${WHITE}$vulns${NC}"
    echo -e "${DIM}  ─────────────────────────────────────────${NC}"
}

# ═══════════════════════════════════════════
# DISCORD NOTIFY (opsional)
# Set DISCORD_WEBHOOK di env untuk aktifkan
# ═══════════════════════════════════════════
show_notify() {
    local title=${1:-"Recon Update"} msg=${2:-""} color=${3:-"3066993"}
    [ -z "$DISCORD_WEBHOOK" ] && return 0   # skip kalau webhook tidak diset

    local payload
    payload=$(jq -n \
        --arg title "$title" \
        --arg desc "$msg" \
        --arg color "$color" \
        '{"embeds":[{"title":$title,"description":$desc,"color":($color|tonumber)}]}')

    curl -s -X POST "$DISCORD_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "$payload" &>/dev/null || true

    _log "Discord notify sent: $title - $msg"
}

# Shortcut untuk notify critical finding
notify_critical() {
    local target=${1:-"?"} finding=${2:-"?"}
    show_notify "🚨 CRITICAL FINDING!" \
        "**Target:** $target\n**Finding:** $finding\n**Time:** $(date '+%H:%M:%S')" \
        "15158332"   # warna merah
}

# Notify phase selesai
notify_phase_done() {
    local phase=${1:-"?"} name=${2:-"?"} dur=${3:-"?"}
    show_notify "✅ Phase $phase Done" \
        "**Phase:** $name\n**Duration:** $dur\n**ETA:** $(show_eta)" \
        "3066993"    # warna hijau
}

# ═══════════════════════════════════════════
# TIPS ROTATOR (Edukasi sambil nunggu)
# FIX: semua $ dalam string di-escape supaya tidak
# dievaluasi bash saat sourced dengan set -u
# ═══════════════════════════════════════════
TIPS=(
    "💡 Jangan lupa cek scope di HackerOne sebelum hunt!"
    "💡 Subdomain 'dev-*' dan 'staging-*' sering bugnya parah"
    "💡 Baca report HackerOne lama target untuk tau pattern"
    "💡 .js file sering leak API key - pasti review manual"
    "💡 403 Forbidden? Coba bypass dengan /, /., /;x"
    '💡 CORS misconfig bayaran $500-$2000 di target besar'
    "💡 Exposed .git = full source code = JACKPOT!"
    "💡 Subdomain takeover = gampang nemu, bayaran tinggi"
    "💡 Combine gau + waybackurls untuk endpoint historis"
    "💡 Pakai 'uro' untuk dedup URL biar ga buang waktu"
    "💡 Screenshot tool hemat waktu visual recon"
    "💡 Nuclei severity high/critical prioritas testing"
    "💡 IDOR bug sering miss tools - WAJIB manual test"
    "💡 Check /.env, /.git/config, /backup.sql - sering bocor"
    "💡 Jangan scan out-of-scope - bisa kena ban program"
    "💡 ffuf untuk directory bruteforce - gap terbesar kebanyakan script"
    "💡 waymore > waybackurls: agregasi 4 sumber sekaligus"
    "💡 dalfox file params/xss_candidates.txt untuk XSS otomatis"
    "💡 notify dari ProjectDiscovery: dapat ping Discord/Slack saat nemu critical"
    "💡 nuclei -etags oast,fuzz untuk skip template yang butuh interactsh"
    '💡 Scope perlu dikonfirmasi lagi? Bounty rata-rata $500-$5000 per critical'
    "💡 Katana > hakrawler: aktif crawl JS, bisa headless browser"
    "💡 dnsx -resp untuk lihat DNS record lengkap, bukan cuma resolve"
    "💡 naabu -top-ports 1000 lebih safe dari full scan untuk bug bounty"
    "💡 Trufflehog v3: scan JS file untuk secret leak otomatis"
)

show_random_tip() {
    local idx=$((RANDOM % ${#TIPS[@]}))
    echo ""
    echo -e "${DIM}${TIPS[$idx]}${NC}"
    echo ""
}

# ═══════════════════════════════════════════
# ETA CALCULATOR
# ═══════════════════════════════════════════
show_eta() {
    local elapsed
    elapsed=$(get_elapsed)
    if [ "${CURRENT_PHASE:-0}" -le 0 ]; then
        echo "calculating..."
        return
    fi
    local avg=$((elapsed / CURRENT_PHASE))
    local remaining=$((TOTAL_PHASES - CURRENT_PHASE))
    local eta=$((avg * remaining))
    echo "~$(format_duration $eta)"
}

# ═══════════════════════════════════════════
# BANNER
# ═══════════════════════════════════════════
show_banner() {
    local target=${1:-"unknown"} mode=${2:-"full"}
    echo -e "${CYAN}"
    cat << "EOF"
    ____              __  __            __           
   / __ )__  ______ _/ / / /_  ______  / /____  _____
  / __  / / / / __ `/ /_/ / / / / __ \/ __/ _ \/ ___/
 / /_/ / /_/ / /_/ / __  / /_/ / / / / /_/  __/ /    
/_____/\__,_/\__, /_/ /_/\__,_/_/ /_/\__/\___/_/     
            /____/       RECON v2.3                   
EOF
    echo -e "${NC}"
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
    printf "${MAGENTA}║${NC}  🎯 Target : ${WHITE}%-44s${NC}${MAGENTA}║${NC}\n" "$target"
    printf "${MAGENTA}║${NC}  ⚙  Mode   : ${YELLOW}%-44s${NC}${MAGENTA}║${NC}\n" "$mode"
    printf "${MAGENTA}║${NC}  ⏰ Start  : ${DIM}%-44s${NC}${MAGENTA}║${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')"
    [ -n "$LOG_FILE" ] && \
        printf "${MAGENTA}║${NC}  📝 Log    : ${DIM}%-44s${NC}${MAGENTA}║${NC}\n" "$LOG_FILE"
    [ -n "$DISCORD_WEBHOOK" ] && \
        printf "${MAGENTA}║${NC}  🔔 Discord: ${GREEN}%-44s${NC}${MAGENTA}║${NC}\n" "Enabled"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    _log "=== RECON START: target=$target mode=$mode ==="
}

# ═══════════════════════════════════════════
# FINAL SUMMARY
# ═══════════════════════════════════════════
show_final_summary() {
    local total_time
    total_time=$(get_elapsed)

    local subs live urls js vulns critical high
    subs=$(wc -l < subdomains/all_subdomains.txt 2>/dev/null || echo "0")
    live=$(wc -l < live/live_urls.txt 2>/dev/null || echo "0")
    urls=$(wc -l < urls/all_urls_dedup.txt 2>/dev/null || echo "0")
    js=$(wc -l < js/js_live.txt 2>/dev/null || echo "0")
    vulns=$(grep -ch "." nuclei/*.txt 2>/dev/null | awk '{s+=$1}END{print s+0}')
    critical=$(grep -h '\[critical\]' nuclei/*.txt 2>/dev/null | wc -l || echo "0")
    high=$(grep -h '\[high\]' nuclei/*.txt 2>/dev/null | wc -l || echo "0")

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           🎉 RECON COMPLETE! 🎉                          ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    printf "  ${BOLD}⏱  Total Duration :${NC} ${WHITE}%s${NC}\n" "$(format_duration $total_time)"
    printf "  ${BOLD}📁 Output Folder  :${NC} ${WHITE}%s${NC}\n" "$(pwd)"
    echo ""
    echo -e "  ${BOLD}📊 Final Stats:${NC}"
    printf "  %-18s ${WHITE}%s${NC}\n" "Subdomains:"   "$subs"
    printf "  %-18s ${WHITE}%s${NC}\n" "Live Hosts:"   "$live"
    printf "  %-18s ${WHITE}%s${NC}\n" "URLs:"         "$urls"
    printf "  %-18s ${WHITE}%s${NC}\n" "JS Files:"     "$js"
    printf "  %-18s ${WHITE}%s${NC}\n" "Vulnerabilities:" "$vulns"
    printf "  %-18s ${RED}%s${NC}\n"   "  Critical:"   "$critical"
    printf "  %-18s ${YELLOW}%s${NC}\n" "  High:"      "$high"
    echo ""

    _log "=== RECON DONE: duration=$(format_duration $total_time) subs=$subs live=$live vulns=$vulns critical=$critical ==="

    # Discord notify saat selesai
    show_notify "🏁 Recon Complete!" \
        "**Duration:** $(format_duration $total_time)\n**Subs:** $subs | **Live:** $live\n**Vulns:** $vulns (**Critical:** $critical, **High:** $high)" \
        "3447003"
}

# ═══════════════════════════════════════════
# CLEANUP (dipanggil trap dari recon.sh)
# ═══════════════════════════════════════════
progress_cleanup() {
    stop_spinner
    _log "=== RECON INTERRUPTED ==="
}

# Trap default (override di recon.sh kalau perlu)
trap 'progress_cleanup; echo ""; exit 130' INT TERM
