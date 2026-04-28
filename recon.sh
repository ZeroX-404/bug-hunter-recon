#!/bin/bash
# ============================================================
# Bug Hunter Recon v2.2 - DENGAN PROGRESS INDICATOR
# ============================================================

set -uo pipefail   # -u: error on unset var, -o pipefail: pipe gagal = error
                    # Sengaja tidak pakai -e agar tool recon yang gagal tidak
                    # stop script (subfinder kosong bukan berarti error fatal)

# Load API keys
[ -f ~/.config/recon/.env ] && source ~/.config/recon/.env

# Load progress helper
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/utils/progress.sh"

SCRIPT_START_TIME=$(date +%s)
VERSION="2.3"

# ═══════════════════════════════════════════
# HELP
# ═══════════════════════════════════════════
show_help() {
    show_banner "Help Menu" "Info"
    echo -e "${CYAN}Usage:${NC}"
    echo -e "  ${YELLOW}./recon.sh -d <domain>${NC}     # Single domain"
    echo -e "  ${YELLOW}./recon.sh -w <domain>${NC}     # Wildcard mode"
    echo -e "  ${YELLOW}./recon.sh -l <list.txt>${NC}   # List of domains"
    echo ""
    echo -e "${CYAN}Options:${NC}"
    echo -e "  ${GREEN}-d${NC}    Single domain mode"
    echo -e "  ${GREEN}-w${NC}    Wildcard mode (deep enum)"
    echo -e "  ${GREEN}-l${NC}    List file"
    echo -e "  ${GREEN}-o${NC}    Output directory"
    echo -e "  ${GREEN}-s${NC}    Quick mode (skip heavy scans)"
    echo -e "  ${GREEN}-v${NC}    Verbose mode (lihat error dari tools)"
    echo -e "  ${GREEN}-x${NC}    Exclude file (out-of-scope)"
    echo -e "  ${GREEN}-h${NC}    Show this help"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo -e "  ${YELLOW}./recon.sh -w target.com${NC}"
    echo -e "  ${YELLOW}./recon.sh -d api.target.com -s${NC}"
    echo -e "  ${YELLOW}./recon.sh -w target.com -x oos.txt${NC}"
    exit 0
}

# ═══════════════════════════════════════════
# PARSE ARGS
# ═══════════════════════════════════════════
MODE=""; TARGET=""; OUTDIR=""; QUICK=0; EXCLUDE=""; VERBOSE=0

while getopts "d:w:l:o:x:svh" opt; do
    case $opt in
        d) MODE="single"; TARGET="$OPTARG" ;;
        w) MODE="wildcard"; TARGET="$OPTARG" ;;
        l) MODE="list"; TARGET="$OPTARG" ;;
        o) OUTDIR="$OPTARG" ;;
        s) QUICK=1 ;;
        v) VERBOSE=1 ;;
        x) EXCLUDE="$OPTARG" ;;
        h) show_help ;;
        *) show_help ;;
    esac
done

[ -z "$MODE" ] && show_help

