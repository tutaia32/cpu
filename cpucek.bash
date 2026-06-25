#!/bin/bash

# ==========================================
# KONFIGURASI WARNA & EFEK
# ==========================================
GREEN='\033[0;32m'
LIGHTGREEN='\033[1;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

fake_load() {
    echo -n -e "${LIGHTGREEN}$1 "
    for i in {1..3}; do
        echo -n "."
        sleep 0.1
    done
}

# ==========================================
# BANNER HEADER UTAMA
# ==========================================
show_header() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
 ██╗  ██╗██╗██████╗ ██╗██╗      ██████╗  ██████╗ ███████╗
 ██║ ██╔╝██║██╔══██╗██║██║      ╚═══██║██╔═══██╗██╔════╝
 █████╔╝ ██║██████╔╝██║██║          ██║██║   ██║█████╗  
 ██╔═██╗ ██║██╔══██╗██║██║     ██   ██║██║   ██║██╔══╝  
 ██║  ██╗██║██████╔╝██║███████╗╚██████╔╝╚██████╔╝███████╗
 ╚═╝  ╚═╝╚═╝╚═════╝ ╚═╝╚══════╝ ╚═════╝  ╚═════╝ ╚══════╝
EOF
    echo -e "${NC}"
}

# ==========================================
# PERSIAPAN KONEKSI DATABASE
# ==========================================
ENV_FILE="/var/www/pterodactyl/.env"
if [ ! -f "$ENV_FILE" ]; then
  show_header
  echo -e "${RED}[!] File .env Pterodactyl tidak ditemukan!${NC}"
  exit 1
fi

DB_HOST=$(grep -w "^DB_HOST" $ENV_FILE | cut -d '=' -f2 | tr -d '"')
DB_PORT=$(grep -w "^DB_PORT" $ENV_FILE | cut -d '=' -f2 | tr -d '"')
DB_NAME=$(grep -w "^DB_DATABASE" $ENV_FILE | cut -d '=' -f2 | tr -d '"')
DB_USER=$(grep -w "^DB_USERNAME" $ENV_FILE | cut -d '=' -f2 | tr -d '"')
DB_PASS=$(grep -w "^DB_PASSWORD" $ENV_FILE | cut -d '=' -f2 | tr -d '"' | tr -d "'")
DB_HOST=${DB_HOST:-127.0.0.1}
DB_PORT=${DB_PORT:-3306}

