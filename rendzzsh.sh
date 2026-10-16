#!/bin/bash

# ============================================
#   AUTO WEB INSTALLER v1.0
#   HTML + Admin Panel + User Dashboard
#   Auto Nginx + SSL + Subdomain Setup
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Cek root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[!] Harus jalan sebagai root!${NC}"
   exit 1
fi

clear
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}   ${MAGENTA}🌐 AUTO WEB INSTALLER v1.0${NC}                ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}   ${YELLOW}HTML + Admin + User Dashboard${NC}             ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ============================================
#   INPUT SUBDOMAIN
# ============================================
read -p "👉 Masukkan subdomain (contoh: web.domain.com): " SUBDOMAIN

# Validasi
if [[ -z "$SUBDOMAIN" ]]; then
    echo -e "${RED}✗ Subdomain tidak boleh kosong!${NC}"
    exit 1
fi

if [[ ! "$SUBDOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo -e "${RED}✗ Format subdomain tidak valid!${NC}"
    echo -e "${YELLOW}Contoh: web.namadomain.com${NC}"
    exit 1
fi

read -p "👉 Masukkan email untuk SSL (Let's Encrypt): " EMAIL
if [[ -z "$EMAIL" ]]; then
    echo -e "${RED}✗ Email tidak boleh kosong!${NC}"
    exit 1
fi

# Path
WEB_ROOT="/var/www/$SUBDOMAIN"
NGINX_CONF="/etc/nginx/sites-available/$SUBDOMAIN"

echo ""
echo -e "${CYAN}📋 Konfigurasi:${NC}"
echo -e "  Subdomain : ${YELLOW}$SUBDOMAIN${NC}"
echo -e "  Email SSL : ${YELLOW}$EMAIL${NC}"
echo -e "  Web Root  : ${YELLOW}$WEB_ROOT${NC}"
echo ""
read -p "Lanjut install? (y/n): " CONFIRM
[[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && { echo -e "${YELLOW}Dibatalkan.${NC}"; exit 0; }

# ============================================
#   STEP 1 - UPDATE & INSTALL NGINX
# ============================================
echo ""
echo -e "${CYAN}[1/7] Update sistem & install Nginx...${NC}"
apt update -qq && apt install nginx curl wget -y -qq 2>/dev/null
systemctl enable nginx >/dev/null 2>&1
systemctl start nginx >/dev/null 2>&1
echo -e "${GREEN}  ✓ Nginx terinstall${NC}"

# ============================================
#   STEP 2 - BIKIN FOLDER WEB
# ============================================
echo -e "${CYAN}[2/7] Membuat struktur folder...${NC}"
mkdir -p "$WEB_ROOT"/{admin,user,assets/css,assets/js}
echo -e "${GREEN}  ✓ Folder dibuat: $WEB_ROOT${NC}"

# ============================================
#   STEP 3 - FILE HALAMAN HOME
# ============================================
echo -e "${CYAN}[3/7] Membuat halaman website...${NC}"

cat > "$WEB_ROOT/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Home - Web Saya</title>
<link rel="stylesheet" href="/assets/css/style.css">
</head>
<body>
<nav class="navbar">
    <div class="logo">🌐 Web Saya</div>
    <ul class="menu">
        <li><a href="/" class="active">Home</a></li>
        <li><a href="/admin/">Admin</a></li>
        <li><a href="/user/">Dashboard</a></li>
    </ul>
</nav>

<section class="hero">
    <h1>Selamat Datang 👋</h1>
    <p>Website ini dibuat otomatis dengan Auto Installer</p>
    <div class="btn-group">
        <a href="/admin/" class="btn btn-primary">🔐 Admin Panel</a>
        <a href="/user/" class="btn btn-secondary">👤 Dashboard User</a>
    </div>
</section>

<footer>
    <p>&copy; 2025 Web Saya. Powered by Auto Installer.</p>
</footer>
</body>
</html>
HTMLEOF

# ============================================
#   STEP 4 - HALAMAN ADMIN
# ============================================
cat > "$WEB_ROOT/admin/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Admin Panel</title>
<link rel="stylesheet" href="/assets/css/style.css">
<style>
body { background: #1a1a2e; color: #eee; }
.admin-wrap { display: flex; min-height: 100vh; }
.sidebar { width: 250px; background: #16213e; padding: 20px; }
.sidebar h2 { color: #4ade80; margin-bottom: 30px; }
.sidebar a { display: block; padding: 12px; color: #ccc; text-decoration: none; border-radius: 8px; margin-bottom: 5px; }
.sidebar a:hover { background: #0f3460; color: #fff; }
.content { flex: 1; padding: 30px; }
.cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-top: 20px; }
.card { background: #16213e; padding: 25px; border-radius: 12px; border-left: 4px solid #4ade80; }
.card h3 { font-size: 2em; color: #4ade80; margin: 0; }
.card p { color: #aaa; margin: 5px 0 0; }
</style>
</head>
<body>
<div class="admin-wrap">
    <aside class="sidebar">
        <h2>🔐 Admin</h2>
        <a href="/admin/">📊 Dashboard</a>
        <a href="#">👥 Users</a>
        <a href="#">📦 Products</a>
        <a href="#">⚙️ Settings</a>
        <a href="/">🏠 Home</a>
    </aside>
    <main class="content">
        <h1>Dashboard Admin</h1>
        <p>Selamat datang, Admin!</p>
        <div class="cards">
            <div class="card"><h3>150</h3><p>Total Users</p></div>
            <div class="card"><h3>42</h3><p>Pesanan Baru</p></div>
            <div class="card"><h3>Rp 5.2M</h3><p>Pendapatan</p></div>
            <div class="card"><h3>98%</h3><p>Uptime</p></div>
        </div>
    </main>
</div>
</body>
</html>
HTMLEOF

# ============================================
#   STEP 5 - HALAMAN USER DASHBOARD
# ============================================
cat > "$WEB_ROOT/user/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>User Dashboard</title>
<link rel="stylesheet" href="/assets/css/style.css">
<style>
body { background: #f0f4f8; }
.user-nav { background: #fff; padding: 15px 30px; box-shadow: 0 2px 10px rgba(0,0,0,0.05); display: flex; justify-content: space-between; align-items: center; }
.user-nav h2 { color: #333; margin: 0; }
.user-nav .profile { background: #4f46e5; color: #fff; width: 40px; height: 40px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-weight: bold; }
.user-content { padding: 30px; max-width: 1200px; margin: 0 auto; }
.welcome { background: linear-gradient(135deg, #4f46e5, #7c3aed); color: #fff; padding: 40px; border-radius: 16px; margin-bottom: 30px; }
.welcome h1 { margin: 0 0 10px; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; }
.box { background: #fff; padding: 25px; border-radius: 12px; box-shadow: 0 2px 10px rgba(0,0,0,0.05); }
.box .icon { font-size: 2em; margin-bottom: 10px; }
.box h3 { color: #333; margin: 0 0 5px; }
.box p { color: #888; margin: 0; font-size: 0.9em; }
</style>
</head>
<body>
<nav class="user-nav">
    <h2>👤 Dashboard User</h2>
    <div class="profile">U</div>
</nav>

<div class="user-content">
    <div class="welcome">
        <h1>Halo, User! 👋</h1>
        <p>Selamat datang di dashboard pribadi kamu</p>
    </div>
    <div class="grid">
        <div class="box"><div class="icon">📦</div><h3>Pesanan Saya</h3><p>3 pesanan aktif</p></div>
        <div class="box"><div class="icon">💰</div><h3>Saldo</h3><p>Rp 250.000</p></div>
        <div class="box"><div class="icon">🔔</div><h3>Notifikasi</h3><p>5 baru</p></div>
        <div class="box"><div class="icon">⚙️</div><h3>Pengaturan</h3><p>Profil & keamanan</p></div>
    </div>
</div>
</body>
</html>
HTMLEOF

# ============================================
#   STEP 6 - CSS UTAMA
# ============================================
cat > "$WEB_ROOT/assets/css/style.css" << 'CSSEOF'
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: 'Segoe UI', Tahoma, sans-serif; line-height: 1.6; }

.navbar {
    display: flex; justify-content: space-between; align-items: center;
    padding: 20px 40px; background: #fff; box-shadow: 0 2px 10px rgba(0,0,0,0.05);
    position: sticky; top: 0; z-index: 100;
}
.navbar .logo { font-size: 1.5em; font-weight: bold; color: #4f46e5; }
.navbar .menu { display: flex; gap: 30px; list-style: none; }
.navbar .menu a { text-decoration: none; color: #555; font-weight: 500; transition: 0.3s; }
.navbar .menu a:hover, .navbar .menu a.active { color: #4f46e5; }

.hero {
    min-height: 80vh; display: flex; flex-direction: column;
    justify-content: center; align-items: center; text-align: center;
    background: linear-gradient(135deg, #667eea, #764ba2); color: #fff; padding: 40px;
}
.hero h1 { font-size: 3.5em; margin-bottom: 20px; }
.hero p { font-size: 1.2em; margin-bottom: 30px; opacity: 0.9; }

.btn-group { display: flex; gap: 20px; flex-wrap: wrap; justify-content: center; }
.btn { padding: 15px 30px; border-radius: 50px; text-decoration: none; font-weight: 600; transition: 0.3s; }
.btn-primary { background: #fff; color: #764ba2; }
.btn-primary:hover { transform: translateY(-3px); box-shadow: 0 10px 20px rgba(0,0,0,0.2); }
.btn-secondary { background: rgba(255,255,255,0.2); color: #fff; border: 2px solid #fff; }
.btn-secondary:hover { background: #fff; color: #764ba2; }

footer { text-align: center; padding: 30px; background: #1a1a2e; color: #888; }
CSSEOF

echo -e "${GREEN}  ✓ Semua halaman dibuat${NC}"

# ============================================
#   STEP 7 - KONFIGURASI NGINX
# ============================================
echo -e "${CYAN}[4/7] Konfigurasi Nginx...${NC}"
cat > "$NGINX_CONF" << NGINXEOF
server {
    listen 80;
    listen [::]:80;
    server_name $SUBDOMAIN;

    root $WEB_ROOT;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location /admin/ {
        try_files \$uri \$uri/ /admin/index.html;
    }

    location /user/ {
        try_files \$uri \$uri/ /user/index.html;
    }

    access_log /var/log/nginx/$SUBDOMAIN.access.log;
    error_log /var/log/nginx/$SUBDOMAIN.error.log;
}
NGINXEOF

# Aktifkan
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/ 2>/dev/null

# Hapus default kalau ada (biar gak bingung)
if [[ -f /etc/nginx/sites-enabled/default ]]; then
    rm -f /etc/nginx/sites-enabled/default
fi

# Test config
if nginx -t >/dev/null 2>&1; then
    echo -e "${GREEN}  ✓ Konfigurasi Nginx valid${NC}"
    systemctl reload nginx
    echo -e "${GREEN}  ✓ Nginx reloaded${NC}"
else
    echo -e "${RED}  ✗ Konfigurasi Nginx error!${NC}"
    nginx -t
    exit 1
fi

# Permission
chown -R www-data:www-data "$WEB_ROOT"
chmod -R 755 "$WEB_ROOT"
echo -e "${GREEN}  ✓ Permission diatur${NC}"

# ============================================
#   STEP 8 - SSL (Let's Encrypt)
# ============================================
echo -e "${CYAN}[5/7] Memasang SSL (HTTPS)...${NC}"

# Cek DNS dulu
SERVER_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null)
DOMAIN_IP=$(getent hosts "$SUBDOMAIN" | awk '{print $1}' | head -1)

if [[ "$SERVER_IP" == "$DOMAIN_IP" ]]; then
    echo -e "${GREEN}  ✓ DNS sudah mengarah ke VPS${NC}"
    
    apt install certbot python3-certbot-nginx -y -qq 2>/dev/null
    if certbot --nginx -d "$SUBDOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect >/dev/null 2>&1; then
        echo -e "${GREEN}  ✓ SSL berhasil dipasang!${NC}"
        SSL_STATUS="aktif ✅"
    else
        echo -e "${YELLOW}  ⚠️  SSL gagal dipasang (bisa coba manual nanti)${NC}"
        SSL_STATUS="gagal ⚠️"
    fi
else
    echo -e "${YELLOW}  ⚠️  DNS belum mengarah ke VPS ini!${NC}"
    echo -e "${YELLOW}  Server IP : $SERVER_IP${NC}"
    echo -e "${YELLOW}  Domain IP : ${DOMAIN_IP:-tidak terdeteksi}${NC}"
    echo -e "${YELLOW}  → SSL dilewati. Pasang nanti dengan:${NC}"
    echo -e "${CYAN}    certbot --nginx -d $SUBDOMAIN${NC}"
    SSL_STATUS="dilewati (DNS belum siap) ⚠️"
fi

# ============================================
#   STEP 9 - FIREWALL
# ============================================
echo -e "${CYAN}[6/7] Setup firewall...${NC}"
if command -v ufw >/dev/null 2>&1; then
    ufw allow 80/tcp >/dev/null 2>&1
    ufw allow 443/tcp >/dev/null 2>&1
    ufw allow 22/tcp >/dev/null 2>&1
    echo -e "${GREEN}  ✓ Firewall dibuka (80, 443, 22)${NC}"
else
    echo -e "${YELLOW}  - ufw tidak ada, dilewati${NC}"
fi

# ============================================
#   SELESAI
# ============================================
echo -e "${CYAN}[7/7] Selesai!${NC}"
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✅ INSTALLASI BERHASIL!${NC}                        ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}🔗 Akses Website:${NC}"
if [[ "$SSL_STATUS" == *"aktif"* ]]; then
    echo -e "  Home    : ${YELLOW}https://$SUBDOMAIN${NC}"
    echo -e "  Admin   : ${YELLOW}https://$SUBDOMAIN/admin/${NC}"
    echo -e "  User    : ${YELLOW}https://$SUBDOMAIN/user/${NC}"
else
    echo -e "  Home    : ${YELLOW}http://$SUBDOMAIN${NC}"
    echo -e "  Admin   : ${YELLOW}http://$SUBDOMAIN/admin/${NC}"
    echo -e "  User    : ${YELLOW}http://$SUBDOMAIN/user/${NC}"
fi
echo ""
echo -e "${CYAN}📁 Lokasi File:${NC}"
echo -e "  Web     : $WEB_ROOT"
echo -e "  Nginx   : $NGINX_CONF"
echo ""
echo -e "${CYAN}🔒 Status SSL: $SSL_STATUS${NC}"
echo ""
echo -e "${MAGENTA}💡 Tips:${NC}"
echo -e "  • Edit file di: ${YELLOW}$WEB_ROOT${NC}"
echo -e "  • Reload nginx: ${YELLOW}systemctl reload nginx${NC}"
echo -e "  • Cek log: ${YELLOW}tail -f /var/log/nginx/$SUBDOMAIN.error.log${NC}"
echo ""
echo -e "${GREEN}Terima kasih bro! 🎉${NC}"
