#!/bin/bash
# ============================================
# Progress Helper - Loading, Bar, ETA, Stats
# ============================================

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
WHITE='\033[1;37m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

# Global
SCRIPT_START_TIME=${SCRIPT_START_TIME:-$(date +%s)}
CURRENT_PHASE=0
TOTAL_PHASES=11
SPINNER_PID=""
PHASE_START_TIME=0
STEP_START_TIME=0

# ═══════════════════════════════════════════
# SPINNER (Loading Animation)
# ═══════════════════════════════════════════
start_spinner() {
    local msg=$1
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
    [ -n "$SPINNER_PID" ] && kill $SPINNER_PID 2>/dev/null
    wait $SPINNER_PID 2>/dev/null
    SPINNER_PID=""
    printf "\r\033[K"
}

# ═══════════════════════════════════════════
# TIME HELPERS
# ═══════════════════════════════════════════
get_elapsed() { echo $(($(date +%s) - SCRIPT_START_TIME)); }

format_time() {
    local s=$1
    printf "%02d:%02d:%02d" $((s/3600)) $(((s%3600)/60)) $((s%60))
}

format_duration() {
    local s=$1
    if [ $s -lt 60 ]; then echo "${s}s"
    elif [ $s -lt 3600 ]; then echo "$((s/60))m $((s%60))s"
    else echo "$((s/3600))h $(((s%3600)/60))m"; fi
}

# ═══════════════════════════════════════════
# PROGRESS BAR
# ═══════════════════════════════════════════
draw_bar() {
    local cur=$1 total=$2 width=${3:-30}
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
    local num=$1 name=$2 est=$3
    CURRENT_PHASE=$num
    PHASE_START_TIME=$(date +%s)
    
    echo ""
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
    printf "${MAGENTA}║${NC} ${BOLD}PHASE %d/%d${NC}: ${WHITE}%-44s${NC}${MAGENTA}║${NC}\n" "$num" "$TOTAL_PHASES" "$name"
    printf "${MAGENTA}║${NC} ${DIM}⏱  Est: %-49s${NC}${MAGENTA}║${NC}\n" "$est"
    printf "${MAGENTA}║${NC} ${DIM}⏰ Elapsed: %-45s${NC}${MAGENTA}║${NC}\n" "$(format_time $(get_elapsed))"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
    
    echo -en "  ${CYAN}Overall: ${NC}"
    draw_bar $num $TOTAL_PHASES 40
    echo ""
}

phase_end() {
    local dur=$(($(date +%s) - PHASE_START_TIME))
    echo ""
    echo -e "  ${GREEN}✓ Phase $CURRENT_PHASE complete${NC} ${DIM}($(format_duration $dur))${NC}"
}

# ═══════════════════════════════════════════
# STEP LOGGER WITH SPINNER
# ═══════════════════════════════════════════
step_start() {
    STEP_START_TIME=$(date +%s)
    start_spinner "$1"
}

step_ok() {
    stop_spinner
    local msg=$1 count=$2
    local dur=$(($(date +%s) - STEP_START_TIME))
    if [ -n "$count" ]; then
        echo -e "  ${GREEN}✓${NC} $msg ${WHITE}→ $count${NC} ${DIM}($(format_duration $dur))${NC}"
    else
        echo -e "  ${GREEN}✓${NC} $msg ${DIM}($(format_duration $dur))${NC}"
    fi
}

step_warn() { stop_spinner; echo -e "  ${YELLOW}⚠${NC} $1"; }
step_fail() { stop_spinner; echo -e "  ${RED}✗${NC} $1"; }
step_info() { echo -e "  ${BLUE}ℹ${NC} $1"; }

# ═══════════════════════════════════════════
# LIVE PROGRESS (untuk task panjang)
# ═══════════════════════════════════════════
live_progress() {
    local file=$1 label=$2 max_time=${3:-300}
    local start=$(date +%s)
    local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local i=0
    
    while kill -0 $! 2>/dev/null; do
        local count=$(wc -l < "$file" 2>/dev/null || echo "0")
        local elapsed=$(($(date +%s) - start))
        local c="${chars:i++%${#chars}:1}"
        printf "\r  ${CYAN}%s${NC} %s: ${WHITE}%d${NC} ${DIM}[%s]${NC}  " \
            "$c" "$label" "$count" "$(format_duration $elapsed)"
        sleep 0.5
        
        [ $elapsed -gt $max_time ] && break
    done
    printf "\r\033[K"
}

