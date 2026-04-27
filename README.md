<div align="center">

# 🔍 Bug Hunter Recon v2.0

### Automated Deep Reconnaissance Tool for HackerOne Bug Bounty Hunting

![Bash](https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)
![Debian](https://img.shields.io/badge/Debian-A81D33?style=for-the-badge&logo=debian&logoColor=white)

![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)
![Version](https://img.shields.io/badge/version-2.0-green.svg?style=flat-square)
![Platform](https://img.shields.io/badge/platform-Debian%2FUbuntu-orange.svg?style=flat-square)
![Maintained](https://img.shields.io/badge/maintained-yes-brightgreen.svg?style=flat-square)

**Tools recon lengkap & terotomatisasi untuk bug bounty hunter pemula sampai pro**

[Features](#-features) • [Installation](#-installation) • [Usage](#-usage) • [Workflow](#-workflow) • [Output](#-output-structure)

---

</div>

## 📖 Tentang Project

**Bug Hunter Recon v2.0** adalah automated reconnaissance tool yang dirancang khusus untuk bug bounty hunter di platform seperti **HackerOne**, **Bugcrowd**, dan **Intigriti**. 

Tool ini menggabungkan **25+ tools recon terbaik** dalam satu workflow terstruktur, mulai dari subdomain enumeration sampai vulnerability scanning, dengan output yang rapi & mudah di-review.

> ⚠️ **DISCLAIMER:** Tool ini hanya untuk authorized testing (bug bounty program resmi). Pengguna bertanggung jawab atas penggunaannya. Jangan scan target yang bukan scope kamu!

---

## ✨ Features

### 🎯 Multi-Mode Scanning
- ✅ **Single Domain Mode** - Scan 1 domain spesifik
- ✅ **Wildcard Mode** - Deep recon untuk `*.target.com`
- ✅ **List Mode** - Batch scan multiple target
- ✅ **Quick Mode** - Recon cepat (1-2 jam)
- ✅ **Deep Mode** - Recon menyeluruh (3-8 jam)

### 🔍 Comprehensive Recon
- 🌐 **Subdomain Enumeration** - Passive + Active + Bruteforce + Permutation
- 🚀 **Live Host Detection** - Multi-port (80, 443, 8080, 8443, dll)
- 📸 **Screenshot Capture** - Visual recon dengan gowitness
- 🎯 **Subdomain Takeover** - Auto detect dengan subzy + nuclei
- 🔓 **CORS Misconfig** - Detect CORS vulnerabilities
- 🚪 **403/401 Bypass** - Auto bypass forbidden pages
- 🔌 **Port Scanning** - Top 1000 ports dengan naabu
- 🕷️ **URL Crawling** - katana + gau + waybackurls + hakrawler
- 📜 **JS Deep Analysis** - SecretFinder + LinkFinder + Mantra + Trufflehog
- 🔐 **Secret Detection** - API keys, tokens, credentials
- 📂 **Sensitive File Discovery** - .env, .git, backup files, config
- 🎨 **Parameter Discovery** - gf patterns + Arjun
- ⚔️ **Vulnerability Scanning** - Nuclei 5-stage scan
- 📊 **Beautiful Reports** - JSON + HTML report

### 🛡️ Safety First
- ✅ **Rate Limiting** - Tidak DoS target
- ✅ **Scope Filter** - Respect in-scope / out-of-scope
- ✅ **Safe Defaults** - Threads sudah di-tune optimal
- ✅ **API Keys Encrypted** - Permission 600 (private)

---

## 📦 Installation

### Prerequisites

- **OS:** Debian 10+ / Ubuntu 20.04+ / Kali Linux
- **RAM:** Minimum 4GB (8GB recommended)
- **Storage:** Minimum 10GB free
- **Internet:** Stable connection

### Step 1: Clone Repository

```bash
git clone https://github.com/ZeroX-404/bug-hunter-recon.git
cd bug-hunter-recon
chmod +x *.sh
Step 2: Install All Tools
bash

Copy code
./install.sh
⏱️ Proses instalasi: 15-20 menit (tergantung koneksi internet)

Script ini akan install:

Base packages (git, curl, python3, go, dll)
25+ Go tools (subfinder, httpx, nuclei, katana, dll)
Python tools (SecretFinder, LinkFinder, ParamSpider, Arjun)
Wordlists (SecLists, best-dns-wordlist, resolvers)
Nuclei templates (default + fuzzing-templates)
GF patterns (xss, sqli, ssrf, lfi, dll)
Step 3: Reload Shell
bash

Copy code
source ~/.bashrc
Step 4: Setup API Keys (Optional but Recommended)
bash

Copy code
./setup-api.sh
Wizard akan tanya API keys satu per satu. Tekan ENTER untuk skip kalau belum punya.

API yang disarankan (semua GRATIS):

API

Link Daftar

Impact

🔑 Chaos

https://chaos.projectdiscovery.io/

⭐⭐⭐⭐⭐

🔑 GitHub Token

https://github.com/settings/tokens

⭐⭐⭐⭐⭐

🔑 VirusTotal

https://virustotal.com/

⭐⭐⭐⭐

🔑 Shodan

https://account.shodan.io/

⭐⭐⭐⭐

🔑 SecurityTrails

https://securitytrails.com/

⭐⭐⭐⭐

🔑 URLScan

https://urlscan.io/

⭐⭐⭐

🔑 Censys

https://censys.io/

⭐⭐⭐⭐

💡 Tip: Walaupun tanpa API, tool ini tetap jalan dengan hasil yang masih bagus!

🚀 Usage
Basic Commands
bash

Copy code
# Wildcard recon (recommended untuk scope *.domain.com)
./recon.sh -w target.com

# Single domain recon
./recon.sh -d api.target.com

# Scan dari list file
./recon.sh -l domains.txt

# Dengan exclude file (out-of-scope)
./recon.sh -w target.com -x oos.txt

# Quick mode (hemat waktu, skip heavy scan)
./recon.sh -w target.com -s

# Custom output directory
./recon.sh -w target.com -o /path/to/output

# Help
./recon.sh -h
Command Options
Flag

Description

Example

-d

Single domain mode

-d api.target.com

-w

Wildcard mode

-w target.com

-l

List file mode

-l domains.txt

-o

Output directory

-o ./results

-x

Exclude file (OOS)

-x oos.txt

-s

Skip heavy scans (quick)

-s

-h

Show help

-h

Real-World Examples
Example 1: Scan HackerOne Target
bash

Copy code
./recon.sh -w hackerone.com
Example 2: Scan dengan Out-of-Scope
bash

Copy code
# Buat file oos.txt isinya subdomain OOS dari program
cat > oos.txt << EOF
support.target.com
status.target.com
blog.target.com
EOF

# Scan dengan exclude
./recon.sh -w target.com -x oos.txt
Example 3: Batch Scan Multiple Targets
bash

Copy code
cat > targets.txt << EOF
target1.com
target2.com
target3.com
EOF

./recon.sh -l targets.txt
🔄 Workflow
mermaid

Copy code
graph TD
    A[Input Target] --> B[Phase 1: Subdomain Enum]
    B --> C[Phase 2: Live Host Detection]
    C --> D[Phase 3: Screenshot]
    D --> E[Phase 4: Quick Wins<br/>Takeover + CORS + 403 Bypass]
    E --> F[Phase 5: Port Scanning]
    F --> G[Phase 6: URL Collection]
    G --> H[Phase 7: JS Deep Analysis]
    H --> I[Phase 8: Secrets & Info Disclosure]
    I --> J[Phase 9: Parameter Discovery]
    J --> K[Phase 10: Nuclei Vuln Scan]
    K --> L[Phase 11: JSON + HTML Report]
