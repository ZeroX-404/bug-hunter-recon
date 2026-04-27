#!/bin/bash
# ============================================
# Bug Hunter Recon - Auto Installer (Debian)
# Version: 2.0.1 (FIXED)
# ============================================

set -e

# Disable git interactive prompts
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/true

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Bug Hunter Recon - Installer v2.0.1  ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"

# ============================================
# BASE PACKAGES
# ============================================
echo -e "${YELLOW}[+] Installing base packages...${NC}"
sudo apt update
sudo apt install -y git curl wget unzip jq python3 python3-pip python3-venv \
    build-essential libpcap-dev chromium dnsutils make ruby-full nmap

# ============================================
# GO INSTALLATION
# ============================================
if ! command -v go &> /dev/null; then
    echo -e "${YELLOW}[+] Installing Go 1.22...${NC}"
    wget -q https://go.dev/dl/go1.22.0.linux-amd64.tar.gz -O /tmp/go.tar.gz
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf /tmp/go.tar.gz
    
    if ! grep -q "/usr/local/go/bin" ~/.bashrc; then
        echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bashrc
    fi
    export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
fi

# Pastikan PATH terload
export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin

mkdir -p ~/go/bin ~/tools ~/wordlists ~/.config/recon ~/bug-hunter-recon/{config,utils,output}

# ============================================
# GO TOOLS
# ============================================
echo -e "${YELLOW}[+] Installing Go tools (butuh waktu ~15 menit)...${NC}"

declare -A GO_TOOLS=(
    ["subfinder"]="github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
    ["httpx"]="github.com/projectdiscovery/httpx/cmd/httpx@latest"
    ["nuclei"]="github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
    ["katana"]="github.com/projectdiscovery/katana/cmd/katana@latest"
    ["naabu"]="github.com/projectdiscovery/naabu/v2/cmd/naabu@latest"
    ["dnsx"]="github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
    ["alterx"]="github.com/projectdiscovery/alterx/cmd/alterx@latest"
    ["chaos"]="github.com/projectdiscovery/chaos-client/cmd/chaos@latest"
    ["mapcidr"]="github.com/projectdiscovery/mapcidr/cmd/mapcidr@latest"
    ["tlsx"]="github.com/projectdiscovery/tlsx/cmd/tlsx@latest"
    ["assetfinder"]="github.com/tomnomnom/assetfinder@latest"
    ["waybackurls"]="github.com/tomnomnom/waybackurls@latest"
    ["gf"]="github.com/tomnomnom/gf@latest"
    ["anew"]="github.com/tomnomnom/anew@latest"
    ["unfurl"]="github.com/tomnomnom/unfurl@latest"
    ["gau"]="github.com/lc/gau/v2/cmd/gau@latest"
    ["hakrawler"]="github.com/hakluke/hakrawler@latest"
    ["dalfox"]="github.com/hahwul/dalfox/v2@latest"
    ["ffuf"]="github.com/ffuf/ffuf/v2@latest"
    ["puredns"]="github.com/d3mondev/puredns/v2@latest"
    ["subzy"]="github.com/PentestPad/subzy@latest"
    ["gowitness"]="github.com/sensepost/gowitness@latest"
    ["getJS"]="github.com/003random/getJS/v2@latest"
    ["subjs"]="github.com/lc/subjs@latest"
    ["mantra"]="github.com/MrEmpy/mantra@latest"
    ["github-subdomains"]="github.com/gwen001/github-subdomains@latest"
    ["notify"]="github.com/projectdiscovery/notify/cmd/notify@latest"
)

for tool in "${!GO_TOOLS[@]}"; do
    if ! command -v $tool &> /dev/null; then
        echo -e "${CYAN}   → Installing: $tool${NC}"
        go install -v "${GO_TOOLS[$tool]}" 2>/dev/null && \
            echo -e "${GREEN}     ✓ $tool installed${NC}" || \
            echo -e "${RED}     ✗ $tool failed${NC}"
    else
        echo -e "${GREEN}   ✓ $tool already installed${NC}"
    fi
done

