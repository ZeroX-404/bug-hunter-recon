#!/bin/bash
# ============================================================
# API Keys Setup Wizard - AMAN & LENGKAP
# Bug Hunter Recon v2.2
# ============================================================

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Inisialisasi semua variabel API ke string kosong
# Supaya tidak unbound kalau user skip
CHAOS_KEY=""
GITHUB_TOKEN=""
VT_KEY=""
SHODAN_KEY=""
ST_KEY=""
URLSCAN_KEY=""
CENSYS_ID=""
CENSYS_SECRET=""
BE_KEY=""
FH_KEY=""
LEAKIX_KEY=""
NETLAS_KEY=""
BEVIGIL_KEY=""
DISCORD_WEBHOOK=""

clear

echo -e "${CYAN}"
cat << "BANNER"
╔══════════════════════════════════════════════════╗
║          🔐 API KEYS SETUP WIZARD 🔐             ║
║                                                  ║
║   API keys akan disimpan AMAN di local kamu:    ║
║   ~/.config/subfinder/provider-config.yaml       ║
║                                                  ║
║   ⚠️  JANGAN share file ini ke siapapun!        ║
╚══════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

echo ""
echo -e "${YELLOW}[!] Tekan ENTER untuk SKIP API yang tidak kamu punya${NC}"
echo -e "${YELLOW}[!] Bisa di-update kapan saja dengan jalankan script ini lagi${NC}"
echo ""

read -p "$(echo -e ${CYAN}Lanjutkan? [y/N]: ${NC})" confirm

if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}[!] Cancelled${NC}"
    exit 0
fi

# Buat folder config
mkdir -p ~/.config/subfinder
mkdir -p ~/.config/recon

CONFIG_FILE="$HOME/.config/subfinder/provider-config.yaml"
RECON_ENV="$HOME/.config/recon/.env"

# Backup jika sudah ada
if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%s)"
    echo -e "${GREEN}[✓] Backup config lama disimpan${NC}"
fi

# ============================================
# FUNCTIONS
# ============================================
input_api() {
    local service=$1
    local url=$2
    local description=$3
    local var_name=$4

    echo ""
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}▸ ${service}${NC}"
    echo -e "${YELLOW}  📝 ${description}${NC}"
    echo -e "${YELLOW}  🔗 Daftar: ${url}${NC}"
    echo ""
    read -rp "$(echo -e "${GREEN}  API Key [ENTER untuk skip]: ${NC}")" key

    if [ -n "$key" ]; then
        # Pakai printf + read ke variabel — aman dari injection
        printf -v "$var_name" '%s' "$key"
        echo -e "${GREEN}  ✓ Tersimpan${NC}"
    else
        echo -e "${YELLOW}  ⊘ Skipped${NC}"
    fi
}

input_api_double() {
    local service=$1
    local url=$2

    echo ""
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}▸ ${service}${NC}"
    echo -e "${YELLOW}  🔗 Daftar: ${url}${NC}"
    echo ""
    read -rp "$(echo -e "${GREEN}  API ID [ENTER skip]: ${NC}")" v1

    if [ -n "$v1" ]; then
        read -rp "$(echo -e "${GREEN}  API Secret: ${NC}")" v2
        CENSYS_ID="$v1"
        CENSYS_SECRET="$v2"
        echo -e "${GREEN}  ✓ Tersimpan${NC}"
    else
        echo -e "${YELLOW}  ⊘ Skipped${NC}"
    fi
}

# ============================================
# TIER 1 - WAJIB
# ============================================
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
echo -e "${CYAN}  TIER 1 - WAJIB (Paling Berdampak)${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════${NC}"

input_api "Chaos (ProjectDiscovery)" \
    "https://chaos.projectdiscovery.io/" \
    "UNLIMITED free - paling recommended!" \
    "CHAOS_KEY"

input_api "GitHub Personal Access Token" \
    "https://github.com/settings/tokens" \
    "Scope: public_repo (centang saja itu)" \
    "GITHUB_TOKEN"

input_api "VirusTotal" \
    "https://www.virustotal.com/gui/my-apikey" \
    "500 req/day - lumayan powerful" \
    "VT_KEY"

