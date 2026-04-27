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
