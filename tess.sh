#!/bin/bash

# ============================================
#   PTERODACTYL ADMIN TOOLS v2.0
#   Fitur: Auto Backup, Install, Uninstall
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ============ KONFIGURASI ============
PANEL_PATH="/var/www/pterodactyl"
WINGS_PATH="/etc/pterodactyl"
TOOLS_DIR="/opt/ptero-tools"
BACKUP_DIR="/root/ptero-backup"
SCRIPT_PATH="/usr/local/bin/ptero"
SCRIPT_SOURCE="/root/ptero-tools.sh"
CRON_FILE="/etc/cron.d/ptero-autobackup"
LOG_FILE="/var/log/ptero-tools.log"

# ============ CEK ROOT ============
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[!] Script harus dijalankan sebagai root!${NC}"
   exit 1
fi

# ============ FUNGSI HEADER ============
header() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}   ${MAGENTA}🚀 PTERODACTYL ADMIN TOOLS v2.0${NC}          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   ${YELLOW}Auto Backup • Install • Uninstall${NC}         ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
}

# ============ LOGGING ============
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# ============ CEK STATUS TOOLS ============
is_installed() {
    [[ -f "$CRON_FILE" ]] && [[ -f "$SCRIPT_PATH" ]] && return 0 || return 1
}

# ============ CEK SERVICES ============
check_services() {
    echo -e "${YELLOW}📊 Status Services:${NC}"
    echo "─────────────────────────────────────────"
    
    if systemctl is-active --quiet pteroq.service 2>/dev/null; then
        echo -e "  pteroq.service     : ${GREEN}● RUNNING${NC}"
    else
        echo -e "  pteroq.service     : ${RED}● STOPPED${NC}"
    fi
    
    if systemctl is-active --quiet wings.service 2>/dev/null; then
        echo -e "  wings.service      : ${GREEN}● RUNNING${NC}"
    else
        echo -e "  wings.service      : ${RED}● STOPPED/OFF${NC}"
    fi
    
    if systemctl is-active --quiet nginx 2>/dev/null; then
        echo -e "  nginx              : ${GREEN}● RUNNING${NC}"
    else
        echo -e "  nginx              : ${RED}● STOPPED${NC}"
    fi
    
    if systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mariadb 2>/dev/null; then
        echo -e "  database           : ${GREEN}● RUNNING${NC}"
    else
        echo -e "  database           : ${RED}● STOPPED${NC}"
    fi
    
    if systemctl is-active --quiet redis-server 2>/dev/null || systemctl is-active --quiet redis 2>/dev/null; then
        echo -e "  redis              : ${GREEN}● RUNNING${NC}"
    else
        echo -e "  redis              : ${RED}● STOPPED${NC}"
    fi
    
    echo "─────────────────────────────────────────"
    if is_installed; then
        echo -e "  Auto Backup        : ${GREEN}● AKTIF${NC}"
    else
        echo -e "  Auto Backup        : ${RED}● BELUM INSTALL${NC}"
    fi
}