# ============================================
# PYTHON TOOLS
# ============================================
echo -e "${YELLOW}[+] Installing Python tools...${NC}"

PIP_FLAGS=""
pip3 install uro 2>/dev/null || PIP_FLAGS="--break-system-packages"
pip3 install $PIP_FLAGS uro arjun bs4 requests lxml 2>/dev/null || true

cd ~/tools

# SecretFinder
if [ ! -d "SecretFinder" ]; then
    echo -e "${CYAN}   → Cloning SecretFinder${NC}"
    git clone -q https://github.com/m4ll0k/SecretFinder.git 2>/dev/null && {
        cd SecretFinder && pip3 install $PIP_FLAGS -r requirements.txt 2>/dev/null || true
        cd ~/tools
        echo -e "${GREEN}     ✓ SecretFinder ready${NC}"
    } || echo -e "${RED}     ✗ SecretFinder failed${NC}"
fi

# LinkFinder
if [ ! -d "LinkFinder" ]; then
    echo -e "${CYAN}   → Cloning LinkFinder${NC}"
    git clone -q https://github.com/GerbenJavado/LinkFinder.git 2>/dev/null && {
        cd LinkFinder && pip3 install $PIP_FLAGS -r requirements.txt 2>/dev/null || true
        cd ~/tools
        echo -e "${GREEN}     ✓ LinkFinder ready${NC}"
    } || echo -e "${RED}     ✗ LinkFinder failed${NC}"
fi

# ParamSpider
if [ ! -d "ParamSpider" ]; then
    echo -e "${CYAN}   → Cloning ParamSpider${NC}"
    git clone -q https://github.com/devanshbatham/ParamSpider.git 2>/dev/null && \
        echo -e "${GREEN}     ✓ ParamSpider ready${NC}" || \
        echo -e "${RED}     ✗ ParamSpider failed${NC}"
fi

# trufflehog
if ! command -v trufflehog &> /dev/null; then
    echo -e "${CYAN}   → Installing trufflehog${NC}"
    curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | \
        sudo sh -s -- -b /usr/local/bin 2>/dev/null && \
        echo -e "${GREEN}     ✓ trufflehog ready${NC}" || \
        echo -e "${RED}     ✗ trufflehog failed${NC}"
fi

# ============================================
# WORDLISTS
# ============================================
echo -e "${YELLOW}[+] Downloading wordlists...${NC}"
cd ~/wordlists

if [ ! -d "SecLists" ]; then
    echo -e "${CYAN}   → Cloning SecLists (besar, ~1GB)${NC}"
    git clone -q --depth 1 https://github.com/danielmiessler/SecLists.git 2>/dev/null && \
        echo -e "${GREEN}     ✓ SecLists ready${NC}" || \
        echo -e "${RED}     ✗ SecLists failed${NC}"
fi

[ ! -f "best-dns-wordlist.txt" ] && {
    echo -e "${CYAN}   → Downloading best-dns-wordlist${NC}"
    wget -q https://wordlists-cdn.assetnote.io/data/manual/best-dns-wordlist.txt && \
        echo -e "${GREEN}     ✓ DNS wordlist ready${NC}"
}

[ ! -f "resolvers.txt" ] && {
    echo -e "${CYAN}   → Downloading resolvers${NC}"
    wget -q https://raw.githubusercontent.com/trickest/resolvers/main/resolvers.txt && \
        echo -e "${GREEN}     ✓ Resolvers ready${NC}"
}

[ ! -f "resolvers-trusted.txt" ] && \
    wget -q https://raw.githubusercontent.com/trickest/resolvers/main/resolvers-trusted.txt

[ ! -f "subdomains-top1mil.txt" ] && \
    wget -q https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/DNS/subdomains-top1million-110000.txt -O subdomains-top1mil.txt

[ ! -f "permutations.txt" ] && \
    wget -q https://gist.githubusercontent.com/six2dez/a89a0c7861d49bb61a09822d272d5395/raw/ -O permutations.txt

# ============================================
# GF PATTERNS
# ============================================
echo -e "${YELLOW}[+] Setting up GF patterns...${NC}"
mkdir -p ~/.gf
cd ~/tools