# ═══════════════════════════════════════════
# DEPENDENCY CHECK
# ═══════════════════════════════════════════
check_deps() {
    local missing=()
    local required_tools=(subfinder httpx dnsx nuclei curl jq)
    local optional_tools=(assetfinder chaos puredns alterx naabu katana gau waybackurls hakrawler uro gf arjun subzy gowitness trufflehog mantra github-subdomains)

    echo -e "${CYAN}[*] Checking dependencies...${NC}"
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}[!] Missing REQUIRED tools: ${missing[*]}${NC}"
        echo -e "${RED}[!] Install dulu sebelum lanjut.${NC}"
        exit 1
    fi

    local warn_missing=()
    for tool in "${optional_tools[@]}"; do
        command -v "$tool" &>/dev/null || warn_missing+=("$tool")
    done
    if [ ${#warn_missing[@]} -gt 0 ]; then
        echo -e "${YELLOW}[~] Optional tools tidak ditemukan (beberapa phase akan di-skip): ${warn_missing[*]}${NC}"
    fi
    echo -e "${GREEN}[+] Core dependencies OK${NC}"
}

check_deps

# ═══════════════════════════════════════════
# CLEANUP HANDLER
# ═══════════════════════════════════════════
CLEANUP_DONE=0
cleanup() {
    [ "$CLEANUP_DONE" -eq 1 ] && return
    CLEANUP_DONE=1
    echo -e "\n${YELLOW}[~] Cleaning up background processes...${NC}"
    jobs -p | xargs -r kill 2>"$DEVNULL" || true
    rm -f /tmp/sensitive_paths.txt /tmp/arjun_input.txt 2>"$DEVNULL" || true
    echo -e "${YELLOW}[~] Cleanup done.${NC}"
}
trap cleanup EXIT INT TERM

# ═══════════════════════════════════════════
# PHASE RESUME HELPERS
# ═══════════════════════════════════════════
# Simpan checkpoint per phase supaya bisa resume kalau crash
CHECKPOINT_DIR=""   # Di-set setelah OUTDIR tersedia

phase_done() {
    local phase_num=$1
    [ -n "$CHECKPOINT_DIR" ] && touch "${CHECKPOINT_DIR}/.phase_${phase_num}_done"
}

phase_is_done() {
    local phase_num=$1
    [ -n "$CHECKPOINT_DIR" ] && [ -f "${CHECKPOINT_DIR}/.phase_${phase_num}_done" ]
}

# ═══════════════════════════════════════════
# SETUP
# ═══════════════════════════════════════════
DATE=$(date +%Y%m%d_%H%M%S)
DOMAIN_NAME=$(echo "$TARGET" | sed 's|https\?://||' | sed 's|/.*||' | tr '/' '_')
[ -z "$OUTDIR" ] && OUTDIR="output/${DOMAIN_NAME}_${DATE}"

mkdir -p "$OUTDIR"/{subdomains,live,urls,js,secrets,nuclei,takeover,ports,params,screenshots,final,logs,checkpoints,ffuf}
cd "$OUTDIR"
CHECKPOINT_DIR="$(pwd)/checkpoints"

LOG_FILE="logs/recon.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Verbose: kalau -v dipass, tampilkan stderr tool; kalau tidak, buang
[ "$VERBOSE" -eq 1 ] && DEVNULL="/dev/stderr" || DEVNULL="/dev/null"

# Resolvers file — diset di sini supaya tersedia di semua phase
RESOLVERS_FILE="${HOME}/wordlists/resolvers.txt"
if [ ! -f "$RESOLVERS_FILE" ]; then
    RESOLVERS_FILE="/tmp/recon_resolvers_fallback.txt"
    printf "8.8.8.8\n8.8.4.4\n1.1.1.1\n1.0.0.1\n9.9.9.9\n208.67.222.222\n" > "$RESOLVERS_FILE"
fi

MODE_DISPLAY="$MODE"
[ $QUICK -eq 1 ] && MODE_DISPLAY="$MODE (quick)"

show_banner "$TARGET" "$MODE_DISPLAY"

echo -e "${DIM}📁 Output: $OUTDIR${NC}"
echo -e "${DIM}📝 Log: $OUTDIR/$LOG_FILE${NC}"
show_random_tip

# ═══════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════
count_lines() {
    [ -f "$1" ] && wc -l < "$1" 2>"$DEVNULL" || echo "0"
}

apply_scope_filter() {
    local input=$1 output=$2
    if [ -n "$EXCLUDE" ] && [ -f "../../$EXCLUDE" ]; then
        grep -vFf "../../$EXCLUDE" "$input" > "$output"
        step_warn "Scope filter applied"
    else
        cp "$input" "$output"
    fi
}

# ═══════════════════════════════════════════════════════════════
# PHASE 1: SUBDOMAIN ENUMERATION
# ═══════════════════════════════════════════════════════════════
phase_start 1 "SUBDOMAIN ENUMERATION" "15-45 menit"

if [ "$MODE" = "single" ]; then
    step_start "Single domain mode (no subdomain enum)..."
    echo "$TARGET" > subdomains/all_subdomains.txt
    step_ok "Single domain mode"
else
    step_start "Running Subfinder (multi-source)..."
    subfinder -d "$TARGET" -all -silent -o subdomains/subfinder.txt 2>"$DEVNULL"
    step_ok "Subfinder" "$(count_lines subdomains/subfinder.txt)"

    step_start "Running Assetfinder..."
    assetfinder --subs-only "$TARGET" 2>"$DEVNULL" > subdomains/assetfinder.txt
    step_ok "Assetfinder" "$(count_lines subdomains/assetfinder.txt)"

    step_start "Fetching from crt.sh..."
    curl -s "https://crt.sh/?q=%25.${TARGET}&output=json" 2>"$DEVNULL" | \
        jq -r '.[].name_value' 2>"$DEVNULL" | sed 's/\*\.//g' | \
        grep -E "\.${TARGET}$" | sort -u > subdomains/crtsh.txt
    step_ok "crt.sh" "$(count_lines subdomains/crtsh.txt)"

    if [ -n "$CHAOS_KEY" ]; then
        step_start "Querying Chaos database..."
        chaos -d "$TARGET" -silent -o subdomains/chaos.txt 2>"$DEVNULL"
        step_ok "Chaos" "$(count_lines subdomains/chaos.txt)"
    else
        step_info "Chaos skipped (no API key)"
    fi

    if [ -n "$GITHUB_TOKEN" ]; then
        step_info "GitHub search (bisa 10-30 menit untuk target besar)..."
        step_start "Searching GitHub for subdomains..."
        timeout 1800 github-subdomains -d "$TARGET" -t "$GITHUB_TOKEN" -o subdomains/github.txt 2>"$DEVNULL" &
        GH_PID=$!
        
        # Live counter
        while kill -0 $GH_PID 2>"$DEVNULL"; do
            count=$(count_lines subdomains/github.txt)
            printf "\r  ${CYAN}⠋${NC} GitHub searching... ${WHITE}%d found${NC}     " "$count"
            sleep 2
        done
        wait $GH_PID
        stop_spinner
        step_ok "GitHub subdomains" "$(count_lines subdomains/github.txt)"
    else
        step_info "GitHub skipped (no token)"
    fi

    # Active (wildcard only, not quick mode)
    if [ "$MODE" = "wildcard" ] && [ $QUICK -eq 0 ]; then
        if [ -f ~/wordlists/best-dns-wordlist.txt ]; then
            step_start "DNS Bruteforce (puredns)..."
            puredns bruteforce ~/wordlists/best-dns-wordlist.txt "$TARGET" \
                -r "$RESOLVERS_FILE" \
                --rate-limit 500 \
                -q > subdomains/bruteforce.txt 2>"$DEVNULL"
            step_ok "Bruteforce" "$(count_lines subdomains/bruteforce.txt)"
        fi

        # Optimized permutation (batasi untuk target besar)
        TOTAL_BASE=$(cat subdomains/*.txt 2>"$DEVNULL" | sort -u | wc -l)
        if [ $TOTAL_BASE -gt 1000 ]; then
            step_info "Target besar ($TOTAL_BASE subs) - limit permutation to top 500"
            PERM_INPUT=$(cat subdomains/*.txt 2>"$DEVNULL" | sort -u | head -500)
        else
            PERM_INPUT=$(cat subdomains/*.txt 2>"$DEVNULL" | sort -u)
        fi
        
        step_start "Permutation generator (alterx)..."
        echo "$PERM_INPUT" | alterx -silent -limit 50000 2>"$DEVNULL" > subdomains/alterx_generated.txt
        step_ok "Alterx generated" "$(count_lines subdomains/alterx_generated.txt)"
        
        step_start "Resolving permutations (dnsx)..."
        dnsx -l subdomains/alterx_generated.txt -silent \
            -r "$RESOLVERS_FILE" \
            -t 100 -rl 500 \
            -o subdomains/permutation.txt 2>"$DEVNULL"
                step_ok "Permutation valid" "$(count_lines subdomains/permutation.txt)"
    fi

    # Merge & Resolve
    step_start "Merging all sources..."
    cat subdomains/*.txt 2>"$DEVNULL" | sort -u > subdomains/raw_all.txt
    step_ok "Total raw" "$(count_lines subdomains/raw_all.txt)"
    
    step_start "DNS Resolution (final validation)..."
    dnsx -l subdomains/raw_all.txt -silent -a -resp \
        -r "$RESOLVERS_FILE" \
        -t 100 -rl 500 2>"$DEVNULL" | \
        awk '{print $1}' | sort -u > subdomains/resolved.txt
    step_ok "DNS resolved" "$(count_lines subdomains/resolved.txt)"

    apply_scope_filter subdomains/resolved.txt subdomains/all_subdomains.txt
fi

TOTAL_SUB=$(count_lines subdomains/all_subdomains.txt)
step_info "📌 FINAL: ${WHITE}$TOTAL_SUB${NC} unique in-scope subdomains"
phase_done 1
phase_end

show_random_tip

# ═══════════════════════════════════════════════════════════════
# PHASE 2: LIVE HOST DETECTION
# ═══════════════════════════════════════════════════════════════
phase_start 2 "LIVE HOST DETECTION" "10-30 menit"

step_start "HTTPX probing (multi-port: 80,443,8080,8443,3000,5000,8000,8888,9000,9090)..."
httpx -l subdomains/all_subdomains.txt \
    -ports 80,443,8080,8443,8000,8888,3000,5000,9000,9090 \
    -threads 50 -rate-limit 100 -timeout 10 \
    -silent -status-code -title -tech-detect -server \
    -content-length -follow-redirects \
    -json -o live/httpx_full.json 2>"$DEVNULL" &
HTTPX_PID=$!

# Live counter
while kill -0 $HTTPX_PID 2>"$DEVNULL"; do
    count=$(count_lines live/httpx_full.json)
    printf "\r  ${CYAN}⠋${NC} Probing live hosts... ${WHITE}%d found${NC}     " "$count"
    sleep 2
done
wait $HTTPX_PID
stop_spinner
step_ok "HTTPX probe" "$(count_lines live/httpx_full.json)"

step_start "Extracting URLs & categorizing..."
cat live/httpx_full.json 2>"$DEVNULL" | jq -r '.url' 2>"$DEVNULL" | sort -u > live/live_urls.txt

httpx -l live/live_urls.txt \
    -silent -status-code -title -tech-detect \
    -o live/live_summary.txt 2>"$DEVNULL"

grep -E "\[200\]" live/live_summary.txt > live/status_200.txt 2>"$DEVNULL"
grep -E "\[30[1-8]\]" live/live_summary.txt > live/status_redirect.txt 2>"$DEVNULL"
grep -E "\[40[13]\]" live/live_summary.txt > live/status_403_401.txt 2>"$DEVNULL"
grep -E "\[500\]|\[502\]|\[503\]" live/live_summary.txt > live/status_5xx.txt 2>"$DEVNULL"

step_ok "Categorized"
TOTAL_LIVE=$(count_lines live/live_urls.txt)
step_info "📌 Live hosts: ${WHITE}$TOTAL_LIVE${NC}"
step_info "   • 200 OK: $(count_lines live/status_200.txt)"
step_info "   • 403/401: $(count_lines live/status_403_401.txt) ${DIM}(try bypass!)${NC}"
step_info "   • 5xx: $(count_lines live/status_5xx.txt) ${DIM}(might leak info)${NC}"

phase_done 2
phase_end
show_stats_inline

# ═══════════════════════════════════════════════════════════════
# PHASE 3: SCREENSHOT
# ═══════════════════════════════════════════════════════════════
phase_start 3 "VISUAL RECON (SCREENSHOT)" "10-60 menit"

if [ $QUICK -eq 0 ] && [ $TOTAL_LIVE -lt 500 ]; then
    step_start "Taking screenshots (gowitness)..."
    gowitness file -f live/live_urls.txt \
        --screenshot-path screenshots/ \
        --timeout 15 --threads 5 2>"$DEVNULL" &
    GW_PID=$!
    
    while kill -0 $GW_PID 2>"$DEVNULL"; do
        count=$(ls screenshots/ 2>"$DEVNULL" | wc -l)
        printf "\r  ${CYAN}⠋${NC} Screenshotting... ${WHITE}%d/%d${NC}     " "$count" "$TOTAL_LIVE"
        sleep 3
    done
    wait $GW_PID
    stop_spinner
    step_ok "Screenshots" "$(ls screenshots/ 2>"$DEVNULL" | wc -l)"
else
    step_warn "Skipped (too many hosts or quick mode)"
fi

phase_done 3
phase_end

# ═══════════════════════════════════════════════════════════════
# PHASE 4: QUICK WINS
# ═══════════════════════════════════════════════════════════════
phase_start 4 "QUICK WINS (Takeover, CORS, Bypass)" "15-25 menit"

step_start "Subdomain Takeover check (subzy)..."
subzy run --targets subdomains/all_subdomains.txt \
    --hide_fails --concurrency 50 \
    > takeover/subzy_results.txt 2>"$DEVNULL"
step_ok "Subzy" "$(count_lines takeover/subzy_results.txt)"

step_start "Nuclei takeover templates..."
nuclei -l live/live_urls.txt \
    -t "$HOME/nuclei-templates/http/takeovers/" \
    -severity high,critical \
    -silent -rate-limit 50 \
    -o takeover/nuclei_takeover.txt 2>"$DEVNULL"
step_ok "Nuclei takeover" "$(count_lines takeover/nuclei_takeover.txt)"

step_start "CORS misconfiguration check..."
nuclei -l live/live_urls.txt \
    -t "$HOME/nuclei-templates/http/misconfiguration/cors-misconfig.yaml" \
    -silent -rate-limit 50 \
    -o nuclei/cors_misconfig.txt 2>"$DEVNULL"
step_ok "CORS check" "$(count_lines nuclei/cors_misconfig.txt)"

if [ -s live/status_403_401.txt ]; then
    step_start "403/401 Bypass attempts..."
    awk '{print $1}' live/status_403_401.txt | \
        nuclei -t "$HOME/nuclei-templates/http/miscellaneous/" \
        -tags bypass -silent \
        -o nuclei/403_bypass.txt 2>"$DEVNULL"
    step_ok "403 bypass" "$(count_lines nuclei/403_bypass.txt)"
fi

phase_done 4
phase_end
show_random_tip

# ═══════════════════════════════════════════════════════════════
# PHASE 5: PORT SCANNING
# ═══════════════════════════════════════════════════════════════
phase_start 5 "PORT SCANNING" "30-90 menit"

if [ $QUICK -eq 0 ]; then
    step_start "Naabu - top 1000 ports..."
    naabu -list subdomains/all_subdomains.txt \
        -top-ports 1000 -rate 500 -silent \
        -o ports/open_ports.txt 2>"$DEVNULL" &
    NAABU_PID=$!
    
    while kill -0 $NAABU_PID 2>"$DEVNULL"; do
        count=$(count_lines ports/open_ports.txt)
        printf "\r  ${CYAN}⠋${NC} Scanning ports... ${WHITE}%d found${NC}     " "$count"
        sleep 5
    done
    wait $NAABU_PID
    stop_spinner
    step_ok "Port scan" "$(count_lines ports/open_ports.txt)"
else
    step_warn "Skipped (quick mode)"
fi

phase_done 5
phase_end

# ═══════════════════════════════════════════════════════════════
# PHASE 6: URL COLLECTION
# ═══════════════════════════════════════════════════════════════
phase_start 6 "URL & ENDPOINT COLLECTION" "30-120 menit"

step_start "Katana - active crawling..."
timeout 3600 katana -list live/live_urls.txt \
    -d 3 -c 10 -jc -silent \
    -o urls/katana.txt 2>"$DEVNULL" &
KATANA_PID=$!

while kill -0 $KATANA_PID 2>"$DEVNULL"; do
    count=$(count_lines urls/katana.txt)
    printf "\r  ${CYAN}⠋${NC} Katana crawling... ${WHITE}%d URLs${NC}     " "$count"
    sleep 3
done
wait $KATANA_PID
stop_spinner
step_ok "Katana" "$(count_lines urls/katana.txt)"

step_start "GAU - passive URLs (wayback+otx+commoncrawl)..."
cat live/live_urls.txt | timeout 3600 gau --threads 10 --subs 2>"$DEVNULL" > urls/gau.txt &
GAU_PID=$!
while kill -0 $GAU_PID 2>"$DEVNULL"; do
    count=$(count_lines urls/gau.txt)
    printf "\r  ${CYAN}⠋${NC} GAU fetching... ${WHITE}%d URLs${NC}     " "$count"
    sleep 3
done
wait $GAU_PID
stop_spinner
step_ok "GAU" "$(count_lines urls/gau.txt)"

step_start "Waybackurls..."
cat live/live_urls.txt | waybackurls 2>"$DEVNULL" > urls/wayback.txt
step_ok "Wayback" "$(count_lines urls/wayback.txt)"

# waymore: agregasi wayback + commoncrawl + otx + urlscan sekaligus
if command -v waymore &>/dev/null; then
    step_start "Waymore - multi-source passive URLs..."
    waymore -i "$TARGET" -mode U -oU urls/waymore.txt 2>"$DEVNULL" || true
    step_ok "Waymore" "$(count_lines urls/waymore.txt)"
else
    step_info "waymore tidak ditemukan - skip (install: pip install waymore)"
fi

step_start "Hakrawler..."
cat live/live_urls.txt | hakrawler -d 2 -subs 2>"$DEVNULL" > urls/hakrawler.txt
step_ok "Hakrawler" "$(count_lines urls/hakrawler.txt)"

step_start "Merging & deduplicating URLs (uro)..."
cat urls/katana.txt urls/gau.txt urls/wayback.txt urls/waymore.txt urls/hakrawler.txt 2>"$DEVNULL" | \
    sort -u | uro 2>"$DEVNULL" > urls/all_urls_dedup.txt
step_ok "After uro dedup" "$(count_lines urls/all_urls_dedup.txt)"

step_start "Filtering by extension..."
grep -iE "\.(js|jsx|mjs)($|\?)" urls/all_urls_dedup.txt | sort -u > urls/js_files.txt
grep -iE "\.(php|asp|aspx|jsp)($|\?)" urls/all_urls_dedup.txt > urls/dynamic_pages.txt
grep -iE "\.(json|xml|yaml|yml|config|conf|env|bak|backup|old|sql|db|log|txt|pdf|xls|xlsx|doc|docx)($|\?)" urls/all_urls_dedup.txt > urls/interesting_files.txt
grep -E "\?.*=" urls/all_urls_dedup.txt > urls/urls_with_params.txt
step_ok "Filtered"

step_info "   • JS files: $(count_lines urls/js_files.txt)"
step_info "   • Dynamic: $(count_lines urls/dynamic_pages.txt)"
step_info "   • Interesting: $(count_lines urls/interesting_files.txt)"
step_info "   • With params: $(count_lines urls/urls_with_params.txt)"

phase_done 6
phase_end
show_stats_inline
show_random_tip

# ═══════════════════════════════════════════════════════════════
# PHASE 7: JS DEEP ANALYSIS
# ═══════════════════════════════════════════════════════════════
phase_start 7 "JS DEEP ANALYSIS" "20-90 menit"

step_start "Filtering live JS files..."
httpx -l urls/js_files.txt -mc 200 -silent -threads 50 \
    -o js/js_live.txt 2>"$DEVNULL"
TOTAL_JS=$(count_lines js/js_live.txt)
step_ok "Live JS files" "$TOTAL_JS"

if [ $TOTAL_JS -gt 0 ]; then
    # LinkFinder - extract endpoints
    step_start "LinkFinder - extracting hidden endpoints (sample 100)..."
    mkdir -p js/endpoints
    
    LF_COUNT=0
    LF_TOTAL=$((TOTAL_JS < 100 ? TOTAL_JS : 100))
    
    head -100 js/js_live.txt | while read -r jsurl; do
        LF_COUNT=$((LF_COUNT + 1))
        printf "\r  ${CYAN}⠋${NC} LinkFinder ${WHITE}%d/%d${NC}     " "$LF_COUNT" "$LF_TOTAL"
        python3 ~/tools/LinkFinder/linkfinder.py -i "$jsurl" -o cli 2>"$DEVNULL" \
            >> js/endpoints/all_endpoints.txt
    done
    stop_spinner
    sort -u js/endpoints/all_endpoints.txt -o js/endpoints/all_endpoints.txt 2>"$DEVNULL"
    step_ok "Endpoints found" "$(count_lines js/endpoints/all_endpoints.txt)"

    # SecretFinder
    step_start "SecretFinder - scanning for secrets (sample 50)..."
    mkdir -p js/secretfinder
    SF_COUNT=0
    SF_TOTAL=$((TOTAL_JS < 50 ? TOTAL_JS : 50))
    
    head -50 js/js_live.txt | while read -r jsurl; do
        SF_COUNT=$((SF_COUNT + 1))
        printf "\r  ${CYAN}⠋${NC} SecretFinder ${WHITE}%d/%d${NC}     " "$SF_COUNT" "$SF_TOTAL"
        python3 ~/tools/SecretFinder/SecretFinder.py -i "$jsurl" -o cli 2>"$DEVNULL" \
            >> js/secretfinder/results.txt
    done
    stop_spinner
    step_ok "SecretFinder done"

    # Mantra
    step_start "Mantra - API key hunter..."
    cat js/js_live.txt | mantra 2>"$DEVNULL" > js/mantra_results.txt
    step_ok "Mantra" "$(count_lines js/mantra_results.txt)"

    # Trufflehog v3
    step_start "Trufflehog - verified secrets only (v3 syntax)..."
    if command -v trufflehog &>/dev/null; then
        while IFS= read -r jsurl; do
            tf_tmp=$(mktemp /tmp/tfhog_XXXXXX.js)
            if curl -sL --max-time 15 "$jsurl" -o "$tf_tmp" 2>"$DEVNULL"; then
                trufflehog filesystem "$tf_tmp" --only-verified --no-update \
                    --json 2>"$DEVNULL" >> js/trufflehog_verified.txt || true
            fi
            rm -f "$tf_tmp"
        done < <(head -30 js/js_live.txt)
        step_ok "Trufflehog verified" "$(count_lines js/trufflehog_verified.txt)"
    else
        step_info "Trufflehog tidak ditemukan - skipping"
    fi

    # Nuclei on JS
    step_start "Nuclei - JS exposures & tokens..."
    nuclei -l js/js_live.txt \
        -t "$HOME/nuclei-templates/http/exposures/" \
        -t "$HOME/nuclei-templates/http/token-spray/" \
        -silent -rate-limit 100 \
        -o js/nuclei_js_exposures.txt 2>"$DEVNULL"
    step_ok "Nuclei JS scan" "$(count_lines js/nuclei_js_exposures.txt)"
else
    step_warn "No live JS files - skipping JS analysis"
fi

phase_done 7
phase_end
show_random_tip

# ═══════════════════════════════════════════════════════════════
# PHASE 8: SECRETS & INFO DISCLOSURE
# ═══════════════════════════════════════════════════════════════
phase_start 8 "SECRETS & INFO DISCLOSURE" "15-40 menit"

# Sensitive paths list
cat > /tmp/sensitive_paths.txt << 'EOF'
/.git/config
/.git/HEAD
/.env
/.env.local
/.env.production
/.env.backup
/config.json
/config.yml
/backup.sql
/backup.zip
/database.sql
/.aws/credentials
/.ssh/id_rsa
/.npmrc
/phpinfo.php
/server-status
/.DS_Store
/robots.txt
/sitemap.xml
/swagger.json
/api-docs
/.htaccess
/.htpasswd
/web.config
/composer.json
/package.json
/package-lock.json
/Dockerfile
/docker-compose.yml
/README
/README.md
/crossdomain.xml
/clientaccesspolicy.xml
/actuator/health
/actuator/env
/actuator/heapdump
/actuator/mappings
/debug/pprof
/metrics
/graphql
/graphiql
/.vscode/settings.json
/.idea/workspace.xml
EOF

step_start "Generating sensitive URLs to check..."
> secrets/sensitive_urls_to_check.txt
while IFS= read -r host; do
    while IFS= read -r path; do
        echo "${host}${path}"
    done < /tmp/sensitive_paths.txt
done < live/live_urls.txt >> secrets/sensitive_urls_to_check.txt
step_ok "URLs generated" "$(count_lines secrets/sensitive_urls_to_check.txt)"

step_start "Probing sensitive files (httpx)..."
httpx -l secrets/sensitive_urls_to_check.txt \
    -mc 200,403 \
    -mr "Index of|root:|DB_PASSWORD|api[_-]?key|secret|BEGIN RSA|BEGIN OPENSSH|mysql_|AKIA[0-9A-Z]{16}" \
    -silent -threads 50 \
    -o secrets/exposed_files.txt 2>"$DEVNULL" &
HTTPX_PID=$!

while kill -0 $HTTPX_PID 2>"$DEVNULL"; do
    count=$(count_lines secrets/exposed_files.txt)
    printf "\r  ${CYAN}⠋${NC} Probing sensitive files... ${WHITE}%d exposed${NC}     " "$count"
    sleep 3
done
wait $HTTPX_PID
stop_spinner
step_ok "Exposed files" "$(count_lines secrets/exposed_files.txt)"

step_start "Checking .git exposure..."
httpx -l live/live_urls.txt -path "/.git/config" \
    -mc 200 -mr "repositoryformatversion" \
    -silent -o secrets/git_exposed.txt 2>"$DEVNULL"
GIT_COUNT=$(count_lines secrets/git_exposed.txt)
if [ $GIT_COUNT -gt 0 ]; then
    step_ok "⚠️  .git EXPOSED!" "$GIT_COUNT"
    echo -e "  ${RED}${BOLD}🚨 CRITICAL: $GIT_COUNT target punya .git exposed!${NC}"
    [ -n "${DISCORD_WEBHOOK:-}" ] && notify_critical "$TARGET" ".git EXPOSED di $GIT_COUNT host! Jalankan git-dumper segera."
else
    step_ok "No .git exposure"
fi

step_start "Checking .env exposure..."
httpx -l live/live_urls.txt -path "/.env" \
    -mc 200 -mr "APP_|DB_|API_|SECRET" \
    -silent -o secrets/env_exposed.txt 2>"$DEVNULL"
ENV_COUNT=$(count_lines secrets/env_exposed.txt)
if [ $ENV_COUNT -gt 0 ]; then
    step_ok "⚠️  .env EXPOSED!" "$ENV_COUNT"
    echo -e "  ${RED}${BOLD}🚨 CRITICAL: $ENV_COUNT target punya .env exposed!${NC}"
    [ -n "${DISCORD_WEBHOOK:-}" ] && notify_critical "$TARGET" ".env EXPOSED di $ENV_COUNT host! Cek segera."
else
    step_ok "No .env exposure"
fi

phase_done 8
phase_end
show_random_tip

# ═══════════════════════════════════════════════════════════════
# PHASE 9: PARAMETER DISCOVERY
# ═══════════════════════════════════════════════════════════════
phase_start 9 "PARAMETER DISCOVERY" "15-40 menit"

if command -v gf &> /dev/null; then
    step_start "Categorizing URLs by vulnerability type (gf patterns)..."
    
    cat urls/all_urls_dedup.txt | gf xss 2>"$DEVNULL" | sort -u > params/xss_candidates.txt
    cat urls/all_urls_dedup.txt | gf sqli 2>"$DEVNULL" | sort -u > params/sqli_candidates.txt
    cat urls/all_urls_dedup.txt | gf ssrf 2>"$DEVNULL" | sort -u > params/ssrf_candidates.txt
    cat urls/all_urls_dedup.txt | gf lfi 2>"$DEVNULL" | sort -u > params/lfi_candidates.txt
    cat urls/all_urls_dedup.txt | gf rce 2>"$DEVNULL" | sort -u > params/rce_candidates.txt
    cat urls/all_urls_dedup.txt | gf redirect 2>"$DEVNULL" | sort -u > params/redirect_candidates.txt
    cat urls/all_urls_dedup.txt | gf ssti 2>"$DEVNULL" | sort -u > params/ssti_candidates.txt
    cat urls/all_urls_dedup.txt | gf idor 2>"$DEVNULL" | sort -u > params/idor_candidates.txt
    cat urls/all_urls_dedup.txt | gf debug_logic 2>"$DEVNULL" | sort -u > params/debug_candidates.txt
    cat urls/all_urls_dedup.txt | gf interestingparams 2>"$DEVNULL" | sort -u > params/interesting_params.txt
    
    step_ok "GF categorization done"
    
    step_info "   • 🎯 XSS candidates: $(count_lines params/xss_candidates.txt)"
    step_info "   • 💉 SQLi candidates: $(count_lines params/sqli_candidates.txt)"
    step_info "   • 🌐 SSRF candidates: $(count_lines params/ssrf_candidates.txt)"
    step_info "   • 📂 LFI candidates: $(count_lines params/lfi_candidates.txt)"
    step_info "   • ⚡ RCE candidates: $(count_lines params/rce_candidates.txt)"
    step_info "   • ↪️  Open redirect: $(count_lines params/redirect_candidates.txt)"
    step_info "   • 📝 SSTI candidates: $(count_lines params/ssti_candidates.txt)"
    step_info "   • 🔓 IDOR candidates: $(count_lines params/idor_candidates.txt)"
fi

if command -v arjun &> /dev/null && [ $QUICK -eq 0 ]; then
    step_start "Arjun - discovering hidden parameters (top 30 hosts)..."
    head -30 live/live_urls.txt > /tmp/arjun_input.txt
    timeout 1800 arjun -i /tmp/arjun_input.txt \
        -oJ params/arjun_results.json \
        -t 10 --stable 2>"$DEVNULL" &
    ARJUN_PID=$!
    
    while kill -0 $ARJUN_PID 2>"$DEVNULL"; do
        printf "\r  ${CYAN}⠋${NC} Arjun hunting hidden params...     "
        sleep 3
    done
    wait $ARJUN_PID
    stop_spinner
    step_ok "Arjun done"
fi

phase_done 9
phase_end
show_random_tip

# ═══════════════════════════════════════════════════════════════
# PHASE 10: NUCLEI VULNERABILITY SCAN
# ═══════════════════════════════════════════════════════════════

# Pastikan nuclei templates tersedia
NUCLEI_TEMPLATES="${HOME}/nuclei-templates"
if [ ! -d "$NUCLEI_TEMPLATES" ]; then
    step_info "nuclei-templates tidak ditemukan di $NUCLEI_TEMPLATES, auto-update..."
    nuclei -update-templates 2>"$DEVNULL" || step_warn "Gagal update nuclei templates - scan mungkin tidak optimal"
fi

phase_start 10 "NUCLEI VULNERABILITY SCAN (5 stages)" "60-180 menit"

echo -e "  ${DIM}This is the longest phase - Nuclei will run 5 different scans${NC}"
echo ""

# Stage 1: Critical & High CVEs
step_start "Stage 1/5: Critical & High CVEs..."
nuclei -l live/live_urls.txt \
    -t "$HOME/nuclei-templates/http/cves/" \
    -severity critical,high \
    -rate-limit 150 -c 25 -silent \
    -o nuclei/01_cves_critical_high.txt 2>"$DEVNULL" &
N1_PID=$!
while kill -0 $N1_PID 2>"$DEVNULL"; do
    count=$(count_lines nuclei/01_cves_critical_high.txt)
    printf "\r  ${CYAN}⠋${NC} [1/5] CVEs scan... ${WHITE}%d findings${NC}     " "$count"
    sleep 5
done
wait $N1_PID
stop_spinner
step_ok "CVEs scan" "$(count_lines nuclei/01_cves_critical_high.txt)"

# Stage 2: Misconfigurations
step_start "Stage 2/5: Misconfigurations..."
nuclei -l live/live_urls.txt \
    -t "$HOME/nuclei-templates/http/misconfiguration/" \
    -severity medium,high,critical \
    -rate-limit 150 -silent \
    -o nuclei/02_misconfigurations.txt 2>"$DEVNULL" &
N2_PID=$!
while kill -0 $N2_PID 2>"$DEVNULL"; do
    count=$(count_lines nuclei/02_misconfigurations.txt)
    printf "\r  ${CYAN}⠋${NC} [2/5] Misconfigs... ${WHITE}%d findings${NC}     " "$count"
    sleep 5
done
wait $N2_PID
stop_spinner
step_ok "Misconfigurations" "$(count_lines nuclei/02_misconfigurations.txt)"

# Stage 3: Exposures
step_start "Stage 3/5: Exposures..."
nuclei -l live/live_urls.txt \
    -t "$HOME/nuclei-templates/http/exposures/" \
    -rate-limit 150 -silent \
    -o nuclei/03_exposures.txt 2>"$DEVNULL" &
N3_PID=$!
while kill -0 $N3_PID 2>"$DEVNULL"; do
    count=$(count_lines nuclei/03_exposures.txt)
    printf "\r  ${CYAN}⠋${NC} [3/5] Exposures... ${WHITE}%d findings${NC}     " "$count"
    sleep 5
done
wait $N3_PID
stop_spinner
step_ok "Exposures" "$(count_lines nuclei/03_exposures.txt)"

# Stage 4: Default Logins
step_start "Stage 4/5: Default Logins..."
nuclei -l live/live_urls.txt \
    -t "$HOME/nuclei-templates/http/default-logins/" \
    -rate-limit 100 -silent \
    -o nuclei/04_default_logins.txt 2>"$DEVNULL" &
N4_PID=$!
while kill -0 $N4_PID 2>"$DEVNULL"; do
    count=$(count_lines nuclei/04_default_logins.txt)
    printf "\r  ${CYAN}⠋${NC} [4/5] Default logins... ${WHITE}%d findings${NC}     " "$count"
    sleep 5
done
wait $N4_PID
stop_spinner
step_ok "Default logins" "$(count_lines nuclei/04_default_logins.txt)"

# Stage 5: Vulnerabilities
step_start "Stage 5/5: Vulnerabilities..."
nuclei -l live/live_urls.txt \
    -t "$HOME/nuclei-templates/http/vulnerabilities/" \
    -severity medium,high,critical \
    -rate-limit 150 -silent \
    -o nuclei/05_vulnerabilities.txt 2>"$DEVNULL" &
N5_PID=$!
while kill -0 $N5_PID 2>"$DEVNULL"; do
    count=$(count_lines nuclei/05_vulnerabilities.txt)
    printf "\r  ${CYAN}⠋${NC} [5/5] Vulnerabilities... ${WHITE}%d findings${NC}     " "$count"
    sleep 5
done
wait $N5_PID
stop_spinner
step_ok "Vulnerabilities" "$(count_lines nuclei/05_vulnerabilities.txt)"

# Bonus: Fuzzing templates
# Bonus: Fuzzing templates (deep mode only)
if [ $QUICK -eq 0 ] && [ -d ~/tools/fuzzing-templates ] && [ -s urls/urls_with_params.txt ]; then
    step_start "BONUS: Fuzzing templates on parameterized URLs..."
    head -500 urls/urls_with_params.txt | \
        nuclei -t "$HOME/tools/fuzzing-templates/" \
        -severity medium,high,critical \
        -rate-limit 100 -silent \
        -o nuclei/06_fuzzing_results.txt 2>"$DEVNULL" &
    NF_PID=$!
    while kill -0 $NF_PID 2>"$DEVNULL"; do
        count=$(count_lines nuclei/06_fuzzing_results.txt)
        printf "\r  ${CYAN}⠋${NC} Fuzzing templates... ${WHITE}%d findings${NC}     " "$count"
        sleep 5
    done
    wait $NF_PID
    stop_spinner
    step_ok "Fuzzing done" "$(count_lines nuclei/06_fuzzing_results.txt)"
fi

phase_done 10
phase_end
show_random_tip

# ═══════════════════════════════════════════════════════════════
# PHASE 11: DIRECTORY BRUTEFORCE (ffuf)
# ═══════════════════════════════════════════════════════════════
phase_start 11 "DIRECTORY BRUTEFORCE (ffuf)" "30-120 menit"

if command -v ffuf &>/dev/null && [ $QUICK -eq 0 ]; then
    # Wordlist fallback
    FFUF_WORDLIST=""
    for wl in \
        ~/wordlists/SecLists/Discovery/Web-Content/raft-medium-directories.txt \
        ~/wordlists/raft-medium-directories.txt \
        /usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt \
        /usr/share/wordlists/dirb/common.txt; do
        if [ -f "$wl" ]; then FFUF_WORDLIST="$wl"; break; fi
    done

    if [ -n "$FFUF_WORDLIST" ]; then
        mkdir -p ffuf
        # Limit ke 20 host untuk efisiensi (prioritas 200 OK dulu)
        FFUF_TARGETS=$(head -20 live/status_200.txt 2>/dev/null | awk '{print $1}' || head -20 live/live_urls.txt)
        FFUF_COUNT=0
        FFUF_TOTAL=$(echo "$FFUF_TARGETS" | wc -l)

        step_start "ffuf - bruteforcing directories ($FFUF_TOTAL hosts)..."
        while IFS= read -r host; do
            FFUF_COUNT=$((FFUF_COUNT + 1))
            # Sanitize hostname jadi nama file
            safe_host=$(echo "$host" | sed 's|https\?://||;s|[/:]|_|g')
            printf "\r  ${CYAN}⠋${NC} ffuf [%d/%d] %s     " "$FFUF_COUNT" "$FFUF_TOTAL" "$host"
            timeout 300 ffuf \
                -u "${host}/FUZZ" \
                -w "$FFUF_WORDLIST" \
                -mc 200,201,204,301,302,307,401,403,405 \
                -t 50 -rate 100 \
                -o "ffuf/${safe_host}.json" -of json \
                -s 2>"$DEVNULL" || true
        done <<< "$FFUF_TARGETS"

        stop_spinner

        # Merge semua hasil ffuf
        step_start "Merging ffuf results..."
        jq -r '.results[]? | "\(.status) \(.length) \(.url)"' ffuf/*.json 2>/dev/null | \
            sort -u > ffuf/all_findings.txt || true
        step_ok "ffuf findings" "$(count_lines ffuf/all_findings.txt)"

        # Extract interesting paths
        grep -E "^200|^201|^204" ffuf/all_findings.txt > ffuf/found_200.txt 2>/dev/null || true
        grep -E "^401|^403" ffuf/all_findings.txt > ffuf/found_auth.txt 2>/dev/null || true
        step_info "   • 200 OK: $(count_lines ffuf/found_200.txt)"
        step_info "   • 401/403 (try bypass!): $(count_lines ffuf/found_auth.txt)"
    else
        step_warn "ffuf wordlist tidak ditemukan. Install SecLists: git clone https://github.com/danielmiessler/SecLists ~/wordlists/SecLists"
    fi
else
    if ! command -v ffuf &>/dev/null; then
        step_info "ffuf tidak ditemukan - skip (install: go install github.com/ffuf/ffuf/v2@latest)"
    else
        step_warn "Skipped (quick mode)"
    fi
fi

phase_done 11
phase_end
show_random_tip

# ═══════════════════════════════════════════════════════════════
# PHASE 12: AUTO XSS SCAN (dalfox)
# ═══════════════════════════════════════════════════════════════
phase_start 12 "AUTO XSS SCAN (dalfox)" "15-60 menit"

if command -v dalfox &>/dev/null && [ -s params/xss_candidates.txt ]; then
    XSS_TOTAL=$(count_lines params/xss_candidates.txt)
    step_info "XSS candidates: $XSS_TOTAL URLs"

    # Limit ke 200 untuk efisiensi
    if [ "$XSS_TOTAL" -gt 200 ]; then
        step_info "Target besar - limit ke 200 URL teratas"
        head -200 params/xss_candidates.txt > /tmp/dalfox_input.txt
    else
        cp params/xss_candidates.txt /tmp/dalfox_input.txt
    fi

    step_start "dalfox - automated XSS scanning..."
    timeout 3600 dalfox file /tmp/dalfox_input.txt \
        --silence \
        --skip-bav \
        --output params/dalfox_findings.txt \
        --format plain \
        2>"$DEVNULL" &
    DFX_PID=$!

    while kill -0 $DFX_PID 2>/dev/null; do
        count=$(count_lines params/dalfox_findings.txt)
        printf "\r  ${CYAN}⠋${NC} dalfox scanning XSS... ${WHITE}%d confirmed${NC}     " "$count"
        sleep 3
    done
    wait $DFX_PID
    stop_spinner

    XSS_CONFIRMED=$(count_lines params/dalfox_findings.txt)
    step_ok "dalfox done" "$XSS_CONFIRMED confirmed XSS"

    if [ "$XSS_CONFIRMED" -gt 0 ]; then
        echo -e "  ${RED}${BOLD}🚨 $XSS_CONFIRMED XSS CONFIRMED!${NC}"
        # Notify Discord jika ada
        if [ -n "${DISCORD_WEBHOOK:-}" ]; then
            notify_critical "$TARGET" "$XSS_CONFIRMED Confirmed XSS via dalfox"
        fi
    fi

    rm -f /tmp/dalfox_input.txt
elif ! command -v dalfox &>/dev/null; then
    step_info "dalfox tidak ditemukan - skip (install: go install github.com/hahwul/dalfox/v2@latest)"
else
    step_info "Tidak ada XSS candidates (params/xss_candidates.txt kosong)"
fi

phase_done 12
phase_end

# ═══════════════════════════════════════════════════════════════
# PHASE 13: REPORTING
# ═══════════════════════════════════════════════════════════════
phase_start 13 "GENERATING FINAL REPORT" "1-2 menit"

END_TIME=$(date +%s)
DURATION=$((END_TIME - SCRIPT_START_TIME))
HOURS=$((DURATION / 3600))
MINUTES=$(((DURATION % 3600) / 60))
SECONDS=$((DURATION % 60))

# Count severity
CRITICAL=$(grep -ch "\[critical\]" nuclei/*.txt 2>"$DEVNULL" | awk '{s+=$1}END{print s+0}')
HIGH=$(grep -ch "\[high\]" nuclei/*.txt 2>"$DEVNULL" | awk '{s+=$1}END{print s+0}')
MEDIUM=$(grep -ch "\[medium\]" nuclei/*.txt 2>"$DEVNULL" | awk '{s+=$1}END{print s+0}')
LOW=$(grep -ch "\[low\]" nuclei/*.txt 2>"$DEVNULL" | awk '{s+=$1}END{print s+0}')
INFO=$(grep -ch "\[info\]" nuclei/*.txt 2>"$DEVNULL" | awk '{s+=$1}END{print s+0}')

# Discord notify kalau ada critical findings
if [ "${CRITICAL:-0}" -gt 0 ] && [ -n "${DISCORD_WEBHOOK:-}" ]; then
    notify_critical "$TARGET" "$CRITICAL Critical nuclei findings! Cek nuclei/*.txt segera."
fi

step_start "Creating PRIORITY_FINDINGS.txt..."
{
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║          🔥 PRIORITY FINDINGS - REVIEW FIRST             ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "Target: $TARGET"
    echo "Date  : $(date)"
    echo ""
    
    echo "═══════════════════════════════════════════════════"
    echo "  🔴 CRITICAL FINDINGS"
    echo "═══════════════════════════════════════════════════"
    grep -h "\[critical\]" nuclei/*.txt 2>"$DEVNULL" || echo "  (none)"
    echo ""
    
    echo "═══════════════════════════════════════════════════"
    echo "  🟠 HIGH FINDINGS"
    echo "═══════════════════════════════════════════════════"
    grep -h "\[high\]" nuclei/*.txt 2>"$DEVNULL" || echo "  (none)"
    echo ""
    
    echo "═══════════════════════════════════════════════════"
    echo "  🎯 SUBDOMAIN TAKEOVER CANDIDATES"
    echo "═══════════════════════════════════════════════════"
    cat takeover/*.txt 2>"$DEVNULL" || echo "  (none)"
    echo ""
    
    echo "═══════════════════════════════════════════════════"
    echo "  🔐 EXPOSED SECRETS (.env, .git)"
    echo "═══════════════════════════════════════════════════"
    cat secrets/env_exposed.txt secrets/git_exposed.txt 2>"$DEVNULL" || echo "  (none)"
    echo ""
    
    echo "═══════════════════════════════════════════════════"
    echo "  🗝️  JS SECRETS (Mantra)"
    echo "═══════════════════════════════════════════════════"
    cat js/mantra_results.txt 2>"$DEVNULL" || echo "  (none)"
    echo ""
    
    echo "═══════════════════════════════════════════════════"
    echo "  ✅ VERIFIED SECRETS (Trufflehog)"
    echo "═══════════════════════════════════════════════════"
    cat js/trufflehog_verified.txt 2>"$DEVNULL" || echo "  (none)"
    echo ""

    echo "═══════════════════════════════════════════════════"
    echo "  🎯 CONFIRMED XSS (dalfox)"
    echo "═══════════════════════════════════════════════════"
    cat params/dalfox_findings.txt 2>"$DEVNULL" || echo "  (none)"
    echo ""

    echo "═══════════════════════════════════════════════════"
    echo "  📂 DIRECTORY BRUTEFORCE - 200 OK (ffuf)"
    echo "═══════════════════════════════════════════════════"
    cat ffuf/found_200.txt 2>"$DEVNULL" || echo "  (none)"
    echo ""

    echo "═══════════════════════════════════════════════════"
    echo "  📂 SENSITIVE FILES EXPOSED"
    echo "═══════════════════════════════════════════════════"
    cat secrets/exposed_files.txt 2>"$DEVNULL" || echo "  (none)"
    
} > final/PRIORITY_FINDINGS.txt
step_ok "Priority findings created"

# JSON Report — pakai jq supaya karakter spesial di $TARGET tidak corrupt JSON
step_start "Generating JSON report..."
# Hitung raw_all.txt dengan aman (tidak ada di mode single)
RAW_ALL_COUNT=$(count_lines subdomains/raw_all.txt)
RESOLVED_COUNT=$(count_lines subdomains/resolved.txt)

jq -n \
  --arg     target          "$TARGET" \
  --arg     mode            "$MODE" \
  --arg     version         "$VERSION" \
  --arg     start_time      "$(date -d @"$SCRIPT_START_TIME" '+%Y-%m-%d %H:%M:%S')" \
  --arg     end_time        "$(date -d @"$END_TIME" '+%Y-%m-%d %H:%M:%S')" \
  --arg     duration_human  "${HOURS}h ${MINUTES}m ${SECONDS}s" \
  --arg     outdir          "$OUTDIR" \
  --argjson duration        "$DURATION" \
  --argjson sub_total       "$RAW_ALL_COUNT" \
  --argjson sub_resolved    "$RESOLVED_COUNT" \
  --argjson sub_inscope     "$(count_lines subdomains/all_subdomains.txt)" \
  --argjson live_total      "$TOTAL_LIVE" \
  --argjson live_200        "$(count_lines live/status_200.txt)" \
  --argjson live_403        "$(count_lines live/status_403_401.txt)" \
  --argjson live_5xx        "$(count_lines live/status_5xx.txt)" \
  --argjson urls_dedup      "$(count_lines urls/all_urls_dedup.txt)" \
  --argjson urls_js         "$(count_lines urls/js_files.txt)" \
  --argjson urls_live_js    "$TOTAL_JS" \
  --argjson urls_params     "$(count_lines urls/urls_with_params.txt)" \
  --argjson urls_interesting "$(count_lines urls/interesting_files.txt)" \
  --argjson v_critical      "$CRITICAL" \
  --argjson v_high          "$HIGH" \
  --argjson v_medium        "$MEDIUM" \
  --argjson v_low           "$LOW" \
  --argjson v_info          "$INFO" \
  --argjson c_xss           "$(count_lines params/xss_candidates.txt)" \
  --argjson c_sqli          "$(count_lines params/sqli_candidates.txt)" \
  --argjson c_ssrf          "$(count_lines params/ssrf_candidates.txt)" \
  --argjson c_lfi           "$(count_lines params/lfi_candidates.txt)" \
  --argjson c_rce           "$(count_lines params/rce_candidates.txt)" \
  --argjson c_redirect      "$(count_lines params/redirect_candidates.txt)" \
  --argjson c_ssti          "$(count_lines params/ssti_candidates.txt)" \
  --argjson c_idor          "$(count_lines params/idor_candidates.txt)" \
  --argjson s_env           "$ENV_COUNT" \
  --argjson s_git           "$GIT_COUNT" \
  --argjson s_files         "$(count_lines secrets/exposed_files.txt)" \
  --argjson takeover        "$(count_lines takeover/subzy_results.txt)" \
  '"'"'{
    scan_info: {
      target: $target, mode: $mode, version: $version,
      start_time: $start_time, end_time: $end_time,
      duration_seconds: $duration, duration_human: $duration_human,
      output_directory: $outdir
    },
    statistics: {
      subdomains: { total_found: $sub_total, resolved: $sub_resolved, in_scope: $sub_inscope },
      live_hosts: { total: $live_total, status_200: $live_200, status_403_401: $live_403, status_5xx: $live_5xx },
      urls: { total_deduped: $urls_dedup, js_files: $urls_js, live_js: $urls_live_js, with_params: $urls_params, interesting_files: $urls_interesting },
      vulnerabilities: { critical: $v_critical, high: $v_high, medium: $v_medium, low: $v_low, info: $v_info },
      vuln_candidates: { xss: $c_xss, sqli: $c_sqli, ssrf: $c_ssrf, lfi: $c_lfi, rce: $c_rce, open_redirect: $c_redirect, ssti: $c_ssti, idor: $c_idor },
      secrets: { env_exposed: $s_env, git_exposed: $s_git, sensitive_files: $s_files },
      takeover_candidates: $takeover
    },
    priority_files: {
      critical_findings: "final/PRIORITY_FINDINGS.txt",
      all_subdomains: "subdomains/all_subdomains.txt",
      live_urls: "live/live_urls.txt",
      nuclei_results: "nuclei/", js_secrets: "js/", params_for_manual: "params/"
    }
  }'"'"' > final/report.json
step_ok "JSON report"

# HTML Report
step_start "Generating HTML report..."
cat > final/report.html << HTMLEOF
<!DOCTYPE html>
<html>
<head>
<title>Recon Report - $TARGET</title>
<style>
body{font-family:-apple-system,Arial,sans-serif;background:#0d1117;color:#c9d1d9;padding:30px;max-width:1400px;margin:auto;line-height:1.6}
h1{color:#58a6ff;border-bottom:2px solid #30363d;padding-bottom:15px}
h2{color:#7ee787;margin-top:35px;border-left:4px solid #7ee787;padding-left:12px}
.card{background:#161b22;padding:20px;margin:15px 0;border-radius:10px;border:1px solid #30363d}
.critical{border-left:5px solid #ff6b6b;background:#1f1215}
.high{border-left:5px solid #ffa657}
.medium{border-left:5px solid #ffd43b}
.low{border-left:5px solid #79c0ff}
.info{border-left:5px solid #8b949e}
.ok{border-left:5px solid #7ee787}
table{width:100%;border-collapse:collapse;margin:15px 0;background:#161b22;border-radius:8px;overflow:hidden}
th,td{padding:12px 15px;text-align:left;border-bottom:1px solid #30363d}
th{background:#21262d;color:#7ee787;font-weight:600}
tr:hover{background:#1c2128}
.num{font-size:32px;font-weight:bold;color:#7ee787}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:15px;margin:20px 0}
.badge{display:inline-block;padding:4px 10px;border-radius:4px;font-size:12px;font-weight:600}
.b-crit{background:#ff6b6b;color:#fff}
.b-high{background:#ffa657;color:#000}
.b-med{background:#ffd43b;color:#000}
.b-low{background:#79c0ff;color:#000}
code{background:#1c2128;padding:2px 6px;border-radius:4px;color:#f0883e}
ul{line-height:2}
.emoji{font-size:24px;margin-right:10px}
</style>
</head>
<body>
<h1>🔍 Bug Hunter Recon Report v$VERSION</h1>

<div class="card">
<strong>🎯 Target:</strong> <code>$TARGET</code><br>
<strong>⚙️  Mode:</strong> $MODE<br>
<strong>⏱️  Duration:</strong> ${HOURS}h ${MINUTES}m ${SECONDS}s<br>
<strong>📅 Date:</strong> $(date)<br>
<strong>📁 Output:</strong> <code>$OUTDIR</code>
</div>

<h2>📊 Quick Stats</h2>
<div class="grid">
<div class="card"><div class="num">$(count_lines subdomains/all_subdomains.txt)</div>🌐 Subdomains</div>
<div class="card"><div class="num">$TOTAL_LIVE</div>✅ Live Hosts</div>
<div class="card"><div class="num">$(count_lines urls/all_urls_dedup.txt)</div>🔗 Unique URLs</div>
<div class="card"><div class="num">$TOTAL_JS</div>📜 Live JS Files</div>
</div>

<h2>🚨 Vulnerabilities Found</h2>
<table>
<tr><th>Severity</th><th>Count</th><th>Priority</th></tr>
<tr class="critical"><td><span class="emoji">🔴</span>Critical</td><td class="num">$CRITICAL</td><td><span class="badge b-crit">REVIEW NOW</span></td></tr>
<tr class="high"><td><span class="emoji">🟠</span>High</td><td class="num">$HIGH</td><td><span class="badge b-high">HIGH PRIORITY</span></td></tr>
<tr class="medium"><td><span class="emoji">🟡</span>Medium</td><td class="num">$MEDIUM</td><td><span class="badge b-med">MEDIUM</span></td></tr>
<tr class="low"><td><span class="emoji">🔵</span>Low</td><td class="num">$LOW</td><td><span class="badge b-low">LOW</span></td></tr>
<tr class="info"><td><span class="emoji">⚪</span>Info</td><td class="num">$INFO</td><td>Informational</td></tr>
</table>

<h2>🎯 Attack Surface Summary</h2>
<table>
<tr><th>Type</th><th>Count</th><th>Test With</th></tr>
<tr><td>🎯 XSS Candidates</td><td>$(count_lines params/xss_candidates.txt)</td><td><code>dalfox</code></td></tr>
<tr><td>💉 SQLi Candidates</td><td>$(count_lines params/sqli_candidates.txt)</td><td><code>sqlmap</code></td></tr>
<tr><td>🌐 SSRF Candidates</td><td>$(count_lines params/ssrf_candidates.txt)</td><td>Manual + Collab</td></tr>
<tr><td>📂 LFI Candidates</td><td>$(count_lines params/lfi_candidates.txt)</td><td>Manual / ffuf</td></tr>
<tr><td>⚡ RCE Candidates</td><td>$(count_lines params/rce_candidates.txt)</td><td>Manual</td></tr>
<tr><td>↪️ Open Redirect</td><td>$(count_lines params/redirect_candidates.txt)</td><td>Manual</td></tr>
<tr><td>📝 SSTI Candidates</td><td>$(count_lines params/ssti_candidates.txt)</td><td>Manual</td></tr>
<tr><td>🔓 IDOR Candidates</td><td>$(count_lines params/idor_candidates.txt)</td><td>Manual (wajib!)</td></tr>
<tr class="critical"><td>🎯 Takeover Candidates</td><td>$(count_lines takeover/subzy_results.txt)</td><td><code>subzy + manual</code></td></tr>
<tr class="critical"><td>🔐 .env Exposed</td><td>$ENV_COUNT</td><td>Curl + verify</td></tr>
<tr class="critical"><td>🔐 .git Exposed</td><td>$GIT_COUNT</td><td><code>git-dumper</code></td></tr>
</table>

<h2>📁 File Locations</h2>
<div class="card ok">
<ul>
<li>🔥 <code>final/PRIORITY_FINDINGS.txt</code> - <strong>BACA INI PERTAMA!</strong></li>
<li>📊 <code>final/report.json</code> - Machine-readable report</li>
<li>🌐 <code>subdomains/all_subdomains.txt</code> - All subdomains</li>
<li>✅ <code>live/live_urls.txt</code> - Live hosts</li>
<li>⚔️ <code>nuclei/</code> - All vulnerability findings</li>
<li>🔐 <code>js/</code> - JS secrets & endpoints</li>
<li>🎯 <code>params/</code> - Categorized URLs for manual testing</li>
<li>📸 <code>screenshots/</code> - Visual recon</li>
</ul>
</div>

<h2>💡 Next Steps (Manual Testing)</h2>
<div class="card">
<ol>
<li><strong>Review <code>PRIORITY_FINDINGS.txt</code></strong> - validasi setiap finding secara manual</li>
<li>Check verified secrets di <code>js/trufflehog_verified.txt</code></li>
<li>Test XSS: <code>dalfox file params/xss_candidates.txt</code></li>
<li>Test SQLi: <code>sqlmap -m params/sqli_candidates.txt --batch</code></li>
<li>Test SSRF manual dengan Burp Collaborator</li>
<li>Review screenshots untuk spot visual anomaly</li>
<li>Exploit .git jika exposed: <code>git-dumper http://target.com/.git/ ./loot</code></li>
<li>Manual IDOR testing pada <code>params/idor_candidates.txt</code></li>
</ol>
</div>

<h2>📚 Useful Commands</h2>
<div class="card">
<pre style="background:#1c2128;padding:15px;border-radius:8px;overflow-x:auto">
# Filter critical findings
grep -h "[critical]" nuclei/*.txt

# Test XSS candidates
dalfox file params/xss_candidates.txt --silence

# Download .git jika exposed
git-dumper http://target.com/.git/ ./dumped-repo

# SQLmap batch test
sqlmap -m params/sqli_candidates.txt --batch --risk=2

# Check takeover manually
cat takeover/subzy_results.txt
</pre>
</div>

<p style="text-align:center;margin-top:40px;color:#8b949e">
Generated by <strong>Bug Hunter Recon v$VERSION</strong> • $(date)
</p>

</body>
</html>
HTMLEOF
step_ok "HTML report"

phase_done 13
phase_end

# ═══════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              ✓ RECON COMPLETE! 🎉                         ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Full stats box
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${CYAN}  📊 FINAL STATISTICS${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
printf "  ⏱️  %-25s ${WHITE}%s${NC}\n" "Total Duration:" "${HOURS}h ${MINUTES}m ${SECONDS}s"
printf "  📁 %-25s ${WHITE}%s${NC}\n" "Output:" "$OUTDIR"
echo ""
echo -e "${BOLD}  🌐 ASSET DISCOVERY${NC}"
printf "     %-25s ${WHITE}%s${NC}\n" "Subdomains:" "$(count_lines subdomains/all_subdomains.txt)"
printf "     %-25s ${WHITE}%s${NC}\n" "Live hosts:" "$TOTAL_LIVE"
printf "     %-25s ${WHITE}%s${NC}\n" "Unique URLs:" "$(count_lines urls/all_urls_dedup.txt)"
printf "     %-25s ${WHITE}%s${NC}\n" "Live JS files:" "$TOTAL_JS"
echo ""
echo -e "${BOLD}  🚨 VULNERABILITIES${NC}"
printf "     ${RED}%-25s %s${NC}\n" "🔴 Critical:" "$CRITICAL"
printf "     ${YELLOW}%-25s %s${NC}\n" "🟠 High:" "$HIGH"
printf "     ${YELLOW}%-25s %s${NC}\n" "🟡 Medium:" "$MEDIUM"
printf "     ${BLUE}%-25s %s${NC}\n" "🔵 Low:" "$LOW"
printf "     %-25s %s\n" "⚪ Info:" "$INFO"
echo ""
echo -e "${BOLD}  🎯 ATTACK SURFACE${NC}"
printf "     %-25s ${WHITE}%s${NC}\n" "XSS candidates:" "$(count_lines params/xss_candidates.txt)"
printf "     %-25s ${WHITE}%s${NC}\n" "SQLi candidates:" "$(count_lines params/sqli_candidates.txt)"
printf "     %-25s ${WHITE}%s${NC}\n" "SSRF candidates:" "$(count_lines params/ssrf_candidates.txt)"
printf "     %-25s ${WHITE}%s${NC}\n" "LFI candidates:" "$(count_lines params/lfi_candidates.txt)"
printf "     %-25s ${WHITE}%s${NC}\n" "RCE candidates:" "$(count_lines params/rce_candidates.txt)"
printf "     %-25s ${WHITE}%s${NC}\n" "Takeover candidates:" "$(count_lines takeover/subzy_results.txt)"

if [ $GIT_COUNT -gt 0 ] || [ $ENV_COUNT -gt 0 ]; then
    echo ""
    echo -e "${RED}${BOLD}  🚨 CRITICAL EXPOSURES DETECTED!${NC}"
    [ $GIT_COUNT -gt 0 ] && printf "     ${RED}.git exposed: %s targets${NC}\n" "$GIT_COUNT"
    [ $ENV_COUNT -gt 0 ] && printf "     ${RED}.env exposed: %s targets${NC}\n" "$ENV_COUNT"
fi

echo ""
echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${GREEN}  📋 NEXT STEPS${NC}"
echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  1.${NC} Review priority findings:"
echo -e "     ${YELLOW}cat $OUTDIR/final/PRIORITY_FINDINGS.txt${NC}"
echo ""
echo -e "${CYAN}  2.${NC} Open HTML report in browser:"
echo -e "     ${YELLOW}xdg-open $OUTDIR/final/report.html${NC}"
echo ""
echo -e "${CYAN}  3.${NC} Check verified secrets:"
echo -e "     ${YELLOW}cat $OUTDIR/js/trufflehog_verified.txt${NC}"
echo ""
echo -e "${CYAN}  4.${NC} Manual test XSS candidates:"
echo -e "     ${YELLOW}dalfox file $OUTDIR/params/xss_candidates.txt${NC}"
echo ""
echo -e "${CYAN}  5.${NC} Manual test SQLi candidates:"
echo -e "     ${YELLOW}sqlmap -m $OUTDIR/params/sqli_candidates.txt --batch${NC}"
echo ""
echo -e "${CYAN}  6.${NC} Check takeover candidates manually:"
echo -e "     ${YELLOW}cat $OUTDIR/takeover/subzy_results.txt${NC}"

if [ $GIT_COUNT -gt 0 ]; then
    echo ""
    echo -e "${RED}${BOLD}  🚨 URGENT:${NC} .git exposed di $GIT_COUNT target!"
    echo -e "     Dump source code dengan:"
    echo -e "     ${YELLOW}git-dumper http://target/.git/ ./dump${NC}"
fi

echo ""
echo -e "${GREEN}${BOLD}💰 Happy Hunting! Good luck finding bugs! 🐛${NC}"
echo ""