# ============================================
#   MENU 1: INSTALL TOOLS
# ============================================
install_tools() {
    clear
    header
    echo -e "${CYAN}📦 INSTALL PTERODACTYL ADMIN TOOLS${NC}"
    echo "─────────────────────────────────────────"
    echo ""
    
    if is_installed; then
        echo -e "${YELLOW}⚠️  Tools sudah terinstall sebelumnya!${NC}"
        read -p "Mau reinstall? (y/n): " confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return
    fi
    
    echo -e "${CYAN}[1/6] Membuat direktori tools...${NC}"
    mkdir -p "$TOOLS_DIR" "$BACKUP_DIR"
    echo -e "${GREEN}  ✓ $TOOLS_DIR${NC}"
    echo -e "${GREEN}  ✓ $BACKUP_DIR${NC}"
    
    echo -e "${CYAN}[2/6] Membuat script auto-backup...${NC}"
    cat > "$TOOLS_DIR/autobackup.sh" << 'EOF'
#!/bin/bash
# Auto Backup Script - Pterodactyl Panel
PANEL_PATH="/var/www/pterodactyl"
BACKUP_DIR="/root/ptero-backup"
LOG_FILE="/var/log/ptero-tools.log"
RETENTION_DAYS=7

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

mkdir -p "$BACKUP_DIR"

# Cek .env
if [[ ! -f "$PANEL_PATH/.env" ]]; then
    log "ERROR: .env tidak ditemukan"
    exit 1
fi

DB_NAME=$(grep "^DB_DATABASE=" "$PANEL_PATH/.env" | cut -d '=' -f2 | tr -d '"')
DB_USER=$(grep "^DB_USERNAME=" "$PANEL_PATH/.env" | cut -d '=' -f2 | tr -d '"')
DB_PASS=$(grep "^DB_PASSWORD=" "$PANEL_PATH/.env" | cut -d '=' -f2 | tr -d '"')

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/db_panel_${TIMESTAMP}.sql"
BACKUP_ENV="$BACKUP_DIR/env_panel_${TIMESTAMP}.env"

# Backup Database
if mysqldump -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$BACKUP_FILE" 2>/dev/null; then
    gzip "$BACKUP_FILE"
    log "SUCCESS: DB backup -> ${BACKUP_FILE}.gz"
else
    log "ERROR: Gagal backup database"
fi

# Backup .env
if cp "$PANEL_PATH/.env" "$BACKUP_ENV" 2>/dev/null; then
    log "SUCCESS: .env backup -> $BACKUP_ENV"
fi

# Hapus backup lama
find "$BACKUP_DIR" -name "*.gz" -mtime +$RETENTION_DAYS -delete 2>/dev/null
find "$BACKUP_DIR" -name "*.env" -mtime +$RETENTION_DAYS -delete 2>/dev/null
log "CLEANUP: Backup > $RETENTION_DAYS hari dihapus"
EOF

    chmod +x "$TOOLS_DIR/autobackup.sh"
    echo -e "${GREEN}  ✓ Script dibuat: $TOOLS_DIR/autobackup.sh${NC}"
    
    echo -e "${CYAN}[3/6] Setup cron job auto-backup (tiap hari jam 03:00)...${NC}"
    cat > "$CRON_FILE" << EOF
# Pterodactyl Auto Backup - by Admin Tools
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 3 * * * root $TOOLS_DIR/autobackup.sh
EOF
    chmod 644 "$CRON_FILE"
    systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null
    echo -e "${GREEN}  ✓ Cron terpasang (backup tiap hari 03:00)${NC}"
    
    echo -e "${CYAN}[4/6] Copy script ke /usr/local/bin...${NC}"
    cp "$SCRIPT_SOURCE" "$SCRIPT_PATH" 2>/dev/null
    chmod +x "$SCRIPT_PATH"
    echo -e "${GREEN}  ✓ Bisa dijalankan dengan perintah: ptero${NC}"
    
    echo -e "${CYAN}[5/6] Setup log file...${NC}"
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    echo -e "${GREEN}  ✓ Log: $LOG_FILE${NC}"
    
    echo -e "${CYAN}[6/6] Test backup pertama...${NC}"
    "$TOOLS_DIR/autobackup.sh"
    if [[ $(ls -1 "$BACKUP_DIR"/*.gz 2>/dev/null | wc -l) -gt 0 ]]; then
        echo -e "${GREEN}  ✓ Backup test berhasil!${NC}"
    else
        echo -e "${YELLOW}  ⚠️  Backup test gagal, cek manual${NC}"
    fi
    
    log "INSTALL: Pterodactyl Tools berhasil diinstall"
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   ✅ INSTALL BERHASIL!${NC}                      ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}📌 Info:${NC}"
    echo -e "  • Backup otomatis tiap hari jam 03:00"
    echo -e "  • Lokasi backup: ${YELLOW}$BACKUP_DIR${NC}"
    echo -e "  • Retention: ${YELLOW}7 hari${NC}"
    echo -e "  • Log: ${YELLOW}$LOG_FILE${NC}"
    echo -e "  • Command: ${YELLOW}ptero${NC}"
    echo ""
    read -p "Tekan ENTER untuk kembali..."
}

# ============================================
#   MENU 2: UNINSTALL TOOLS
# ============================================
uninstall_tools() {
    clear
    header
    echo -e "${RED}🗑️  UNINSTALL PTERODACTYL ADMIN TOOLS${NC}"
    echo "─────────────────────────────────────────"
    echo ""
    echo -e "${YELLOW}⚠️  PERINGATAN!${NC}"
    echo "Ini akan menghapus:"
    echo "  • Script auto-backup ($TOOLS_DIR)"
    echo "  • Cron job auto-backup"
    echo "  • Command 'ptero'"
    echo ""
    echo -e "${CYAN}Backup lama TIDAK dihapus (aman)${NC}"
    echo -e "Lokasi backup: ${YELLOW}$BACKUP_DIR${NC}"
    echo ""
    read -p "Yakin mau uninstall? (ketik 'HAPUS' untuk konfirmasi): " confirm
    
    if [[ "$confirm" != "HAPUS" ]]; then
        echo -e "${YELLOW}✗ Uninstall dibatalkan.${NC}"
        sleep 2
        return
    fi
    
    echo ""
    echo -e "${CYAN}[1/6] Stop & hapus cron job...${NC}"
    if [[ -f "$CRON_FILE" ]]; then
        rm -f "$CRON_FILE"
        systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null
        echo -e "${GREEN}  ✓ Cron dihapus${NC}"
    else
        echo -e "${YELLOW}  - Cron tidak ditemukan${NC}"
    fi
    
    echo -e "${CYAN}[2/6] Hapus script tools...${NC}"
    if [[ -d "$TOOLS_DIR" ]]; then
        rm -rf "$TOOLS_DIR"
        echo -e "${GREEN}  ✓ $TOOLS_DIR dihapus${NC}"
    else
        echo -e "${YELLOW}  - Folder tools tidak ada${NC}"
    fi
    
    echo -e "${CYAN}[3/6] Hapus command 'ptero'...${NC}"
    if [[ -f "$SCRIPT_PATH" ]]; then
        rm -f "$SCRIPT_PATH"
        echo -e "${GREEN}  ✓ Command ptero dihapus${NC}"
    else
        echo -e "${YELLOW}  - Command ptero tidak ada${NC}"
    fi
    
    echo -e "${CYAN}[4/6] Hapus log file...${NC}"
    if [[ -f "$LOG_FILE" ]]; then
        rm -f "$LOG_FILE"
        echo -e "${GREEN}  ✓ Log dihapus${NC}"
    fi
    
    echo -e "${CYAN}[5/6] Cek proses yang jalan...${NC}"
    pkill -f "autobackup.sh" 2>/dev/null && echo -e "${GREEN}  ✓ Proses backup dihentikan${NC}" || echo -e "${YELLOW}  - Tidak ada proses backup aktif${NC}"
    
    echo -e "${CYAN}[6/6] Tanya backup lama...${NC}"
    if [[ -d "$BACKUP_DIR" ]] && [[ $(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l) -gt 0 ]]; then
        BACKUP_COUNT=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l)
        BACKUP_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
        echo -e "${YELLOW}  📁 Backup lama: $BACKUP_COUNT file ($BACKUP_SIZE)${NC}"
        read -p "  Hapus juga backup lama? (y/n): " del_backup
        if [[ "$del_backup" == "y" || "$del_backup" == "Y" ]]; then
            rm -rf "$BACKUP_DIR"
            echo -e "${GREEN}  ✓ Backup lama dihapus${NC}"
        else
            echo -e "${GREEN}  ✓ Backup lama disimpan di: $BACKUP_DIR${NC}"
        fi
    else
        echo -e "${YELLOW}  - Tidak ada backup lama${NC}"
    fi
    
    log "UNINSTALL: Pterodactyl Tools dihapus"
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   ✅ UNINSTALL SELESAI!${NC}                     ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Panel Pterodactyl kamu TIDAK terpengaruh.${NC}"
    echo -e "${CYAN}Hanya tools tambahan yang dihapus.${NC}"
    echo ""
    read -p "Tekan ENTER untuk keluar..."
    exit 0
}

# ============================================
#   FITUR LAINNYA
# ============================================
restart_panel() {
    echo -e "${YELLOW}🔄 Restarting Panel services...${NC}"
    systemctl restart pteroq.service 2>/dev/null && echo -e "${GREEN}✓ pteroq restarted${NC}"
    systemctl restart nginx 2>/dev/null && echo -e "${GREEN}✓ nginx restarted${NC}"
    systemctl restart redis-server 2>/dev/null || systemctl restart redis 2>/dev/null
    echo -e "${GREEN}✓ Service panel direstart!${NC}"
    log "RESTART: Panel services"
    sleep 2
}

restart_wings() {
    echo -e "${YELLOW}🔄 Restarting Wings...${NC}"
    if systemctl is-active --quiet wings.service 2>/dev/null; then
        systemctl restart wings.service && echo -e "${GREEN}✓ Wings restarted!${NC}"
    else
        echo -e "${RED}✗ wings.service tidak ditemukan${NC}"
    fi
    log "RESTART: Wings"
    sleep 2
}

clear_cache() {
    echo -e "${YELLOW}🧹 Clearing Laravel cache...${NC}"
    cd "$PANEL_PATH" 2>/dev/null || { echo -e "${RED}✗ Panel path tidak ada!${NC}"; sleep 2; return; }
    php artisan cache:clear 2>/dev/null && echo -e "${GREEN}✓ Cache cleared${NC}"
    php artisan view:clear 2>/dev/null && echo -e "${GREEN}✓ View cleared${NC}"
    php artisan config:clear 2>/dev/null && echo -e "${GREEN}✓ Config cleared${NC}"
    php artisan route:clear 2>/dev/null && echo -e "${GREEN}✓ Route cleared${NC}"
    php artisan optimize 2>/dev/null && echo -e "${GREEN}✓ Optimized${NC}"
    log "CACHE: Cleared"
    sleep 2
}

backup_manual() {
    echo -e "${YELLOW}💾 Backup Manual...${NC}"
    if [[ -f "$TOOLS_DIR/autobackup.sh" ]]; then
        "$TOOLS_DIR/autobackup.sh"
        LATEST=$(ls -t "$BACKUP_DIR"/*.gz 2>/dev/null | head -1)
        if [[ -n "$LATEST" ]]; then
            SIZE=$(du -h "$LATEST" | cut -f1)
            echo -e "${GREEN}✓ Backup berhasil: $LATEST ($SIZE)${NC}"
        else
            echo -e "${RED}✗ Backup gagal!${NC}"
        fi
    else
        echo -e "${RED}✗ Tools belum diinstall! Pilih menu [1] dulu.${NC}"
    fi
    sleep 3
}

info_system() {
    clear
    header
    echo -e "${CYAN}📋 Informasi Sistem:${NC}"
    echo "─────────────────────────────────────────"
    echo -e "  Hostname    : $(hostname)"
    echo -e "  OS          : $(grep PRETTY_NAME /etc/os-release | cut -d '"' -f2)"
    echo -e "  Kernel      : $(uname -r)"
    echo -e "  Uptime      : $(uptime -p)"
    echo -e "  CPU         : $(nproc) cores"
    echo -e "  RAM         : $(free -h | awk '/^Mem:/ {print $3"/"$2}')"
    echo -e "  Disk        : $(df -h / | awk 'NR==2 {print $3"/"$2" ("$5")"}')"
    echo -e "  IP Public   : $(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo 'N/A')"
    echo "─────────────────────────────────────────"
    echo -e "${CYAN}📦 Backup Info:${NC}"
    if [[ -d "$BACKUP_DIR" ]]; then
        COUNT=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l)
        SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
        echo -e "  Total backup : $COUNT file"
        echo -e "  Ukuran       : $SIZE"
        echo -e "  Lokasi       : $BACKUP_DIR"
    else
        echo -e "  ${YELLOW}Belum ada backup${NC}"
    fi
    echo "─────────────────────────────────────────"
    read -p "Tekan ENTER untuk kembali..."
}

fix_perms() {
    echo -e "${YELLOW}🔧 Fixing permissions...${NC}"
    chown -R www-data:www-data "$PANEL_PATH"/* 2>/dev/null
    chmod -R 755 "$PANEL_PATH/storage" "$PANEL_PATH/bootstrap/cache" 2>/dev/null
    echo -e "${GREEN}✓ Permissions diperbaiki!${NC}"
    log "FIX: Permissions"
    sleep 2
}

# ============================================
#   MENU UTAMA
# ============================================
main_menu() {
    while true; do
        header
        check_services
        echo ""
        echo -e "${CYAN}📌 MENU UTAMA:${NC}"
        echo "─────────────────────────────────────────"
        echo -e "  ${GREEN}[1]${NC} 📦 Install Tools (Auto Backup)"
        echo -e "  ${RED}[2]${NC} 🗑️  Uninstall Tools"
        echo "─────────────────────────────────────────"
        echo -e "  ${GREEN}[3]${NC} 🔄 Restart Panel Services"
        echo -e "  ${GREEN}[4]${NC} 🚀 Restart Wings"
        echo -e "  ${GREEN}[5]${NC} 🧹 Clear Cache Laravel"
        echo -e "  ${GREEN}[6]${NC} 💾 Backup Sekarang (Manual)"
        echo -e "  ${GREEN}[7]${NC} 📋 Info Sistem"
        echo -e "  ${GREEN}[8]${NC} 🔧 Fix Permissions"
        echo -e "  ${RED}[0]${NC} ❌ Keluar"
        echo "─────────────────────────────────────────"
        read -p "👉 Pilih menu [0-8]: " choice
        
        case $choice in
            1) install_tools ;;
            2) uninstall_tools ;;
            3) restart_panel ;;
            4) restart_wings ;;
            5) clear_cache ;;
            6) backup_manual ;;
            7) info_system ;;
            8) fix_perms ;;
            0)
                echo -e "${GREEN}👋 Bye bro!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}✗ Pilihan tidak valid!${NC}"
                sleep 1
                ;;
        esac
    done
}

main_menu