# ==========================================
# FUNGSI LACAK PID (CYBERPUNK BRACKETS STYLE)
# ==========================================
track_pid() {
    local TARGET_PID=$1
    local CPU_USAGE=$2

    local CID=$(cat /proc/$TARGET_PID/cgroup 2>/dev/null | grep -oE 'docker-[a-f0-9]+' | head -n 1 | sed 's/docker-//')
    if [ -z "$CID" ]; then return 1; fi
    local SHORT_CID=${CID:0:12}

    local NAME=$(docker inspect --format='{{.Name}}' $SHORT_CID 2>/dev/null | sed 's/\///')
    if [ -z "$NAME" ]; then return 1; fi
    
    local UUID=$(echo "$NAME" | sed -E 's/^(pterodactyl-|ptdl-)//')

    local RESULT=$(mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -N -B -e "
    SELECT servers.name, users.username FROM servers JOIN users ON servers.owner_id = users.id WHERE servers.uuid LIKE '$UUID%';
    " 2>/dev/null)

    if [ -z "$RESULT" ]; then return 1; fi

    IFS=$'\t' read -r SERVER_NAME USERNAME <<< "$RESULT"

    echo -e "${CYAN}------------------------------------------------${NC}"
    if [ -n "$CPU_USAGE" ]; then
        echo -e "${RED}[!] OVERLOAD DETECTED: ${CPU_USAGE}% CPU USAGE${NC}"
    fi
    echo -e "${GREEN}├── ${CYAN}[PID]${GREEN} Target PID   : ${NC}$TARGET_PID"
    echo -e "${GREEN}├── ${CYAN}[CID]${GREEN} Container ID : ${NC}$SHORT_CID"
    echo -e "${GREEN}├── ${CYAN}[UID]${GREEN} Server UUID  : ${NC}$UUID"
    echo -e "${LIGHTGREEN}├── ${YELLOW}[NAME]${LIGHTGREEN} Server Name : ${NC}$SERVER_NAME"
    echo -e "${LIGHTGREEN}└── ${YELLOW}[USER]${LIGHTGREEN} Owner Name  : ${NC}$USERNAME"
    
    return 0
}

# ==========================================
# HALAMAN 2: LOGIK UTAMA AUTO-SCAN
# ==========================================
run_scanner_engine() {
    show_header
    echo -e "${CYAN}┌──────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${LIGHTGREEN}          PTERODACTYL CPU CORE HUNTER         ${CYAN}│${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────┘${NC}"
    fake_load "[*] Extracting Pterodactyl environment keys"
    echo -e " [ OK ]${NC}"
    echo -e "${YELLOW}[*] Action confirmed. Initiating Auto-Scan...${NC}\n"
    fake_load "[*] Analyzing top 100 active core processes"
    
    TOP_PIDS=$(ps -eo pid,%cpu --sort=-%cpu 2>/dev/null | awk 'NR>1 {print $1"|"$2}' | head -n 100)
    
    if [ -z "$TOP_PIDS" ]; then
        echo -e " ${RED}[ FAILED ]${NC}"
        exit 1
    fi
    echo -e " [ OK ]${NC}\n"

    COUNT=0
    SCANNED_CIDS=""

    for ROW in $TOP_PIDS; do
        P=$(echo $ROW | cut -d'|' -f1)
        CPU=$(echo $ROW | cut -d'|' -f2)

        TEMP_CID=$(cat /proc/$P/cgroup 2>/dev/null | grep -oE 'docker-[a-f0-9]+' | head -n 1 | sed 's/docker-//')
        TEMP_SHORT=${TEMP_CID:0:12}
        
        if [ -n "$TEMP_SHORT" ]; then
            if [[ "$SCANNED_CIDS" != *"$TEMP_SHORT"* ]]; then
                if track_pid "$P" "$CPU"; then
                    SCANNED_CIDS="$SCANNED_CIDS $TEMP_SHORT"
                    ((COUNT++))
                    if [ $COUNT -ge 5 ]; then break; fi
                fi
            fi
        fi
    done

    if [ $COUNT -eq 0 ]; then
        echo -e "${CYAN}------------------------------------------------${NC}"
        echo -e "${GREEN}[✓] Sistem aman. Tidak ada Pterodactyl container overload.${NC}"
    fi

    # FOOTER REAPER SKULL SHIELD
    echo -e "${CYAN}================================================${NC}"
    echo -e "${RED}             ⣠⣤⣶⣶⣶⣤⣄⡀          "
    echo -e "${RED}           ⠀⠀⣴⣾⣿⣿⣿⣿⣿⣧⡀⠈⠢        "
    echo -e "${RED}           ⠀⣼⣿⣿⣿⣿⣿⣿⣿⡿⠁⠀⠀        "
    echo -e "${RED}           ⢰⡿⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀        "
    echo -e "${RED}           ⠘⣽⡿⠿⠿⣿⣿⣿⣿⣿⣦⣤⡀       "
    echo -e "${RED}           ⠀⣟⠀⠀⠀⣸⣿⡏⠀⠀⠀⢹⠗        "
    echo -e "${RED}           ⠀⣿⣷⣶⣾⡿⠁⠙⣄⣀⣀⣠⡀        "
    echo -e "${RED}           ⠀⠙⠙⢿⡿⣷⣶⣤⣿⣿⡿⠿⠃        "
    echo -e "${RED}           ⠀⠀⠀⠺⡏⡏⡏⡏⡏⠉⠁⠀⠀        "
    echo -e "${CYAN}================================================${NC}"
    echo -e "${GREEN}[✓] Operation Terminated. Ghost mode active!${NC}\n"
}

# ==========================================
# HALAMAN 1: INTERACTIVE WELCOME INTERFACE (BOX MODEL)
# ==========================================
show_welcome_page() {
    show_header
    
    # --- BOX METADATA PREMIUM (STRUKTUR SAMA SEPERTI REFERENSI) ---
    echo -e "${CYAN}┌──────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${LIGHTGREEN}          PTERODACTYL CPU CORE HUNTER         ${CYAN}│${NC}"
    echo -e "${CYAN}│${GREEN}  Author: kibiljoe    Target: CPU DESTROYER   ${CYAN}│${NC}"
    echo -e "${CYAN}├──────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${YELLOW}       [ ★ v1.6 VIP PREMIUM MEMBER ★ ]        ${CYAN}│${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────┘${NC}\n"
    
    # Menu Tindakan Utama
    echo -e "${YELLOW} MENU UTAMA :${NC}"
    echo -e " ${CYAN}[1]${NC} ${LIGHTGREEN}Start / Mulai Scan Core CPU (Top 5)${NC}"
    echo -e " ${CYAN}[2]${NC} ${RED}Back / Exit to Terminal${NC}\n"
    
    echo -e -n "${CYAN}[?] Pilih tindakan (1-2): ${NC}"
    read -r CHOICE

    case $CHOICE in
        1)
            run_scanner_engine
            ;;
        2)
            echo -e "\n${RED}[*] Back to terminal. Goodbye!${NC}\n"
            exit 0
            ;;
        *)
            echo -e "\n${RED}[!] Pilihan tidak valid! Memuat ulang halaman...${NC}"
            sleep 1
            show_welcome_page
            ;;
    esac
}

# ==========================================
# TRIGGER ENTRY ROUTER
# ==========================================
if [ -z "$1" ]; then
    show_welcome_page
else
    show_header
    echo -e "${CYAN}================================================${NC}"
    fake_load "[*] Tracking specific target PID $1"
    echo -e " [ OK ]${NC}\n"
    
    if ! track_pid "$1" ""; then
        echo -e "${RED}[!] PID $1 bukan milik server Pterodactyl atau UUID tidak valid.${NC}"
    fi
    echo -e "${CYAN}================================================${NC}\n"
fi
  
