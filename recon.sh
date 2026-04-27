#!/bin/bash
# ============================================================
# Bug Hunter Recon v2.0 - DEEP RECON
# Support: Single Domain & Wildcard
# ============================================================

# Load API keys
[ -f ~/.config/recon/.env ] && source ~/.config/recon/.env

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
WHITE='\033[1;37m'; NC='\033[0m'

VERSION="2.0"

# ============================================
# BANNER
# ============================================
banner() {
cat << "EOF"
    ____              __  __            __           
   / __ )__  ______ _/ / / /_  ______  / /____  _____
  / __  / / / / __ `/ /_/ / / / / __ \/ __/ _ \/ ___/
 / /_/ / /_/ / /_/ / __  / /_/ / / / / /_/  __/ /    
/_____/\__,_/\__, /_/ /_/\__,_/_/ /_/\__/\___/_/     
            /____/                                    
       Recon v2.0 - H1 Bug Bounty Edition
EOF
}

# ============================================
# HELP
# ============================================
show_help() {
    banner
    echo ""
    echo -e "${CYAN}Usage:${NC}"
    echo -e "  ${YELLOW}./recon.sh -d <domain>${NC}           # Single domain"
    echo -e "  ${YELLOW}./recon.sh -w <domain>${NC}           # Wildcard (*.domain.com)"
    echo -e "  ${YELLOW}./recon.sh -l <list.txt>${NC}         # List of domains"
    echo ""
    echo -e "${CYAN}Options:${NC}"
    echo -e "  ${GREEN}-d${NC}    Single domain mode"
    echo -e "  ${GREEN}-w${NC}    Wildcard mode (deep subdomain enum)"
    echo -e "  ${GREEN}-l${NC}    List file"
    echo -e "  ${GREEN}-o${NC}    Output directory (default: output/)"
    echo -e "  ${GREEN}-s${NC}    Skip heavy scans (quick mode)"
    echo -e "  ${GREEN}-x${NC}    Exclude file (out-of-scope)"
    echo -e "  ${GREEN}-h${NC}    Show help"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo -e "  ${YELLOW}./recon.sh -w hackerone.com${NC}"
    echo -e "  ${YELLOW}./recon.sh -d api.target.com${NC}"
    echo -e "  ${YELLOW}./recon.sh -w target.com -x oos.txt${NC}"
    exit 0
}

# ============================================
# PARSE ARGS
# ============================================
MODE=""
TARGET=""
OUTDIR=""
QUICK=0
EXCLUDE=""

while getopts "d:w:l:o:x:sh" opt; do
    case $opt in
        d) MODE="single"; TARGET="$OPTARG" ;;
        w) MODE="wildcard"; TARGET="$OPTARG" ;;
        l) MODE="list"; TARGET="$OPTARG" ;;
        o) OUTDIR="$OPTARG" ;;
        s) QUICK=1 ;;
        x) EXCLUDE="$OPTARG" ;;
        h) show_help ;;
        *) show_help ;;
    esac
done

[ -z "$MODE" ] && show_help

# ============================================
# SETUP
# ============================================
banner
echo ""

DATE=$(date +%Y%m%d_%H%M%S)
DOMAIN_NAME=$(echo "$TARGET" | sed 's|https\?://||' | sed 's|/.*||' | tr '/' '_')
[ -z "$OUTDIR" ] && OUTDIR="output/${DOMAIN_NAME}_${DATE}"

mkdir -p "$OUTDIR"/{subdomains,live,urls,js,secrets,nuclei,takeover,ports,params,screenshots,final,logs}
cd "$OUTDIR"

# Logging
LOG_FILE="logs/recon.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Timer
START_TIME=$(date +%s)

echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Target : ${WHITE}$TARGET${NC}"
echo -e "${CYAN}║  Mode   : ${WHITE}$MODE${NC}"
echo -e "${CYAN}║  Output : ${WHITE}$OUTDIR${NC}"
echo -e "${CYAN}║  Start  : ${WHITE}$(date)${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
echo ""

# ============================================
# HELPER FUNCTIONS
# ============================================
phase_header() {
    echo ""
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${MAGENTA}▶ PHASE $1: $2${NC}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

log_step() {
    echo -e "${CYAN}[*]${NC} $1"
}

log_ok() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

count_lines() {
    [ -f "$1" ] && wc -l < "$1" || echo "0"
}

# Scope filter function
apply_scope_filter() {
    local input=$1
    local output=$2
    
    if [ -n "$EXCLUDE" ] && [ -f "../../$EXCLUDE" ]; then
        grep -vFf "../../$EXCLUDE" "$input" > "$output"
        log_warn "Scope filter applied (excluded OOS)"
    else
        cp "$input" "$output"
    fi
}

# ============================================
# PHASE 1: SUBDOMAIN ENUMERATION
# ============================================
phase_header "1" "SUBDOMAIN ENUMERATION"

if [ "$MODE" = "single" ]; then
    echo "$TARGET" > subdomains/all_subdomains.txt
    log_ok "Single domain mode - skip enumeration"
else
    # --- Passive Sources ---
    log_step "Subfinder (multi-source passive)..."
    subfinder -d "$TARGET" -all -silent -o subdomains/subfinder.txt 2>/dev/null
    log_ok "Subfinder: $(count_lines subdomains/subfinder.txt)"

    log_step "Assetfinder..."
    assetfinder --subs-only "$TARGET" 2>/dev/null > subdomains/assetfinder.txt
    log_ok "Assetfinder: $(count_lines subdomains/assetfinder.txt)"

    log_step "crt.sh (Certificate Transparency)..."
    curl -s "https://crt.sh/?q=%25.${TARGET}&output=json" 2>/dev/null | \
        jq -r '.[].name_value' 2>/dev/null | sed 's/\*\.//g' | \
        grep -E "\.${TARGET}$" | sort -u > subdomains/crtsh.txt
    log_ok "crt.sh: $(count_lines subdomains/crtsh.txt)"

    # Chaos (jika ada API)
    if [ -n "$CHAOS_KEY" ]; then
        log_step "Chaos (ProjectDiscovery)..."
        chaos -d "$TARGET" -silent -o subdomains/chaos.txt 2>/dev/null
        log_ok "Chaos: $(count_lines subdomains/chaos.txt)"
    fi

    # GitHub subdomains
    if [ -n "$GITHUB_TOKEN" ]; then
        log_step "GitHub subdomains search..."
        github-subdomains -d "$TARGET" -t "$GITHUB_TOKEN" -o subdomains/github.txt 2>/dev/null
        log_ok "GitHub: $(count_lines subdomains/github.txt)"
    fi

    # --- Active (Wildcard Only) ---
    if [ "$MODE" = "wildcard" ] && [ $QUICK -eq 0 ]; then
        log_step "DNS Bruteforce (puredns)..."
        if [ -f ~/wordlists/best-dns-wordlist.txt ]; then
            puredns bruteforce ~/wordlists/best-dns-wordlist.txt "$TARGET" \
                -r ~/wordlists/resolvers.txt \
                --rate-limit 2000 \
                -q > subdomains/bruteforce.txt 2>/dev/null
            log_ok "Bruteforce: $(count_lines subdomains/bruteforce.txt)"
        fi

        log_step "Permutation (alterx)..."
        cat subdomains/*.txt 2>/dev/null | sort -u | \
            alterx -silent 2>/dev/null | \
            dnsx -silent -r ~/w
                    log_step "Permutation (alterx)..."
        cat subdomains/*.txt 2>/dev/null | sort -u | \
            alterx -silent 2>/dev/null | \
            dnsx -silent -r ~/wordlists/resolvers.txt \
            -o subdomains/permutation.txt 2>/dev/null
        log_ok "Permutation: $(count_lines subdomains/permutation.txt)"
    fi

    # --- Merge & Resolve ---
    log_step "Merging all sources..."
    cat subdomains/*.txt 2>/dev/null | sort -u > subdomains/raw_all.txt
    
    log_step "DNS Resolution (dnsx)..."
    dnsx -l subdomains/raw_all.txt -silent -a -resp \
        -r ~/wordlists/resolvers.txt 2>/dev/null | \
        awk '{print $1}' | sort -u > subdomains/resolved.txt

    # Apply scope filter
    apply_scope_filter subdomains/resolved.txt subdomains/all_subdomains.txt
    
    TOTAL_SUB=$(count_lines subdomains/all_subdomains.txt)
    log_ok "Total unique resolved subdomains: ${WHITE}$TOTAL_SUB${NC}"
fi

# ============================================
# PHASE 2: LIVE HOST DETECTION
# ============================================
phase_header "2" "LIVE HOST DETECTION & FINGERPRINTING"

log_step "HTTPX - Probing live hosts (multi-port)..."
httpx -l subdomains/all_subdomains.txt \
    -ports 80,443,8080,8443,8000,8888,3000,5000,9000,9090 \
    -threads 50 \
    -rate-limit 100 \
    -timeout 10 \
    -silent \
    -status-code \
    -title \
    -tech-detect \
    -server \
    -content-length \
    -follow-redirects \
    -json \
    -o live/httpx_full.json 2>/dev/null

# Extract URLs
cat live/httpx_full.json 2>/dev/null | jq -r '.url' 2>/dev/null | sort -u > live/live_urls.txt

# Simple text version
httpx -l subdomains/all_subdomains.txt \
    -silent -status-code -title -tech-detect \
    -o live/live_summary.txt 2>/dev/null

TOTAL_LIVE=$(count_lines live/live_urls.txt)
log_ok "Live hosts: ${WHITE}$TOTAL_LIVE${NC}"

# Filter by status code untuk prioritas
log_step "Categorizing by status code..."
grep -E "\$200\$" live/live_summary.txt > live/status_200.txt 2>/dev/null
grep -E "\$30[1-8]\$" live/live_summary.txt > live/status_redirect.txt 2>/dev/null
grep -E "\$40[13]\$" live/live_summary.txt > live/status_403_401.txt 2>/dev/null
grep -E "\$500\$|\$502\$|\$503\$" live/live_summary.txt > live/status_5xx.txt 2>/dev/null

log_ok "200 OK: $(count_lines live/status_200.txt) | 403/401: $(count_lines live/status_403_401.txt) | 5xx: $(count_lines live/status_5xx.txt)"

# ============================================
# PHASE 3: SCREENSHOT (Visual Recon)
# ============================================
if [ $QUICK -eq 0 ] && [ $TOTAL_LIVE -lt 500 ]; then
    phase_header "3" "SCREENSHOT CAPTURE"
    log_step "Taking screenshots (gowitness)..."
    gowitness file -f live/live_urls.txt \
        --screenshot-path screenshots/ \
        --timeout 15 \
        --threads 5 2>/dev/null
    log_ok "Screenshots saved to screenshots/"
else
    log_warn "Skipped screenshot (too many targets or quick mode)"
fi

# ============================================
# PHASE 4: QUICK WINS - TAKEOVER, CORS, BYPASS
# ============================================
phase_header "4" "QUICK WINS SCAN"

# Subdomain Takeover
log_step "Subdomain Takeover Check (subzy + nuclei)..."
subzy run --targets subdomains/all_subdomains.txt \
    --hide_fails --concurrency 50 \
    > takeover/subzy_results.txt 2>/dev/null

nuclei -l live/live_urls.txt \
    -t ~/nuclei-templates/http/takeovers/ \
    -severity high,critical \
    -silent -rate-limit 50 \
    -o takeover/nuclei_takeover.txt 2>/dev/null

log_ok "Takeover check complete → takeover/"

# CORS Misconfiguration
log_step "CORS Misconfiguration Check..."
nuclei -l live/live_urls.txt \
    -t ~/nuclei-templates/http/misconfiguration/cors-misconfig.yaml \
    -silent -rate-limit 50 \
    -o nuclei/cors_misconfig.txt 2>/dev/null
log_ok "CORS check complete"

# 403/401 Bypass Check
if [ -s live/status_403_401.txt ]; then
    log_step "403/401 Bypass attempts..."
    awk '{print $1}' live/status_403_401.txt | \
        nuclei -t ~/nuclei-templates/http/miscellaneous/ \
        -tags bypass -silent \
        -o nuclei/403_bypass.txt 2>/dev/null
    log_ok "403 bypass check complete"
fi

# ============================================
# PHASE 5: PORT SCANNING
# ============================================
if [ $QUICK -eq 0 ]; then
    phase_header "5" "PORT SCANNING"
    log_step "Naabu - Top 1000 ports..."
    naabu -list subdomains/all_subdomains.txt \
        -top-ports 1000 \
        -rate 1000 \
        -silent \
        -o ports/open_ports.txt 2>/dev/null
    log_ok "Port scan: $(count_lines ports/open_ports.txt) open ports found"
fi

# ============================================
# PHASE 6: URL & ENDPOINT COLLECTION
# ============================================
phase_header "6" "URL & ENDPOINT COLLECTION"

log_step "Katana (active crawl)..."
katana -list live/live_urls.txt \
    -d 3 \
    -c 10 \
    -jc \
    -silent \
    -o urls/katana.txt 2>/dev/null
log_ok "Katana: $(count_lines urls/katana.txt)"

log_step "GAU (passive from wayback/otx/commoncrawl)..."
cat live/live_urls.txt | gau --threads 10 --subs 2>/dev/null > urls/gau.txt
log_ok "GAU: $(count_lines urls/gau.txt)"

log_step "Waybackurls..."
cat live/live_urls.txt | waybackurls 2>/dev/null > urls/wayback.txt
log_ok "Wayback: $(count_lines urls/wayback.txt)"

log_step "Hakrawler..."
cat live/live_urls.txt | hakrawler -d 2 -subs 2>/dev/null > urls/hakrawler.txt
log_ok "Hakrawler: $(count_lines urls/hakrawler.txt)"

# Merge & Deduplicate dengan uro
log_step "Merging & deduplicating URLs (uro)..."
cat urls/katana.txt urls/gau.txt urls/wayback.txt urls/hakrawler.txt 2>/dev/null | \
    sort -u | uro 2>/dev/null > urls/all_urls_dedup.txt

TOTAL_URL=$(count_lines urls/all_urls_dedup.txt)
log_ok "Total unique URLs (after uro): ${WHITE}$TOTAL_URL${NC}"

# Filter by extension
log_step "Filtering by extension..."
grep -iE "\.(js|jsx|mjs)($|\?)" urls/all_urls_dedup.txt | sort -u > urls/js_files.txt
grep -iE "\.(php|asp|aspx|jsp)($|\?)" urls/all_urls_dedup.txt > urls/dynamic_pages.txt
grep -iE "\.(json|xml|yaml|yml|config|conf|env|bak|backup|old|sql|db|log|txt|pdf|xls|xlsx|doc|docx)($|\?)" urls/all_urls_dedup.txt > urls/interesting_files.txt
grep -E "\?.*=" urls/all_urls_dedup.txt > urls/urls_with_params.txt

log_ok "JS files: $(count_lines urls/js_files.txt)"
log_ok "Dynamic pages: $(count_lines urls/dynamic_pages.txt)"
log_ok "Interesting files: $(count_lines urls/interesting_files.txt)"
log_ok "URLs with params: $(count_lines urls/urls_with_params.txt)"

# ============================================
# PHASE 7: JS DEEP ANALYSIS
# ============================================
phase_header "7" "JS DEEP ANALYSIS"

# Filter live JS files only
log_step "Filtering live JS files..."
httpx -l urls/js_files.txt -mc 200 -silent -threads 50 \
    -o js/js_live.txt 2>/dev/null
TOTAL_JS=$(count_lines js/js_live.txt)
log_ok "Live JS files: ${WHITE}$TOTAL_JS${NC}"

if [ $TOTAL_JS -gt 0 ]; then
    # Extract endpoints from JS using LinkFinder
    log_step "Extracting endpoints (LinkFinder)..."
    mkdir -p js/endpoints
    head -100 js/js_live.txt | while read -r jsurl; do
        filename=$(echo "$jsurl" | md5sum | cut -d' ' -f1)
        python3 ~/tools/LinkFinder/linkfinder.py -i "$jsurl" -o cli 2>/dev/null \
            >> js/endpoints/all_endpoints.txt
    done
    sort -u js/endpoints/all_endpoints.txt -o js/endpoints/all_endpoints.txt 2>/dev/null
    log_ok "Endpoints extracted: $(count_lines js/endpoints/all_endpoints.txt)"

    # SecretFinder - Deep secret search
    log_step "SecretFinder - searching secrets in JS..."
    mkdir -p js/secretfinder
    head -50 js/js_live.txt | while read -r jsurl; do
        python3 ~/tools/SecretFinder/SecretFinder.py \
            -i "$jsurl" -o cli 2>/dev/null \
            >> js/secretfinder/results.txt
    done
    log_ok "SecretFinder done"

    # Mantra - API keys hunter
    log_step "Mantra - API key hunting..."
    cat js/js_live.txt | mantra 2>/dev/null > js/mantra_results.txt
    log_ok "Mantra done: $(count_lines js/mantra_results.txt)"

    # Trufflehog on JS URLs
    log_step "Trufflehog - verified secrets..."
    head -30 js/js_live.txt | while read -r jsurl; do
        trufflehog --no-update --only-verified "$jsurl" 2>/dev/null \
            >> js/trufflehog_verified.txt
    done
    log_ok "Trufflehog done"

    # Nuclei expos
        # Nuclei exposures khusus JS
    log_step "Nuclei - JS exposures & tokens..."
    nuclei -l js/js_live.txt \
        -t ~/nuclei-templates/http/exposures/ \
        -t ~/nuclei-templates/http/token-spray/ \
        -silent -rate-limit 100 \
        -o js/nuclei_js_exposures.txt 2>/dev/null
    log_ok "Nuclei JS scan done"
fi

# ============================================
# PHASE 8: SECRETS & INFORMATION DISCLOSURE
# ============================================
phase_header "8" "SECRETS & INFO DISCLOSURE"

# Common sensitive paths check
log_step "Checking sensitive paths..."
cat > /tmp/sensitive_paths.txt << 'EOF'
/.git/config
/.git/HEAD
/.env
/.env.local
/.env.production
/.env.development
/.env.backup
/config.json
/config.yml
/config.yaml
/settings.json
/backup.sql
/backup.zip
/database.sql
/db.sql
/dump.sql
/.aws/credentials
/.ssh/id_rsa
/.npmrc
/.dockerconfigjson
/phpinfo.php
/info.php
/test.php
/server-status
/server-info
/.DS_Store
/robots.txt
/sitemap.xml
/swagger.json
/swagger.yaml
/api-docs
/api/swagger
/v1/swagger
/v2/swagger
/openapi.json
/.htaccess
/.htpasswd
/wp-config.php.bak
/web.config
/composer.json
/package.json
/package-lock.json
/yarn.lock
/.travis.yml
/.circleci/config.yml
/.gitlab-ci.yml
/Dockerfile
/docker-compose.yml
/.vscode/settings.json
/.idea/workspace.xml
/README.md
/CHANGELOG.md
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
EOF

# Generate full URLs
> secrets/sensitive_urls_to_check.txt
while IFS= read -r host; do
    while IFS= read -r path; do
        echo "${host}${path}"
    done < /tmp/sensitive_paths.txt
done < live/live_urls.txt >> secrets/sensitive_urls_to_check.txt

log_step "Probing sensitive files..."
httpx -l secrets/sensitive_urls_to_check.txt \
    -mc 200,403 \
    -mr "Index of|root:|DB_PASSWORD|api[_-]?key|secret|BEGIN RSA|BEGIN OPENSSH|mysql_|AKIA[0-9A-Z]{16}" \
    -silent -threads 50 \
    -o secrets/exposed_files.txt 2>/dev/null

log_ok "Exposed files found: $(count_lines secrets/exposed_files.txt)"

# Check .git exposed
log_step "Checking .git exposure..."
httpx -l live/live_urls.txt -path "/.git/config" \
    -mc 200 -mr "repositoryformatversion" \
    -silent -o secrets/git_exposed.txt 2>/dev/null
[ -s secrets/git_exposed.txt ] && log_ok "⚠️  .git EXPOSED: $(count_lines secrets/git_exposed.txt) targets"

# Check .env exposed
log_step "Checking .env exposure..."
httpx -l live/live_urls.txt -path "/.env" \
    -mc 200 -mr "APP_|DB_|API_|SECRET" \
    -silent -o secrets/env_exposed.txt 2>/dev/null
[ -s secrets/env_exposed.txt ] && log_ok "⚠️  .env EXPOSED: $(count_lines secrets/env_exposed.txt) targets"

# ============================================
# PHASE 9: PARAMETER DISCOVERY
# ============================================
phase_header "9" "PARAMETER DISCOVERY"

if command -v gf &> /dev/null; then
    log_step "GF Patterns - categorizing URLs by vuln type..."
    
    cat urls/all_urls_dedup.txt | gf xss 2>/dev/null | sort -u > params/xss_candidates.txt
    cat urls/all_urls_dedup.txt | gf sqli 2>/dev/null | sort -u > params/sqli_candidates.txt
    cat urls/all_urls_dedup.txt | gf ssrf 2>/dev/null | sort -u > params/ssrf_candidates.txt
    cat urls/all_urls_dedup.txt | gf lfi 2>/dev/null | sort -u > params/lfi_candidates.txt
    cat urls/all_urls_dedup.txt | gf rce 2>/dev/null | sort -u > params/rce_candidates.txt
    cat urls/all_urls_dedup.txt | gf redirect 2>/dev/null | sort -u > params/redirect_candidates.txt
    cat urls/all_urls_dedup.txt | gf ssti 2>/dev/null | sort -u > params/ssti_candidates.txt
    cat urls/all_urls_dedup.txt | gf idor 2>/dev/null | sort -u > params/idor_candidates.txt
    cat urls/all_urls_dedup.txt | gf debug_logic 2>/dev/null | sort -u > params/debug_candidates.txt
    cat urls/all_urls_dedup.txt | gf interestingparams 2>/dev/null | sort -u > params/interesting_params.txt
    
    log_ok "XSS: $(count_lines params/xss_candidates.txt)"
    log_ok "SQLi: $(count_lines params/sqli_candidates.txt)"
    log_ok "SSRF: $(count_lines params/ssrf_candidates.txt)"
    log_ok "LFI: $(count_lines params/lfi_candidates.txt)"
    log_ok "RCE: $(count_lines params/rce_candidates.txt)"
    log_ok "Open Redirect: $(count_lines params/redirect_candidates.txt)"
    log_ok "SSTI: $(count_lines params/ssti_candidates.txt)"
fi

# Arjun - hidden parameter discovery (sample only untuk hemat waktu)
if command -v arjun &> /dev/null && [ $QUICK -eq 0 ]; then
    log_step "Arjun - discovering hidden parameters (top 30)..."
    head -30 live/live_urls.txt > /tmp/arjun_input.txt
    arjun -i /tmp/arjun_input.txt \
        -oJ params/arjun_results.json \
        -t 10 --stable 2>/dev/null
    log_ok "Arjun done"
fi

# ============================================
# PHASE 10: NUCLEI VULNERABILITY SCANNING
# ============================================
phase_header "10" "NUCLEI VULNERABILITY SCAN"

# Stage 1: Critical & High CVEs
log_step "Stage 1/5: Critical & High CVEs..."
nuclei -l live/live_urls.txt \
    -t ~/nuclei-templates/http/cves/ \
    -severity critical,high \
    -rate-limit 150 \
    -c 25 \
    -silent \
    -o nuclei/01_cves_critical_high.txt 2>/dev/null
log_ok "Stage 1 done"

# Stage 2: Misconfigurations
log_step "Stage 2/5: Misconfigurations..."
nuclei -l live/live_urls.txt \
    -t ~/nuclei-templates/http/misconfiguration/ \
    -severity medium,high,critical \
    -rate-limit 150 \
    -silent \
    -o nuclei/02_misconfigurations.txt 2>/dev/null
log_ok "Stage 2 done"

# Stage 3: Exposures
log_step "Stage 3/5: Exposures..."
nuclei -l live/live_urls.txt \
    -t ~/nuclei-templates/http/exposures/ \
    -rate-limit 150 \
    -silent \
    -o nuclei/03_exposures.txt 2>/dev/null
log_ok "Stage 3 done"

# Stage 4: Default Logins
log_step "Stage 4/5: Default Logins..."
nuclei -l live/live_urls.txt \
    -t ~/nuclei-templates/http/default-logins/ \
    -rate-limit 100 \
    -silent \
    -o nuclei/04_default_logins.txt 2>/dev/null
log_ok "Stage 4 done"

# Stage 5: Vulnerabilities & Auth Bypass
log_step "Stage 5/5: Vulnerabilities & Auth Bypass..."
nuclei -l live/live_urls.txt \
    -t ~/nuclei-templates/http/vulnerabilities/ \
    -severity medium,high,critical \
    -rate-limit 150 \
    -silent \
    -o nuclei/05_vulnerabilities.txt 2>/dev/null
log_ok "Stage 5 done"

# Custom fuzzing templates (deep mode only)
if [ $QUICK -eq 0 ] && [ -d ~/tools/fuzzing-templates ]; then
    log_step "BONUS: Fuzzing templates on URLs with params..."
    if [ -s urls/urls_with_params.txt ]; then
        head -500 urls/urls_with_params.txt | \
            nuclei -t ~/tools/fuzzing-templates/ \
            -severity medium,high,critical \
            -rate-limit 100 \
            -silent \
            -o nuclei/06_fuzzing_results.txt 2>/dev/null
        log_ok "Fuzzing done"
    fi
fi

# ============================================
# PHASE 11: REPORTING
# ============================================
phase_header "11" "GENERATING REPORT"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
HOURS=$((DURATION / 3600))
MINUTES=$(( (DURATION % 3600) / 60 ))
SECONDS=$((DURATION % 60))

# Count findings
CRITICAL=$(grep -c "\$critical\$" nuclei/*.txt 2>/dev/null | awk -F: '{sum+=$2} END {print sum}')
HIGH=$(grep -c "\$high\$" nuclei/*.txt 2>/dev/null | awk -F: '{sum+=$2} END {print sum}')
MEDIUM=$(grep -c "\$medium\$" nuclei/*.txt 2>/dev/null | awk -F: '{sum+=$2} END {print sum}')
LOW=$(grep -c "\$low\$" nuclei/*.txt 2>/dev/null | awk -F: '{sum+=$2} END {print sum}')
INFO=$(grep -c "\$info\$" nuclei/*.txt 2>/dev/null | awk -F: '{sum+=$2} END {print sum}')

# Merge all critical/high findings to priority file
log_step "Creating priority findings file..."
{
    echo "=== CRITICAL FINDINGS ==="
    grep -h "\$critical\$" nuclei/*.txt 2>/dev/null
    echo ""
    echo "=== HIGH FINDINGS ==="
    grep -h "\$high\$" nuclei/*.txt 2>/dev/null
    echo ""
    echo "=== TAKEOVER CANDIDATES ==="
    cat takeover/*.txt 2
        echo "=== TAKEOVER CANDIDATES ==="
    cat takeover/*.txt 2>/dev/null
    echo ""
    echo "=== EXPOSED SECRETS ==="
    cat secrets/env_exposed.txt secrets/git_exposed.txt 2>/dev/null
    echo ""
    echo "=== JS SECRETS (Mantra) ==="
    cat js/mantra_results.txt 2>/dev/null
    echo ""
    echo "=== TRUFFLEHOG VERIFIED ==="
    cat js/trufflehog_verified.txt 2>/dev/null
} > final/PRIORITY_FINDINGS.txt

# ============================================
# GENERATE JSON REPORT
# ============================================
log_step "Generating JSON report..."

cat > final/report.json << EOF
{
  "scan_info": {
    "target": "$TARGET",
    "mode": "$MODE",
    "start_time": "$(date -d @$START_TIME '+%Y-%m-%d %H:%M:%S')",
    "end_time": "$(date -d @$END_TIME '+%Y-%m-%d %H:%M:%S')",
    "duration_seconds": $DURATION,
    "duration_human": "${HOURS}h ${MINUTES}m ${SECONDS}s",
    "output_directory": "$OUTDIR",
    "version": "$VERSION"
  },
  "statistics": {
    "subdomains": {
      "total_found": $(count_lines subdomains/raw_all.txt),
      "resolved": $(count_lines subdomains/resolved.txt),
      "in_scope": $(count_lines subdomains/all_subdomains.txt)
    },
    "live_hosts": {
      "total": $TOTAL_LIVE,
      "status_200": $(count_lines live/status_200.txt),
      "status_403_401": $(count_lines live/status_403_401.txt),
      "status_5xx": $(count_lines live/status_5xx.txt)
    },
    "urls": {
      "total_deduped": $TOTAL_URL,
      "js_files": $(count_lines urls/js_files.txt),
      "live_js": $(count_lines js/js_live.txt),
      "with_params": $(count_lines urls/urls_with_params.txt),
      "interesting_files": $(count_lines urls/interesting_files.txt)
    },
    "vulnerabilities": {
      "critical": ${CRITICAL:-0},
      "high": ${HIGH:-0},
      "medium": ${MEDIUM:-0},
      "low": ${LOW:-0},
      "info": ${INFO:-0}
    },
    "vuln_candidates": {
      "xss": $(count_lines params/xss_candidates.txt),
      "sqli": $(count_lines params/sqli_candidates.txt),
      "ssrf": $(count_lines params/ssrf_candidates.txt),
      "lfi": $(count_lines params/lfi_candidates.txt),
      "rce": $(count_lines params/rce_candidates.txt),
      "open_redirect": $(count_lines params/redirect_candidates.txt),
      "ssti": $(count_lines params/ssti_candidates.txt)
    },
    "secrets": {
      "env_exposed": $(count_lines secrets/env_exposed.txt),
      "git_exposed": $(count_lines secrets/git_exposed.txt),
      "sensitive_files": $(count_lines secrets/exposed_files.txt)
    },
    "takeover_candidates": $(count_lines takeover/subzy_results.txt)
  },
  "priority_files": {
    "critical_findings": "final/PRIORITY_FINDINGS.txt",
    "all_subdomains": "subdomains/all_subdomains.txt",
    "live_urls": "live/live_urls.txt",
    "nuclei_results": "nuclei/",
    "js_secrets": "js/",
    "params_for_manual": "params/"
  }
}
EOF

log_ok "JSON report: final/report.json"

# ============================================
# GENERATE HTML REPORT (BONUS)
# ============================================
log_step "Generating HTML summary..."

cat > final/report.html << HTMLEOF
<!DOCTYPE html>
<html>
<head>
<title>Recon Report - $TARGET</title>
<style>
body{font-family:Arial,sans-serif;background:#1a1a1a;color:#e0e0e0;padding:20px;max-width:1200px;margin:auto}
h1{color:#00ff88;border-bottom:2px solid #00ff88;padding-bottom:10px}
h2{color:#00d4ff;margin-top:30px}
.card{background:#2a2a2a;padding:15px;margin:10px 0;border-radius:8px;border-left:4px solid #00ff88}
.critical{border-left-color:#ff0040}
.high{border-left-color:#ff6b00}
.medium{border-left-color:#ffcc00}
.low{border-left-color:#00d4ff}
table{width:100%;border-collapse:collapse;margin:10px 0}
th,td{padding:10px;text-align:left;border-bottom:1px solid #444}
th{background:#333;color:#00ff88}
.num{font-size:28px;font-weight:bold;color:#00ff88}
.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:15px}
</style>
</head>
<body>
<h1>🔍 Bug Hunter Recon Report</h1>
<div class="card">
<strong>Target:</strong> $TARGET<br>
<strong>Mode:</strong> $MODE<br>
<strong>Duration:</strong> ${HOURS}h ${MINUTES}m ${SECONDS}s<br>
<strong>Date:</strong> $(date)
</div>

<h2>📊 Quick Stats</h2>
<div class="grid">
<div class="card"><div class="num">$(count_lines subdomains/all_subdomains.txt)</div>Subdomains</div>
<div class="card"><div class="num">$TOTAL_LIVE</div>Live Hosts</div>
<div class="card"><div class="num">$TOTAL_URL</div>Unique URLs</div>
<div class="card"><div class="num">$(count_lines js/js_live.txt)</div>Live JS Files</div>
</div>

<h2>🚨 Vulnerabilities Found</h2>
<table>
<tr><th>Severity</th><th>Count</th></tr>
<tr><td>🔴 Critical</td><td>${CRITICAL:-0}</td></tr>
<tr><td>🟠 High</td><td>${HIGH:-0}</td></tr>
<tr><td>🟡 Medium</td><td>${MEDIUM:-0}</td></tr>
<tr><td>🔵 Low</td><td>${LOW:-0}</td></tr>
<tr><td>⚪ Info</td><td>${INFO:-0}</td></tr>
</table>

<h2>🎯 Attack Surface</h2>
<table>
<tr><th>Type</th><th>Count</th></tr>
<tr><td>XSS Candidates</td><td>$(count_lines params/xss_candidates.txt)</td></tr>
<tr><td>SQLi Candidates</td><td>$(count_lines params/sqli_candidates.txt)</td></tr>
<tr><td>SSRF Candidates</td><td>$(count_lines params/ssrf_candidates.txt)</td></tr>
<tr><td>LFI Candidates</td><td>$(count_lines params/lfi_candidates.txt)</td></tr>
<tr><td>Open Redirect</td><td>$(count_lines params/redirect_candidates.txt)</td></tr>
<tr><td>Takeover Candidates</td><td>$(count_lines takeover/subzy_results.txt)</td></tr>
<tr><td>.env Exposed</td><td>$(count_lines secrets/env_exposed.txt)</td></tr>
<tr><td>.git Exposed</td><td>$(count_lines secrets/git_exposed.txt)</td></tr>
</table>

<h2>📁 Important Files</h2>
<ul>
<li><code>final/PRIORITY_FINDINGS.txt</code> - Baca ini dulu!</li>
<li><code>nuclei/</code> - Semua hasil nuclei</li>
<li><code>js/</code> - JS analysis (secrets, endpoints)</li>
<li><code>params/</code> - URL untuk manual testing</li>
<li><code>screenshots/</code> - Visual recon</li>
</ul>

<h2>💡 Next Steps (Manual Testing)</h2>
<ol>
<li>Buka <code>final/PRIORITY_FINDINGS.txt</code> - validasi tiap finding</li>
<li>Review <code>js/mantra_results.txt</code> & <code>js/trufflehog_verified.txt</code></li>
<li>Test XSS candidates dengan <code>dalfox</code></li>
<li>Test SQLi candidates dengan <code>sqlmap</code></li>
<li>Test SSRF candidates manual (Burp Collaborator)</li>
<li>Review screenshots untuk visual anomaly</li>
<li>Cek <code>secrets/env_exposed.txt</code> & <code>secrets/git_exposed.txt</code></li>
</ol>

</body>
</html>
HTMLEOF

log_ok "HTML report: final/report.html"

# ============================================
# FINAL SUMMARY
# ============================================
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           ✓ RECON COMPLETE!                        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}⏱️  Duration: ${WHITE}${HOURS}h ${MINUTES}m ${SECONDS}s${NC}"
echo -e "${CYAN}📁 Output  : ${WHITE}$OUTDIR${NC}"
echo ""
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}📊 SUMMARY STATISTICS${NC}"
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
printf "   %-30s ${WHITE}%s${NC}\n" "Subdomains resolved:" "$(count_lines subdomains/all_subdomains.txt)"
printf "   %-30s ${WHITE}%s${NC}\n" "Live hosts:" "$TOTAL_LIVE"
printf "   %-30s ${WHITE}%s${NC}\n" "Unique URLs:" "$TOTAL_URL"
printf "   %-30s ${WHITE}%s${NC}\n" "Live JS files:" "$(count_lines js/js_live.txt)"
echo ""
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🚨 VULNERABILITIES${NC}"
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
printf "   ${RED}%-30s %s${NC}\n" "🔴 Critical:" "${CRITICAL:-0}"
printf "   ${YELLOW}%-30s %s${NC}\n" "🟠 High:" "${HIGH:-0}"
printf "   ${YELLOW}%-30s %s${NC}\n" "🟡 Medium:" "${MEDIUM:-0}"
printf "   ${BLUE}%-30s %s${NC}\n" "🔵 Low:" "${LOW:-0}"
printf "   %-30s %s\n" "⚪ Info:" "${INFO:-0}"
echo ""
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🎯 ATTACK SURFACE${NC}"
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
printf "   %-30s ${WHITE}%s${NC}\n" "XSS candidates:" "$(count_lines params/xss_candidates.txt)"
printf "   %-30s ${WHITE}%s${NC}\n" "SQLi candidates:" "$(count_lines params/sqli_candidates.txt)"
printf "   %-30s ${WHITE}%s${NC}\n" "SSRF candidates:" "$(count_lines params/ssrf_candidates.txt)"
printf "   %-30s ${WHITE}%s${NC}\n" "LFI candidates:" "$(count_lines params/lfi_candidates.txt)"
printf "   %-30s ${WHITE}%s${NC}\n" "Open redirect:" "$(count_lines params/redirect_candidates.txt)"
printf "   %-30s ${WHITE}%s${NC}\n" "Takeover candidates:" "$(count_lines takeover/subzy_results.txt)"
printf "   ${RED}%-30s %s${NC}\n" ".env exposed:" "$(count_lines secrets/env_exposed.txt)"
printf "   ${RED}%-30s %s${NC}\n" ".git exposed:" "$(count_lines secrets/git_exposed.txt)"
echo ""
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}📋 NEXT STEPS - MANUAL REVIEW${NC}"
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  1.${NC} cat ${WHITE}$OUTDIR/final/PRIORITY_FINDINGS.txt${NC}"
echo -e "${CYAN}  2.${NC} Review ${WHITE}$OUTDIR/final/report.html${NC} (buka di browser)"
echo -e "${CYAN}  3.${NC} Check secrets: ${WHITE}$OUTDIR/js/mantra_results.txt${NC}"
echo -e "${CYAN}  4.${NC} Verified secrets: ${WHITE}$OUTDIR/js/trufflehog_verified.txt${NC}"
echo -e "${CYAN}  5.${NC} Manual test XSS: ${WHITE}dalfox file $OUTDIR/params/xss_candidates.txt${NC}"
echo -e "${CYAN}  6.${NC} Manual test SQLi: ${WHITE}sqlmap -m $OUTDIR/params/sqli_candidates.txt${NC}"
echo ""
echo -e "${GREEN}💰 Happy Hunting! Good luck finding bugs! 🐛${NC}"
echo ""