if [ ! -d "Gf-Patterns" ]; then
    git clone -q https://github.com/1ndianl33t/Gf-Patterns.git 2>/dev/null && \
        echo -e "${GREEN}   ✓ Gf-Patterns cloned${NC}"
fi

cp Gf-Patterns/*.json ~/.gf/ 2>/dev/null && \
    echo -e "${GREEN}   ✓ GF patterns installed${NC}"

# Tambahan pattern dari Tomnomnom
# Tambahan pattern dari Tomnomnom
if [ ! -d "gf-tomnomnom" ]; then
    git clone -q https://github.com/tomnomnom/gf.git gf-tomnomnom 2>/dev/null && \
        cp gf-tomnomnom/examples/*.json ~/.gf/ 2>/dev/null
fi

# ============================================
# NUCLEI TEMPLATES (FIXED - No Git Prompt)
# ============================================
echo -e "${YELLOW}[+] Updating Nuclei templates...${NC}"

# Update official templates
if command -v nuclei &> /dev/null; then
    nuclei -update-templates -silent 2>/dev/null && \
        echo -e "${GREEN}   ✓ Official templates updated${NC}" || \
        echo -e "${YELLOW}   ⊘ Nuclei update skipped${NC}"
fi

cd ~/tools

# Fuzzing templates (official, public)
if [ ! -d "fuzzing-templates" ]; then
    echo -e "${CYAN}   → Cloning fuzzing-templates${NC}"
    git clone -q https://github.com/projectdiscovery/fuzzing-templates.git 2>/dev/null && \
        echo -e "${GREEN}     ✓ fuzzing-templates ready${NC}" || \
        echo -e "${YELLOW}     ⊘ fuzzing-templates skipped${NC}"
fi

# Extra community templates (optional, skip if fail)
echo -e "${CYAN}   → Trying optional community templates${NC}"

# Alternative template repos (all public & active)
COMMUNITY_REPOS=(
    "https://github.com/geeknik/the-nuclei-templates.git|nuclei-geeknik"
    "https://github.com/pikpikcu/nuclei-templates.git|nuclei-pikpikcu"
    "https://github.com/0xPugal/fuzz4bounty.git|fuzz4bounty"
)

for repo_info in "${COMMUNITY_REPOS[@]}"; do
    IFS='|' read -r repo_url repo_name <<< "$repo_info"
    if [ ! -d "$repo_name" ]; then
        timeout 30 git clone -q "$repo_url" "$repo_name" 2>/dev/null && \
            echo -e "${GREEN}     ✓ $repo_name${NC}" || \
            echo -e "${YELLOW}     ⊘ $repo_name skipped${NC}"
    fi
done

# ============================================
# FINAL CHECK
# ============================================
echo ""
echo -e "${YELLOW}[+] Running final check...${NC}"
echo ""

CRITICAL_TOOLS=("subfinder" "httpx" "nuclei" "katana" "dnsx" "ffuf")
MISSING=0

for tool in "${CRITICAL_TOOLS[@]}"; do
    if command -v $tool &> /dev/null; then
        echo -e "${GREEN}   ✓ $tool${NC}"
    else
        echo -e "${RED}   ✗ $tool MISSING${NC}"
        ((MISSING++))
    fi
done

echo ""
if [ $MISSING -eq 0 ]; then
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      ✓ INSTALLATION COMPLETE!          ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
else
    echo -e "${YELLOW}╔════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║   ⚠ INSTALLATION PARTIAL               ║${NC}"
    echo -e "${YELLOW}║   $MISSING critical tools missing        ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════╝${NC}"
fi

echo ""
echo -e "${YELLOW}[!] Langkah selanjutnya:${NC}"
echo -e "${CYAN}   1. source ~/.bashrc${NC}"
echo -e "${CYAN}   2. ./setup-api.sh    ${NC}${YELLOW}# Setup API keys${NC}"
echo -e "${CYAN}   3. ./recon.sh -h     ${NC}${YELLOW}# Lihat help${NC}"
echo ""
echo -e "${GREEN}💰 Happy Hunting! 🐛${NC}"
