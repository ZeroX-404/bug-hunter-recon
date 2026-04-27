# 🔍 Bug Hunter Recon v2.0

Deep recon automation untuk HackerOne bug bounty hunting.

## 📦 Instalasi

### 1. Clone/Download semua script
```bash
mkdir ~/bug-hunter-recon && cd ~/bug-hunter-recon
# Simpan semua script (install.sh, setup-api.sh, recon.sh) di folder ini
chmod +x *.sh


---

## 🚀 Cara Pakai Lengkap (Step by Step)

```bash
# Step 1: Buat folder
mkdir ~/bug-hunter-recon && cd ~/bug-hunter-recon

# Step 2: Buat semua file (copy script di atas)
nano install.sh      # paste install.sh
nano setup-api.sh    # paste setup-api.sh
nano recon.sh        # paste recon.sh
mkdir config
nano config/config.yaml  # paste config.yaml

# Step 3: Permission
chmod +x install.sh setup-api.sh recon.sh

# Step 4: Install semua tools
./install.sh
source ~/.bashrc

# Step 5: Setup API keys (isi yang kamu punya)
./setup-api.sh

# Step 6: Mulai hunting!
./recon.sh -w target.com