input_api "Shodan" \
    "https://account.shodan.io/" \
    "100 query credits free" \
    "SHODAN_KEY"

input_api "SecurityTrails" \
    "https://securitytrails.com/app/account/credentials" \
    "50 query/bulan free" \
    "ST_KEY"

input_api "URLScan.io" \
    "https://urlscan.io/user/profile/" \
    "1000/day free" \
    "URLSCAN_KEY"

echo ""
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}▸ Discord Webhook (untuk notifikasi critical finding)${NC}"
echo -e "${YELLOW}  📝 Recon akan ping Discord saat nemu critical/exposed secrets${NC}"
echo -e "${YELLOW}  🔗 Buat: Discord Server → Edit Channel → Integrations → Webhooks${NC}"
echo ""
read -rp "$(echo -e "${GREEN}  Webhook URL [ENTER untuk skip]: ${NC}")" DISCORD_WEBHOOK
[ -n "$DISCORD_WEBHOOK" ] && echo -e "${GREEN}  ✓ Tersimpan${NC}" || echo -e "${YELLOW}  ⊘ Skipped${NC}"

# ============================================
# TIER 2 - OPTIONAL
# ============================================
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
echo -e "${CYAN}  TIER 2 - OPTIONAL (Tambahan)${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════${NC}"

input_api_double "Censys" \
    "https://search.censys.io/account/api"

input_api "BinaryEdge" \
    "https://app.binaryedge.io/account/api" \
    "250/bulan free" \
    "BE_KEY"

input_api "FullHunt" \
    "https://fullhunt.io/user/settings" \
    "100/bulan free" \
    "FH_KEY"

input_api "LeakIX" \
    "https://leakix.net/" \
    "Misconfig & leak detection" \
    "LEAKIX_KEY"

input_api "Netlas" \
    "https://app.netlas.io/profile/" \
    "50/day free" \
    "NETLAS_KEY"

input_api "BeVigil" \
    "https://bevigil.com/" \
    "Mobile app intel - optional" \
    "BEVIGIL_KEY"

# ============================================
# WRITE CONFIG FILE - SUBFINDER
# ============================================
echo ""
echo -e "${YELLOW}[+] Menulis konfigurasi...${NC}"

# Create subfinder config
{
    echo "# Subfinder Provider Config"
    echo "# Generated by Bug Hunter Recon Setup Wizard"
    echo "# Date: $(date)"
    echo ""
    
    if [ -n "$CHAOS_KEY" ]; then
        echo "chaos:"
        echo "  - ${CHAOS_KEY}"
        echo ""
    fi
    
    if [ -n "$GITHUB_TOKEN" ]; then
        echo "github:"
        echo "  - ${GITHUB_TOKEN}"
        echo ""
    fi
    
    if [ -n "$VT_KEY" ]; then
        echo "virustotal:"
        echo "  - ${VT_KEY}"
        echo ""
    fi
    
    if [ -n "$SHODAN_KEY" ]; then
        echo "shodan:"
        echo "  - ${SHODAN_KEY}"
        echo ""
    fi
    
    if [ -n "$ST_KEY" ]; then
        echo "securitytrails:"
        echo "  - ${ST_KEY}"
        echo ""
    fi
    
    if [ -n "$URLSCAN_KEY" ]; then
        echo "urlscan:"
        echo "  - ${URLSCAN_KEY}"
        echo ""
    fi
    
    if [ -n "$CENSYS_ID" ]; then
        echo "censys:"
        echo "  - ${CENSYS_ID}:${CENSYS_SECRET}"
        echo ""
    fi
    
    if [ -n "$BE_KEY" ]; then
        echo "binaryedge:"
        echo "  - ${BE_KEY}"
        echo ""
    fi
    
    if [ -n "$FH_KEY" ]; then
        echo "fullhunt:"
        echo "  - ${FH_KEY}"
        echo ""
    fi
    
    if [ -n "$LEAKIX_KEY" ]; then
        echo "leakix:"
        echo "  - ${LEAKIX_KEY}"
        echo ""
    fi
    
    if [ -n "$NETLAS_KEY" ]; then
        echo "netlas:"
        echo "  - ${NETLAS_KEY}"
        echo ""
    fi
    
    if [ -n "$BEVIGIL_KEY" ]; then
        echo "bevigil:"
        echo "  - ${BEVIGIL_KEY}"
    fi
} > "$CONFIG_FILE"

