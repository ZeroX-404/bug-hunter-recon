#!/bin/bash
# ============================================
# Bug Hunter Recon - Auto Installer (Debian)
# ============================================

set -e

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Bug Hunter Recon - Installer v2.0    ║${NC}"
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
pip3 install $PIP_FLAGS uro arjun bs4 requests lxml 2>/dev/null

cd ~/tools

# SecretFinder
if [ ! -d "SecretFinder" ]; then
    git clone -q https://github.com/m4ll0k/SecretFinder.git
    cd SecretFinder && pip3 install $PIP_FLAGS -r requirements.txt 2>/dev/null; cd ~/tools
fi

# LinkFinder
if [ ! -d "LinkFinder" ]; then
    git clone -q https://github.com/GerbenJavado/LinkFinder.git
    cd LinkFinder && pip3 install $PIP_FLAGS -r requirements.txt 2>/dev/null; cd ~/tools
fi

# ParamSpider
if [ ! -d "ParamSpider" ]; then
    git clone -q https://github.com/devanshbatham/ParamSpider.git
fi

# trufflehog
if ! command -v trufflehog &> /dev/null; then
    echo -e "${CYAN}   → Installing trufflehog${NC}"
    curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sudo sh -s -- -b /usr/local/bin
fi

# ============================================
# WORDLISTS
# ============================================
echo -e "${YELLOW}[+] Downloading wordlists...${NC}"
cd ~/wordlists

[ ! -d "SecLists" ] && git clone -q --depth 1 https://github.com/danielmiessler/SecLists.git
[ ! -f "best-dns-wordlist.txt" ] && wget -q https://wordlists-cdn.assetnote.io/data/manual/best-dns-wordlist.txt
[ ! -f "resolvers.txt" ] && wget -q https://raw.githubusercontent.com/trickest/resolvers/main/resolvers.txt
[ ! -f "resolvers-trusted.txt" ] && wget -q https://raw.githubusercontent.com/trickest/resolvers/main/resolvers-trusted.txt
[ ! -f "subdomains-top1mil.txt" ] && wget -q https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/DNS/subdomains-top1million-110000.txt -O subdomains-top1mil.txt
[ ! -f "permutations.txt" ] && wget -q https://gist.githubusercontent.com/six2dez/a89a0c7861d49bb61a09822d272d5395/raw/ -O permutations.txt

# ============================================
# GF PATTERNS
# ============================================
echo -e "${YELLOW}[+] Setting up GF patterns...${NC}"
mkdir -p ~/.gf
cd ~/tools
[ ! -d "Gf-Patterns" ] && git clone -q https://github.com/1ndianl33t/Gf-Patterns.git
cp Gf-Patterns/*.json ~/.gf/ 2>/dev/null

# ============================================
# NUCLEI TEMPLATES
# ============================================
echo -e "${YELLOW}[+] Updating Nuclei templates...${NC}"
nuclei -update-templates -silent 2>/dev/null

cd ~/tools
[ ! -d "fuzzing-templates" ] && git clone -q https://github.com/projectdiscovery/fuzzing-templates.git
[ ! -d "nuclei_templates_priv8" ] && git clone -q https://github.com/coffinxp/nuclei_templates.git nuclei_templates_priv8 2>/dev/null

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      ✓ INSTALLATION COMPLETE!          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}[!] Langkah selanjutnya:${NC}"
echo -e "${CYAN}   1. source ~/.bashrc${NC}"
echo -e "${CYAN}   2. ./setup-api.sh    ${NC}${YELLOW}# Setup API keys${NC}"
echo -e "${CYAN}   3. ./recon.sh        ${NC}${YELLOW}# Mulai recon${NC}"