# ═══════════════════════════════════════════
# STATS DISPLAY
# ═══════════════════════════════════════════
show_stats_inline() {
    local subs=$(wc -l < subdomains/all_subdomains.txt 2>/dev/null || echo "0")
    local live=$(wc -l < live/live_urls.txt 2>/dev/null || echo "0")
    local urls=$(wc -l < urls/all_urls_dedup.txt 2>/dev/null || echo "0")
    local js=$(wc -l < js/js_live.txt 2>/dev/null || echo "0")
    
    echo -e "${DIM}  ─────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}📊 Stats:${NC} Subs:${WHITE}$subs${NC} | Live:${WHITE}$live${NC} | URLs:${WHITE}$urls${NC} | JS:${WHITE}$js${NC}"
    echo -e "${DIM}  ─────────────────────────────────────────${NC}"
}

# ═══════════════════════════════════════════
# TIPS ROTATOR (Edukasi sambil nunggu)
# ═══════════════════════════════════════════
TIPS=(
    "💡 Jangan lupa cek scope di HackerOne sebelum hunt!"
    "💡 Subdomain 'dev-*' dan 'staging-*' sering bugnya parah"
    "💡 Baca report HackerOne lama target untuk tau pattern"
    "💡 .js file sering leak API key - pasti review manual"
    "💡 403 Forbidden? Coba bypass dengan /, /., /;x"
    "💡 CORS misconfig bayaran $500-$2000 di target besar"
    "💡 Exposed .git = full source code = JACKPOT!"
    "💡 Subdomain takeover = gampang nemu, bayaran tinggi"
    "💡 Combine gau + waybackurls untuk endpoint historis"
    "💡 Pakai 'uro' untuk dedup URL biar ga buang waktu"
    "💡 Screenshot tool hemat waktu visual recon"
    "💡 Nuclei severity high/critical prioritas testing"
    "💡 IDOR bug sering miss tools - WAJIB manual test"
    "💡 Check /.env, /.git/config, /backup.sql - sering bocor"
    "💡 Jangan scan out-of-scope - bisa kena ban program"
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
    local elapsed=$(get_elapsed)
    if [ $CURRENT_PHASE -eq 0 ]; then
        echo "calculating..."
        return
    fi
    local avg=$((elapsed / CURRENT_PHASE))
    local remaining=$((TOTAL_PHASES - CURRENT_PHASE))
    local eta=$((avg * remaining))
    echo "$(format_duration $eta)"
}

# ═══════════════════════════════════════════
# BANNER
# ═══════════════════════════════════════════
show_banner() {
    local target=$1 mode=$2
    echo -e "${CYAN}"
    cat << "EOF"
    ____              __  __            __           
   / __ )__  ______ _/ / / /_  ______  / /____  _____
  / __  / / / / __ `/ /_/ / / / / __ \/ __/ _ \/ ___/
 / /_/ / /_/ / /_/ / __  / /_/ / / / / /_/  __/ /    
/_____/\__,_/\__, /_/ /_/\__,_/_/ /_/\__/\___/_/     
            /____/       RECON v2.1                   
EOF
    echo -e "${NC}"
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
    printf "${MAGENTA}║${NC}  🎯 Target : ${WHITE}%-44s${NC}${MAGENTA}║${NC}\n" "$target"
    printf "${MAGENTA}║${NC}  ⚙  Mode   : ${YELLOW}%-44s${NC}${MAGENTA}║${NC}\n" "$mode"
    printf "${MAGENTA}║${NC}  ⏰ Start  : ${DIM}%-44s${NC}${MAGENTA}║${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ═══════════════════════════════════════════
# FINAL SUMMARY
# ═══════════════════════════════════════════
show_final_summary() {
    local total_time=$(get_elapsed)
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           🎉 RECON COMPLETE! 🎉                          ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    printf "  ${BOLD}⏱  Total Duration:${NC} ${WHITE}%s${NC}\n" "$(format_duration $total_time)"
    printf "  ${BOLD}📁 Output Folder :${NC} ${WHITE}%s${NC}\n" "$(pwd)"
    echo ""
}

# Cleanup saat CTRL+C
trap 'stop_spinner; echo ""; exit 130' INT TERM