chmod 600 "$CONFIG_FILE"

# ============================================
# WRITE ENV FILE
# ============================================
{
    echo "# Bug Hunter Recon - Environment Variables"
    echo "# AUTO-GENERATED - Jangan commit ke git!"
    echo "# Date: $(date)"
    echo ""
    echo "export CHAOS_KEY=\"${CHAOS_KEY}\""
    echo "export GITHUB_TOKEN=\"${GITHUB_TOKEN}\""
    echo "export VT_API_KEY=\"${VT_KEY}\""
    echo "export SHODAN_API_KEY=\"${SHODAN_KEY}\""
    echo "export SECURITYTRAILS_KEY=\"${ST_KEY}\""
    echo "export URLSCAN_KEY=\"${URLSCAN_KEY}\""
    echo "export CENSYS_API_ID=\"${CENSYS_ID}\""
    echo "export CENSYS_API_SECRET=\"${CENSYS_SECRET}\""
    echo "export BINARYEDGE_KEY=\"${BE_KEY}\""
    echo "export FULLHUNT_KEY=\"${FH_KEY}\""
    echo "export LEAKIX_KEY=\"${LEAKIX_KEY}\""
    echo "export NETLAS_KEY=\"${NETLAS_KEY}\""
    echo "export BEVIGIL_KEY=\"${BEVIGIL_KEY}\""
    echo "export DISCORD_WEBHOOK=\"${DISCORD_WEBHOOK}\""
} > "$RECON_ENV"

chmod 600 "$RECON_ENV"

# ============================================
# AUTO-SOURCE IN BASHRC
# ============================================
if ! grep -q "recon/.env" ~/.bashrc; then
    echo "" >> ~/.bashrc
    echo "# Bug Hunter Recon API Keys" >> ~/.bashrc
    echo "[ -f ~/.config/recon/.env ] && source ~/.config/recon/.env" >> ~/.bashrc
fi

# ============================================
# SUMMARY
# ============================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         ✓ SETUP COMPLETE!                ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}📁 Config tersimpan di:${NC}"
echo -e "   ${YELLOW}• ~/.config/subfinder/provider-config.yaml${NC}"
echo -e "   ${YELLOW}• ~/.config/recon/.env${NC}"
echo ""
echo -e "${CYAN}🔒 Permission: 600 (hanya kamu yang bisa baca)${NC}"
echo ""

# Hitung berapa API yang terisi
count=0
[ -n "$CHAOS_KEY" ] && count=$((count + 1))
[ -n "$GITHUB_TOKEN" ] && count=$((count + 1))
[ -n "$VT_KEY" ] && count=$((count + 1))
[ -n "$SHODAN_KEY" ] && count=$((count + 1))
[ -n "$ST_KEY" ] && count=$((count + 1))
[ -n "$URLSCAN_KEY" ] && count=$((count + 1))
[ -n "$CENSYS_ID" ] && count=$((count + 1))
[ -n "$BE_KEY" ] && count=$((count + 1))
[ -n "$FH_KEY" ] && count=$((count + 1))
[ -n "$LEAKIX_KEY" ] && count=$((count + 1))
[ -n "$NETLAS_KEY" ] && count=$((count + 1))
[ -n "$BEVIGIL_KEY" ] && count=$((count + 1))
[ -n "$DISCORD_WEBHOOK" ] && count=$((count + 1))

echo -e "${GREEN}✓ Total API terdaftar: ${count}${NC}"
echo ""
echo -e "${YELLOW}[!] Jalankan perintah ini untuk load API keys:${NC}"
echo -e "${CYAN}   source ~/.bashrc${NC}"
echo ""
echo -e "${YELLOW}[!] Lalu mulai recon:${NC}"
echo -e "${CYAN}   ./recon.sh -w target.com${NC}"
echo ""
echo -e "${GREEN}💰 Happy Hunting! 🐛${NC}"
