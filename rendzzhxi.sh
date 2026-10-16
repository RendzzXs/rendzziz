#!/bin/bash

# ============================================
#   🔥 WEB PANEL FULL FEATURED INSTALLER v1.0
#   Login • Register • Admin • Dashboard
#   Live Stats • User Management • Dark Theme
# ============================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'

[[ $EUID -ne 0 ]] && { echo -e "${RED}Harus root bro!${NC}"; exit 1; }

clear
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}   ${MAGENTA}🔥 WEB PANEL FULL FEATURED INSTALLER${NC}      ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}   ${YELLOW}Login • Register • Admin • Dashboard${NC}      ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}   ${YELLOW}Live Stats • User Management • Dark Theme${NC} ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ============ INPUT ============
read -p "👉 Subdomain (contoh: web.domain.com): " SUBDOMAIN
[[ -z "$SUBDOMAIN" ]] && { echo -e "${RED}Kosong!${NC}"; exit 1; }

read -p "👉 Email untuk SSL: " EMAIL
[[ -z "$EMAIL" ]] && { echo -e "${RED}Kosong!${NC}"; exit 1; }

read -p "👉 Username admin: " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}

read -p "👉 Password admin (min 6 char): " ADMIN_PASS
[[ ${#ADMIN_PASS} -lt 6 ]] && { echo -e "${RED}Minimal 6 karakter!${NC}"; exit 1; }

read -p "👉 Email admin: " ADMIN_EMAIL
ADMIN_EMAIL=${ADMIN_EMAIL:-admin@$SUBDOMAIN}

DB_PASS=$(openssl rand -hex 16)
DB_NAME="webpanel_$(echo $SUBDOMAIN | tr '.' '_' | cut -c1-20)"
WEB_ROOT="/var/www/$SUBDOMAIN"
NGINX_CONF="/etc/nginx/sites-available/$SUBDOMAIN"

echo ""
echo -e "${CYAN}📋 Konfigurasi:${NC}"
echo -e "  Subdomain    : ${YELLOW}$SUBDOMAIN${NC}"
echo -e "  Admin User   : ${YELLOW}$ADMIN_USER${NC}"
echo -e "  Admin Email  : ${YELLOW}$ADMIN_EMAIL${NC}"
echo ""
read -p "Lanjut install? (y/n): " CONFIRM
[[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && exit 0

# ============ STEP 1: INSTALL PACKAGES ============
echo ""
echo -e "${CYAN}[1/8] Install Nginx, PHP, MySQL...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update -qq 2>/dev/null
apt install nginx php8.3-fpm php8.3-mysql php8.3-mbstring php8.3-curl php8.3-xml php8.3-zip mysql-server unzip curl wget openssl -y -qq 2>/dev/null
systemctl enable nginx php8.3-fpm mysql >/dev/null 2>&1
systemctl start nginx php8.3-fpm mysql >/dev/null 2>&1
echo -e "${GREEN}  ✓ Terinstall${NC}"

# ============ STEP 2: SETUP DATABASE ============
echo -e "${CYAN}[2/8] Setup database...${NC}"
mysql -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;" 2>/dev/null
mysql -e "CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS 'wpuser'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO 'wpuser'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

mysql "$DB_NAME" << 'SQLEOF'
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    role ENUM('admin','user') DEFAULT 'user',
    avatar VARCHAR(255) DEFAULT NULL,
    status ENUM('active','banned') DEFAULT 'active',
    last_login DATETIME DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE activity_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    action VARCHAR(255),
    ip VARCHAR(45),
    user_agent TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE settings (
    key_name VARCHAR(50) PRIMARY KEY,
    value TEXT
);

INSERT INTO settings VALUES ('site_name', 'Web Panel');
INSERT INTO settings VALUES ('site_desc', 'Panel modern dengan fitur lengkap');
SQLEOF

echo -e "${GREEN}  ✓ Database & tabel dibuat${NC}"

# ============ STEP 3: BUAT STRUKTUR FOLDER ============
echo -e "${CYAN}[3/8] Membuat struktur folder...${NC}"
mkdir -p "$WEB_ROOT"/{admin,user,api,includes,assets/{css,js,img},uploads}
echo -e "${GREEN}  ✓ Folder dibuat${NC}"

# ============ STEP 4: FILE KONFIGURASI ============
echo -e "${CYAN}[4/8] Membuat file konfigurasi...${NC}"

cat > "$WEB_ROOT/includes/config.php" << PHPEOF
<?php
session_start();
define('DB_HOST', 'localhost');
define('DB_NAME', '$DB_NAME');
define('DB_USER', 'wpuser');
define('DB_PASS', '$DB_PASS');
define('SITE_URL', 'https://$SUBDOMAIN');
define('SITE_NAME', 'Web Panel');

try {
    \$pdo = new PDO("mysql:host=".DB_HOST.";dbname=".DB_NAME.";charset=utf8mb4", DB_USER, DB_PASS, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
} catch (PDOException \$e) {
    die("DB Error: " . \$e->getMessage());
}

// Helper functions
function isLoggedIn() { return isset(\$_SESSION['user_id']); }
function isAdmin() { return isLoggedIn() && \$_SESSION['role'] === 'admin'; }
function requireLogin() { if (!isLoggedIn()) { header('Location: /login.php'); exit; } }
function requireAdmin() { if (!isAdmin()) { header('Location: /user/'); exit; } }
function csrf() {
    if (empty(\$_SESSION['csrf'])) \$_SESSION['csrf'] = bin2hex(random_bytes(32));
    return \$_SESSION['csrf'];
}
function checkCsrf(\$t) { return isset(\$_SESSION['csrf']) && hash_equals(\$_SESSION['csrf'], \$t); }
function logActivity(\$pdo, \$uid, \$action) {
    \$stmt = \$pdo->prepare("INSERT INTO activity_log (user_id, action, ip, user_agent) VALUES (?,?,?,?)");
    \$stmt->execute([\$uid, \$action, \$_SERVER['REMOTE_ADDR'] ?? '', \$_SERVER['HTTP_USER_AGENT'] ?? '']);
}
PHPEOF

# Bikin admin user
ADMIN_HASH=$(php -r "echo password_hash('$ADMIN_PASS', PASSWORD_BCRYPT);")
mysql "$DB_NAME" -e "INSERT INTO users (username, email, password, role, status) VALUES ('$ADMIN_USER', '$ADMIN_EMAIL', '$ADMIN_HASH', 'admin', 'active');"

echo -e "${GREEN}  ✓ Config & admin dibuat${NC}"

# ============ STEP 5: FILE PHP UTAMA ============
echo -e "${CYAN}[5/8] Membuat halaman PHP...${NC}"

# ---------- HEADER (include) ----------
cat > "$WEB_ROOT/includes/header.php" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="id" data-theme="dark">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title><?= $pageTitle ?? 'Web Panel' ?> - <?= SITE_NAME ?></title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
<link rel="stylesheet" href="/assets/css/style.css">
</head>
<body>
HTMLEOF

# ---------- NAVBAR (include) ----------
cat > "$WEB_ROOT/includes/navbar.php" << 'HTMLEOF'
<nav class="navbar">
    <div class="nav-left">
        <a href="/" class="logo"><i class="fas fa-rocket"></i> <?= SITE_NAME ?></a>
    </div>
    <div class="nav-center">
        <a href="/"><i class="fas fa-home"></i> Home</a>
        <?php if (isLoggedIn()): ?>
            <a href="/user/"><i class="fas fa-tachometer-alt"></i> Dashboard</a>
            <?php if (isAdmin()): ?>
                <a href="/admin/"><i class="fas fa-crown"></i> Admin</a>
            <?php endif; ?>
        <?php endif; ?>
    </div>
    <div class="nav-right">
        <button id="themeToggle" class="icon-btn" title="Toggle Theme">
            <i class="fas fa-moon"></i>
        </button>
        <?php if (isLoggedIn()): ?>
            <div class="user-menu">
                <button class="icon-btn user-btn">
                    <i class="fas fa-user-circle"></i>
                    <span><?= htmlspecialchars($_SESSION['username']) ?></span>
                </button>
                <div class="dropdown">
                    <a href="/user/"><i class="fas fa-tachometer-alt"></i> Dashboard</a>
                    <a href="/user/profile.php"><i class="fas fa-user-edit"></i> Profile</a>
                    <a href="/logout.php"><i class="fas fa-sign-out-alt"></i> Logout</a>
                </div>
            </div>
        <?php else: ?>
            <a href="/login.php" class="btn btn-primary"><i class="fas fa-sign-in-alt"></i> Login</a>
            <a href="/register.php" class="btn btn-outline"><i class="fas fa-user-plus"></i> Register</a>
        <?php endif; ?>
    </div>
</nav>
HTMLEOF

# ---------- FOOTER ----------
cat > "$WEB_ROOT/includes/footer.php" << 'HTMLEOF'
<footer class="footer">
    <p><i class="fas fa-copyright"></i> <?= date('Y') ?> <?= SITE_NAME ?>. Powered by <i class="fas fa-heart" style="color:#e74c3c"></i></p>
</footer>
<script src="/assets/js/main.js"></script>
</body>
</html>
HTMLEOF

# ---------- HOME / INDEX ----------
cat > "$WEB_ROOT/index.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/includes/config.php';
$pageTitle = 'Home';
include __DIR__ . '/includes/header.php';
include __DIR__ . '/includes/navbar.php';
?>
<section class="hero">
    <div class="hero-content">
        <h1><i class="fas fa-rocket"></i> Selamat Datang di <?= SITE_NAME ?></h1>
        <p>Panel modern dengan fitur lengkap: Login, Register, Dashboard Admin, User Management, Live Stats, dan Dark Theme!</p>
        <div class="btn-group">
            <?php if (isLoggedIn()): ?>
                <a href="/user/" class="btn btn-primary btn-lg"><i class="fas fa-tachometer-alt"></i> Buka Dashboard</a>
            <?php else: ?>
                <a href="/register.php" class="btn btn-primary btn-lg"><i class="fas fa-user-plus"></i> Daftar Sekarang</a>
                <a href="/login.php" class="btn btn-outline btn-lg"><i class="fas fa-sign-in-alt"></i> Login</a>
            <?php endif; ?>
        </div>
    </div>
</section>

<section class="features">
    <h2><i class="fas fa-star"></i> Fitur Unggulan</h2>
    <div class="feature-grid">
        <div class="feature-card"><i class="fas fa-lock"></i><h3>Login Aman</h3><p>Password hash bcrypt + CSRF protection</p></div>
        <div class="feature-card"><i class="fas fa-users-cog"></i><h3>User Management</h3><p>Kelola user dengan mudah dari admin panel</p></div>
        <div class="feature-card"><i class="fas fa-chart-line"></i><h3>Live Statistik</h3><p>Monitoring user & aktivitas secara real-time</p></div>
        <div class="feature-card"><i class="fas fa-moon"></i><h3>Dark Theme</h3><p>Mode gelap & terang dengan satu klik</p></div>
        <div class="feature-card"><i class="fas fa-shield-alt"></i><h3>Keamanan</h3><p>Proteksi CSRF, XSS, dan SQL Injection</p></div>
        <div class="feature-card"><i class="fas fa-mobile-alt"></i><h3>Responsive</h3><p>Tampilan optimal di semua device</p></div>
    </div>
</section>
<?php include __DIR__ . '/includes/footer.php'; ?>
PHPEOF

# ---------- LOGIN ----------
cat > "$WEB_ROOT/login.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/includes/config.php';
$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!checkCsrf($_POST['csrf'] ?? '')) { $error = 'Invalid CSRF token'; }
    else {
        $username = trim($_POST['username'] ?? '');
        $password = $_POST['password'] ?? '';
        $stmt = $pdo->prepare("SELECT * FROM users WHERE username=? OR email=? LIMIT 1");
        $stmt->execute([$username, $username]);
        $user = $stmt->fetch();
        if ($user && password_verify($password, $user['password'])) {
            if ($user['status'] === 'banned') { $error = 'Akun kamu dibanned!'; }
            else {
                $_SESSION['user_id'] = $user['id'];
                $_SESSION['username'] = $user['username'];
                $_SESSION['role'] = $user['role'];
                $pdo->prepare("UPDATE users SET last_login=NOW() WHERE id=?")->execute([$user['id']]);
                logActivity($pdo, $user['id'], 'Login');
                header('Location: ' . ($user['role'] === 'admin' ? '/admin/' : '/user/'));
                exit;
            }
        } else { $error = 'Username atau password salah!'; }
    }
}
$pageTitle = 'Login';
include __DIR__ . '/includes/header.php';
include __DIR__ . '/includes/navbar.php';
?>
<div class="auth-wrap">
    <div class="auth-card">
        <h1><i class="fas fa-sign-in-alt"></i> Login</h1>
        <p class="subtitle">Masuk ke akun kamu</p>
        <?php if ($error): ?><div class="alert alert-error"><i class="fas fa-exclamation-circle"></i> <?= $error ?></div><?php endif; ?>
        <form method="POST">
            <input type="hidden" name="csrf" value="<?= csrf() ?>">
            <div class="form-group">
                <label><i class="fas fa-user"></i> Username / Email</label>
                <input type="text" name="username" required autofocus>
            </div>
            <div class="form-group">
                <label><i class="fas fa-lock"></i> Password</label>
                <input type="password" name="password" required>
            </div>
            <button type="submit" class="btn btn-primary btn-block"><i class="fas fa-sign-in-alt"></i> Login</button>
        </form>
        <p class="auth-footer">Belum punya akun? <a href="/register.php">Daftar di sini</a></p>
    </div>
</div>
<?php include __DIR__ . '/includes/footer.php'; ?>
PHPEOF

# ---------- REGISTER ----------
cat > "$WEB_ROOT/register.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/includes/config.php';
if (isLoggedIn()) { header('Location: /user/'); exit; }
$error = ''; $success = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!checkCsrf($_POST['csrf'] ?? '')) { $error = 'Invalid CSRF'; }
    else {
        $username = trim($_POST['username'] ?? '');
        $email = trim($_POST['email'] ?? '');
        $password = $_POST['password'] ?? '';
        $confirm = $_POST['confirm'] ?? '';
        
        if (strlen($username) < 3) $error = 'Username minimal 3 karakter';
        elseif (!filter_var($email, FILTER_VALIDATE_EMAIL)) $error = 'Email tidak valid';
        elseif (strlen($password) < 6) $error = 'Password minimal 6 karakter';
        elseif ($password !== $confirm) $error = 'Konfirmasi password tidak cocok';
        else {
            $stmt = $pdo->prepare("SELECT id FROM users WHERE username=? OR email=?");
            $stmt->execute([$username, $email]);
            if ($stmt->fetch()) { $error = 'Username atau email sudah dipakai'; }
            else {
                $hash = password_hash($password, PASSWORD_BCRYPT);
                $pdo->prepare("INSERT INTO users (username, email, password) VALUES (?,?,?)")->execute([$username, $email, $hash]);
                $success = 'Registrasi berhasil! Silakan login.';
            }
        }
    }
}
$pageTitle = 'Register';
include __DIR__ . '/includes/header.php';
include __DIR__ . '/includes/navbar.php';
?>
<div class="auth-wrap">
    <div class="auth-card">
        <h1><i class="fas fa-user-plus"></i> Register</h1>
        <p class="subtitle">Buat akun baru</p>
        <?php if ($error): ?><div class="alert alert-error"><i class="fas fa-exclamation-circle"></i> <?= $error ?></div><?php endif; ?>
        <?php if ($success): ?><div class="alert alert-success"><i class="fas fa-check-circle"></i> <?= $success ?> <a href="/login.php">Login</a></div><?php endif; ?>
        <form method="POST">
            <input type="hidden" name="csrf" value="<?= csrf() ?>">
            <div class="form-group"><label><i class="fas fa-user"></i> Username</label><input type="text" name="username" required></div>
            <div class="form-group"><label><i class="fas fa-envelope"></i> Email</label><input type="email" name="email" required></div>
            <div class="form-group"><label><i class="fas fa-lock"></i> Password</label><input type="password" name="password" required></div>
            <div class="form-group"><label><i class="fas fa-lock"></i> Konfirmasi Password</label><input type="password" name="confirm" required></div>
            <button type="submit" class="btn btn-primary btn-block"><i class="fas fa-user-plus"></i> Daftar</button>
        </form>
        <p class="auth-footer">Sudah punya akun? <a href="/login.php">Login di sini</a></p>
    </div>
</div>
<?php include __DIR__ . '/includes/footer.php'; ?>
PHPEOF

# ---------- LOGOUT ----------
cat > "$WEB_ROOT/logout.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/includes/config.php';
if (isLoggedIn()) logActivity($pdo, $_SESSION['user_id'], 'Logout');
session_destroy();
header('Location: /login.php');
exit;
PHPEOF

# ---------- USER DASHBOARD ----------
cat > "$WEB_ROOT/user/index.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/../includes/config.php';
requireLogin();
$pageTitle = 'Dashboard';
$myLogs = $pdo->prepare("SELECT * FROM activity_log WHERE user_id=? ORDER BY id DESC LIMIT 10");
$myLogs->execute([$_SESSION['user_id']]);
$myLogs = $myLogs->fetchAll();
include __DIR__ . '/../includes/header.php';
include __DIR__ . '/../includes/navbar.php';
?>
<div class="container">
    <div class="page-header">
        <h1><i class="fas fa-tachometer-alt"></i> Dashboard User</h1>
        <p>Selamat datang, <strong><?= htmlspecialchars($_SESSION['username']) ?></strong>! 👋</p>
    </div>
    
    <div class="stats-grid">
        <div class="stat-card"><div class="stat-icon" style="background:linear-gradient(135deg,#667eea,#764ba2)"><i class="fas fa-calendar"></i></div><div class="stat-info"><h3><?= date('d M Y') ?></h3><p>Hari ini</p></div></div>
        <div class="stat-card"><div class="stat-icon" style="background:linear-gradient(135deg,#f093fb,#f5576c)"><i class="fas fa-clock"></i></div><div class="stat-info"><h3><?= date('H:i') ?></h3><p>Waktu server</p></div></div>
        <div class="stat-card"><div class="stat-icon" style="background:linear-gradient(135deg,#4facfe,#00f2fe)"><i class="fas fa-shield-alt"></i></div><div class="stat-info"><h3>Aktif</h3><p>Status akun</p></div></div>
        <div class="stat-card"><div class="stat-icon" style="background:linear-gradient(135deg,#43e97b,#38f9d7)"><i class="fas fa-star"></i></div><div class="stat-info"><h3><?= ucfirst($_SESSION['role']) ?></h3><p>Role kamu</p></div></div>
    </div>
    
    <div class="card">
        <h2><i class="fas fa-history"></i> Aktivitas Terakhir</h2>
        <table class="table">
            <thead><tr><th>Action</th><th>IP</th><th>Waktu</th></tr></thead>
            <tbody>
                <?php if (empty($myLogs)): ?>
                    <tr><td colspan="3" style="text-align:center;color:#888">Belum ada aktivitas</td></tr>
                <?php else: foreach ($myLogs as $log): ?>
                    <tr><td><i class="fas fa-circle-dot"></i> <?= htmlspecialchars($log['action']) ?></td><td><code><?= htmlspecialchars($log['ip']) ?></code></td><td><?= $log['created_at'] ?></td></tr>
                <?php endforeach; endif; ?>
            </tbody>
        </table>
    </div>
</div>
<?php include __DIR__ . '/../includes/footer.php'; ?>
PHPEOF

# ---------- USER PROFILE ----------
cat > "$WEB_ROOT/user/profile.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/../includes/config.php';
requireLogin();
$msg = ''; $err = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!checkCsrf($_POST['csrf'] ?? '')) { $err = 'Invalid CSRF'; }
    else {
        $email = trim($_POST['email'] ?? '');
        $newpass = $_POST['newpass'] ?? '';
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) $err = 'Email tidak valid';
        else {
            if ($newpass) {
                if (strlen($newpass) < 6) $err = 'Password minimal 6 char';
                else {
                    $hash = password_hash($newpass, PASSWORD_BCRYPT);
                    $pdo->prepare("UPDATE users SET email=?, password=? WHERE id=?")->execute([$email, $hash, $_SESSION['user_id']]);
                    $msg = 'Profile & password diupdate!';
                }
            } else {
                $pdo->prepare("UPDATE users SET email=? WHERE id=?")->execute([$email, $_SESSION['user_id']]);
                $msg = 'Profile diupdate!';
            }
            if (!$err) logActivity($pdo, $_SESSION['user_id'], 'Update profile');
        }
    }
}
$user = $pdo->prepare("SELECT * FROM users WHERE id=?");
$user->execute([$_SESSION['user_id']]);
$user = $user->fetch();
$pageTitle = 'Profile';
include __DIR__ . '/../includes/header.php';
include __DIR__ . '/../includes/navbar.php';
?>
<div class="container-narrow">
    <div class="card">
        <h1><i class="fas fa-user-edit"></i> Edit Profile</h1>
        <?php if ($msg): ?><div class="alert alert-success"><?= $msg ?></div><?php endif; ?>
        <?php if ($err): ?><div class="alert alert-error"><?= $err ?></div><?php endif; ?>
        <form method="POST">
            <input type="hidden" name="csrf" value="<?= csrf() ?>">
            <div class="form-group"><label><i class="fas fa-user"></i> Username (tidak bisa diubah)</label><input type="text" value="<?= htmlspecialchars($user['username']) ?>" disabled></div>
            <div class="form-group"><label><i class="fas fa-envelope"></i> Email</label><input type="email" name="email" value="<?= htmlspecialchars($user['email']) ?>" required></div>
            <div class="form-group"><label><i class="fas fa-lock"></i> Password Baru (kosongkan jika tidak diubah)</label><input type="password" name="newpass"></div>
            <button class="btn btn-primary"><i class="fas fa-save"></i> Simpan</button>
            <a href="/user/" class="btn btn-outline"><i class="fas fa-arrow-left"></i> Kembali</a>
        </form>
    </div>
</div>
<?php include __DIR__ . '/../includes/footer.php'; ?>
PHPEOF

# ---------- ADMIN DASHBOARD ----------
cat > "$WEB_ROOT/admin/index.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/../includes/config.php';
requireAdmin();
$pageTitle = 'Admin Dashboard';

$totalUsers = $pdo->query("SELECT COUNT(*) FROM users")->fetchColumn();
$totalAdmins = $pdo->query("SELECT COUNT(*) FROM users WHERE role='admin'")->fetchColumn();
$totalBanned = $pdo->query("SELECT COUNT(*) FROM users WHERE status='banned'")->fetchColumn();
$activeToday = $pdo->query("SELECT COUNT(*) FROM users WHERE DATE(last_login)=CURDATE()")->fetchColumn();
$totalLogs = $pdo->query("SELECT COUNT(*) FROM activity_log")->fetchColumn();

$recentUsers = $pdo->query("SELECT * FROM users ORDER BY id DESC LIMIT 5")->fetchAll();
$recentLogs = $pdo->query("SELECT al.*, u.username FROM activity_log al LEFT JOIN users u ON al.user_id=u.id ORDER BY al.id DESC LIMIT 10")->fetchAll();

include __DIR__ . '/../includes/header.php';
include __DIR__ . '/../includes/navbar.php';
?>
<div class="container">
    <div class="page-header">
        <h1><i class="fas fa-crown"></i> Admin Dashboard</h1>
        <p>Panel kontrol administrator</p>
    </div>
    
    <div class="stats-grid">
        <div class="stat-card"><div class="stat-icon" style="background:linear-gradient(135deg,#667eea,#764ba2)"><i class="fas fa-users"></i></div><div class="stat-info"><h3><?= $totalUsers ?></h3><p>Total Users</p></div></div>
        <div class="stat-card"><div class="stat-icon" style="background:linear-gradient(135deg,#f093fb,#f5576c)"><i class="fas fa-crown"></i></div><div class="stat-info"><h3><?= $totalAdmins ?></h3><p>Admins</p></div></div>
        <div class="stat-card"><div class="stat-icon" style="background:linear-gradient(135deg,#fa709a,#fee140)"><i class="fas fa-user-slash"></i></div><div class="stat-info"><h3><?= $totalBanned ?></h3><p>Banned</p></div></div>
        <div class="stat-card"><div class="stat-icon" style="background:linear-gradient(135deg,#43e97b,#38f9d7)"><i class="fas fa-user-check"></i></div><div class="stat-info"><h3><?= $activeToday ?></h3><p>Aktif Hari Ini</p></div></div>
        <div class="stat-card"><div class="stat-icon" style="background:linear-gradient(135deg,#4facfe,#00f2fe)"><i class="fas fa-list"></i></div><div class="stat-info"><h3><?= $totalLogs ?></h3><p>Total Log</p></div></div>
    </div>
    
    <div class="grid-2">
        <div class="card">
            <h2><i class="fas fa-user-plus"></i> User Terbaru</h2>
            <table class="table">
                <thead><tr><th>User</th><th>Role</th><th>Status</th></tr></thead>
                <tbody>
                    <?php foreach ($recentUsers as $u): ?>
                    <tr>
                        <td><i class="fas fa-user-circle"></i> <?= htmlspecialchars($u['username']) ?></td>
                        <td><span class="badge badge-<?= $u['role'] ?>"><?= $u['role'] ?></span></td>
                        <td><span class="badge badge-<?= $u['status'] ?>"><?= $u['status'] ?></span></td>
                    </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
        </div>
        <div class="card">
            <h2><i class="fas fa-history"></i> Log Terbaru</h2>
            <table class="table">
                <thead><tr><th>User</th><th>Action</th><th>Waktu</th></tr></thead>
                <tbody>
                    <?php foreach ($recentLogs as $l): ?>
                    <tr>
                        <td><?= htmlspecialchars($l['username'] ?? 'N/A') ?></td>
                        <td><?= htmlspecialchars($l['action']) ?></td>
                        <td><small><?= date('d/m H:i', strtotime($l['created_at'])) ?></small></td>
                    </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
        </div>
    </div>
    
    <div class="quick-actions">
        <a href="/admin/users.php" class="action-btn"><i class="fas fa-users-cog"></i><span>Manage Users</span></a>
        <a href="/admin/logs.php" class="action-btn"><i class="fas fa-list-alt"></i><span>Activity Log</span></a>
        <a href="/admin/settings.php" class="action-btn"><i class="fas fa-cog"></i><span>Settings</span></a>
        <a href="/user/" class="action-btn"><i class="fas fa-user"></i><span>User View</span></a>
    </div>
</div>
<?php include __DIR__ . '/../includes/footer.php'; ?>
PHPEOF

# ---------- ADMIN USER MANAGEMENT ----------
cat > "$WEB_ROOT/admin/users.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/../includes/config.php';
requireAdmin();
$msg = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && checkCsrf($_POST['csrf'] ?? '')) {
    $action = $_POST['action'] ?? '';
    $uid = (int)($_POST['uid'] ?? 0);
    if ($uid && $uid != $_SESSION['user_id']) {
        if ($action === 'ban') { $pdo->prepare("UPDATE users SET status='banned' WHERE id=?")->execute([$uid]); $msg = 'User dibanned'; }
        elseif ($action === 'unban') { $pdo->prepare("UPDATE users SET status='active' WHERE id=?")->execute([$uid]); $msg = 'User di-unban'; }
        elseif ($action === 'makerev_admin') { $pdo->prepare("UPDATE users SET role='admin' WHERE id=?")->execute([$uid]); $msg = 'User jadi admin'; }
        elseif ($action === 'remove_admin') { $pdo->prepare("UPDATE users SET role='user' WHERE id=?")->execute([$uid]); $msg = 'Admin jadi user'; }
        elseif ($action === 'delete') { $pdo->prepare("DELETE FROM users WHERE id=?")->execute([$uid]); $msg = 'User dihapus'; }
        logActivity($pdo, $_SESSION['user_id'], "Admin: $action user ID $uid");
    }
}
$users = $pdo->query("SELECT * FROM users ORDER BY id DESC")->fetchAll();
$pageTitle = 'User Management';
include __DIR__ . '/../includes/header.php';
include __DIR__ . '/../includes/navbar.php';
?>
<div class="container">
    <div class="page-header">
        <h1><i class="fas fa-users-cog"></i> User Management</h1>
        <p>Kelola semua user di sini</p>
    </div>
    <?php if ($msg): ?><div class="alert alert-success"><?= $msg ?></div><?php endif; ?>
    
    <div class="card">
        <table class="table">
            <thead>
                <tr><th>ID</th><th>Username</th><th>Email</th><th>Role</th><th>Status</th><th>Last Login</th><th>Aksi</th></tr>
            </thead>
            <tbody>
                <?php foreach ($users as $u): ?>
                <tr>
                    <td>#<?= $u['id'] ?></td>
                    <td><i class="fas fa-user-circle"></i> <?= htmlspecialchars($u['username']) ?></td>
                    <td><?= htmlspecialchars($u['email']) ?></td>
                    <td><span class="badge badge-<?= $u['role'] ?>"><?= $u['role'] ?></span></td>
                    <td><span class="badge badge-<?= $u['status'] ?>"><?= $u['status'] ?></span></td>
                    <td><small><?= $u['last_login'] ?? 'Never' ?></small></td>
                    <td class="actions">
                        <?php if ($u['id'] != $_SESSION['user_id']): ?>
                        <form method="POST" style="display:inline" onsubmit="return confirm('Yakin?')">
                            <input type="hidden" name="csrf" value="<?= csrf() ?>">
                            <input type="hidden" name="uid" value="<?= $u['id'] ?>">
                            <?php if ($u['status'] === 'active'): ?>
                                <button name="action" value="ban" class="btn-icon btn-warn" title="Ban"><i class="fas fa-ban"></i></button>
                            <?php else: ?>
                                <button name="action" value="unban" class="btn-icon btn-ok" title="Unban"><i class="fas fa-check"></i></button>
                            <?php endif; ?>
                            <?php if ($u['role'] === 'user'): ?>
                                <button name="action" value="makerev_admin" class="btn-icon btn-info" title="Jadikan Admin"><i class="fas fa-crown"></i></button>
                            <?php else: ?>
                                <button name="action" value="remove_admin" class="btn-icon btn-info" title="Jadikan User"><i class="fas fa-user"></i></button>
                            <?php endif; ?>
                            <button name="action" value="delete" class="btn-icon btn-danger" title="Hapus"><i class="fas fa-trash"></i></button>
                        </form>
                        <?php else: ?>
                            <span class="badge badge-info">Kamu</span>
                        <?php endif; ?>
                    </td>
                </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    </div>
</div>
<?php include __DIR__ . '/../includes/footer.php'; ?>
PHPEOF

# ---------- ADMIN LOGS ----------
cat > "$WEB_ROOT/admin/logs.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/../includes/config.php';
requireAdmin();
$logs = $pdo->query("SELECT al.*, u.username FROM activity_log al LEFT JOIN users u ON al.user_id=u.id ORDER BY al.id DESC LIMIT 100")->fetchAll();
$pageTitle = 'Activity Logs';
include __DIR__ . '/../includes/header.php';
include __DIR__ . '/../includes/navbar.php';
?>
<div class="container">
    <div class="page-header">
        <h1><i class="fas fa-list-alt"></i> Activity Logs</h1>
        <p>100 aktivitas terakhir</p>
    </div>
    <div class="card">
        <table class="table">
            <thead><tr><th>ID</th><th>User</th><th>Action</th><th>IP</th><th>Waktu</th></tr></thead>
            <tbody>
                <?php foreach ($logs as $l): ?>
                <tr>
                    <td>#<?= $l['id'] ?></td>
                    <td><?= htmlspecialchars($l['username'] ?? 'Guest') ?></td>
                    <td><?= htmlspecialchars($l['action']) ?></td>
                    <td><code><?= htmlspecialchars($l['ip']) ?></code></td>
                    <td><small><?= $l['created_at'] ?></small></td>
                </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    </div>
</div>
<?php include __DIR__ . '/../includes/footer.php'; ?>
PHPEOF

# ---------- ADMIN SETTINGS ----------
cat > "$WEB_ROOT/admin/settings.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/../includes/config.php';
requireAdmin();
$msg = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && checkCsrf($_POST['csrf'] ?? '')) {
    $pdo->prepare("UPDATE settings SET value=? WHERE key_name='site_name'")->execute([$_POST['site_name']]);
    $pdo->prepare("UPDATE settings SET value=? WHERE key_name='site_desc'")->execute([$_POST['site_desc']]);
    $msg = 'Settings disimpan!';
}
$get = function($k) use ($pdo) { $s = $pdo->prepare("SELECT value FROM settings WHERE key_name=?"); $s->execute([$k]); return $s->fetchColumn(); };
$pageTitle = 'Settings';
include __DIR__ . '/../includes/header.php';
include __DIR__ . '/../includes/navbar.php';
?>
<div class="container-narrow">
    <div class="card">
        <h1><i class="fas fa-cog"></i> Settings</h1>
        <?php if ($msg): ?><div class="alert alert-success"><?= $msg ?></div><?php endif; ?>
        <form method="POST">
            <input type="hidden" name="csrf" value="<?= csrf() ?>">
            <div class="form-group"><label>Nama Website</label><input type="text" name="site_name" value="<?= htmlspecialchars($get('site_name')) ?>"></div>
            <div class="form-group"><label>Deskripsi</label><input type="text" name="site_desc" value="<?= htmlspecialchars($get('site_desc')) ?>"></div>
            <button class="btn btn-primary"><i class="fas fa-save"></i> Simpan</button>
        </form>
    </div>
</div>
<?php include __DIR__ . '/../includes/footer.php'; ?>
PHPEOF

# ---------- API LIVE STATS ----------
cat > "$WEB_ROOT/api/stats.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/../includes/config.php';
header('Content-Type: application/json');
if (!isLoggedIn()) { echo json_encode(['error'=>'unauthorized']); exit; }
$stats = [
    'total_users' => (int)$pdo->query("SELECT COUNT(*) FROM users")->fetchColumn(),
    'online_now' => (int)$pdo->query("SELECT COUNT(*) FROM users WHERE last_login >= NOW() - INTERVAL 5 MINUTE")->fetchColumn(),
    'total_logs' => (int)$pdo->query("SELECT COUNT(*) FROM activity_log")->fetchColumn(),
    'banned' => (int)$pdo->query("SELECT COUNT(*) FROM users WHERE status='banned'")->fetchColumn(),
    'timestamp' => date('H:i:s'),
];
echo json_encode($stats);
PHPEOF

echo -e "${GREEN}  ✓ Semua halaman PHP dibuat${NC}"

# ============ STEP 6: CSS & JS ============
echo -e "${CYAN}[6/8] Membuat CSS & JS...${NC}"

cat > "$WEB_ROOT/assets/css/style.css" << 'CSSEOF'
:root {
    --bg: #f5f7fb; --bg-card: #fff; --bg-nav: #fff;
    --text: #2c3e50; --text-muted: #7f8c8d;
    --border: #e1e8ed; --primary: #4f46e5; --primary-hover: #4338ca;
    --success: #10b981; --danger: #ef4444; --warning: #f59e0b; --info: #3b82f6;
    --shadow: 0 2px 12px rgba(0,0,0,0.06);
}
[data-theme="dark"] {
    --bg: #0f172a; --bg-card: #1e293b; --bg-nav: #1e293b;
    --text: #e2e8f0; --text-muted: #94a3b8;
    --border: #334155; --primary: #6366f1; --primary-hover: #4f46e5;
    --shadow: 0 2px 12px rgba(0,0,0,0.3);
}
* { margin:0; padding:0; box-sizing:border-box; }
body { font-family:'Segoe UI',Tahoma,sans-serif; background:var(--bg); color:var(--text); line-height:1.6; transition: background .3s, color .3s; }
a { color: var(--primary); text-decoration: none; }
a:hover { opacity: .85; }

/* NAVBAR */
.navbar { display:flex; justify-content:space-between; align-items:center; padding:15px 30px; background:var(--bg-nav); border-bottom:1px solid var(--border); box-shadow:var(--shadow); position:sticky; top:0; z-index:100; flex-wrap:wrap; gap:15px; }
.nav-left .logo { font-size:1.3em; font-weight:700; color:var(--primary); display:flex; align-items:center; gap:8px; }
.nav-center { display:flex; gap:25px; }
.nav-center a { color:var(--text-muted); font-weight:500; display:flex; align-items:center; gap:6px; }
.nav-center a:hover { color:var(--primary); }
.nav-right { display:flex; align-items:center; gap:12px; }
.icon-btn { background:transparent; border:1px solid var(--border); color:var(--text); padding:8px 12px; border-radius:8px; cursor:pointer; transition:.2s; display:inline-flex; align-items:center; gap:6px; }
.icon-btn:hover { background:var(--primary); color:#fff; border-color:var(--primary); }
.user-menu { position:relative; }
.dropdown { display:none; position:absolute; right:0; top:100%; background:var(--bg-card); border:1px solid var(--border); border-radius:10px; min-width:180px; box-shadow:var(--shadow); padding:8px; z-index:200; }
.user-menu:hover .dropdown, .user-menu.open .dropdown { display:block; }
.dropdown a { display:flex; align-items:center; gap:10px; padding:10px 12px; color:var(--text); border-radius:6px; }
.dropdown a:hover { background:var(--bg); color:var(--primary); }

/* BUTTONS */
.btn { padding:10px 20px; border-radius:8px; border:none; cursor:pointer; font-weight:600; display:inline-flex; align-items:center; gap:8px; transition:.2s; text-decoration:none; font-size:.95em; }
.btn-primary { background:var(--primary); color:#fff; }
.btn-primary:hover { background:var(--primary-hover); transform:translateY(-2px); }
.btn-outline { background:transparent; border:2px solid var(--primary); color:var(--primary); }
.btn-outline:hover { background:var(--primary); color:#fff; }
.btn-block { width:100%; justify-content:center; }
.btn-lg { padding:14px 28px; font-size:1.05em; }
.btn-icon { background:transparent; border:1px solid var(--border); padding:6px 10px; border-radius:6px; cursor:pointer; color:var(--text); transition:.2s; }
.btn-icon:hover { color:#fff; }
.btn-warn:hover { background:var(--warning); border-color:var(--warning); }
.btn-ok:hover { background:var(--success); border-color:var(--success); }
.btn-info:hover { background:var(--info); border-color:var(--info); }
.btn-danger:hover { background:var(--danger); border-color:var(--danger); }

/* HERO */
.hero { min-height:65vh; display:flex; align-items:center; justify-content:center; text-align:center; padding:60px 30px; background:linear-gradient(135deg,#667eea,#764ba2); color:#fff; }
.hero h1 { font-size:2.8em; margin-bottom:20px; }
.hero p { font-size:1.15em; max-width:700px; margin:0 auto 30px; opacity:.95; }
.btn-group { display:flex; gap:15px; justify-content:center; flex-wrap:wrap; }

/* FEATURES */
.features { padding:60px 30px; max-width:1200px; margin:0 auto; }
.features h2 { text-align:center; font-size:2em; margin-bottom:40px; }
.feature-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(260px,1fr)); gap:25px; }
.feature-card { background:var(--bg-card); padding:30px; border-radius:14px; border:1px solid var(--border); text-align:center; transition:.3s; }
.feature-card:hover { transform:translateY(-5px); box-shadow:var(--shadow); border-color:var(--primary); }
.feature-card i { font-size:2.5em; color:var(--primary); margin-bottom:15px; }
.feature-card h3 { margin-bottom:10px; }
.feature-card p { color:var(--text-muted); font-size:.9em; }

/* AUTH */
.auth-wrap { min-height:70vh; display:flex; align-items:center; justify-content:center; padding:40px 20px; }
.auth-card { background:var(--bg-card); padding:40px; border-radius:16px; box-shadow:var(--shadow); max-width:420px; width:100%; border:1px solid var(--border); }
.auth-card h1 { font-size:1.6em; margin-bottom:8px; display:flex; align-items:center; gap:10px; color:var(--primary); }
.auth-card .subtitle { color:var(--text-muted); margin-bottom:25px; font-size:.9em; }
.auth-footer { text-align:center; margin-top:20px; color:var(--text-muted); font-size:.9em; }

/* FORM */
.form-group { margin-bottom:18px; }
.form-group label { display:block; margin-bottom:6px; font-weight:600; font-size:.9em; }
.form-group label i { color:var(--primary); margin-right:5px; }
.form-group input, .form-group select, .form-group textarea { width:100%; padding:12px 14px; border:1px solid var(--border); border-radius:8px; background:var(--bg); color:var(--text); font-size:.95em; transition:.2s; font-family:inherit; }
.form-group input:focus { outline:none; border-color:var(--primary); box-shadow:0 0 0 3px rgba(99,102,241,.15); }
.form-group input:disabled { opacity:.6; cursor:not-allowed; }

/* ALERTS */
.alert { padding:12px 16px; border-radius:8px; margin-bottom:15px; font-size:.9em; display:flex; align-items:center; gap:8px; }
.alert-error { background:rgba(239,68,68,.1); color:var(--danger); border-left:4px solid var(--danger); }
.alert-success { background:rgba(16,185,129,.1); color:var(--success); border-left:4px solid var(--success); }

/* CONTAINER */
.container { max-width:1200px; margin:0 auto; padding:30px; }
.container-narrow { max-width:600px; margin:0 auto; padding:30px; }
.page-header { margin-bottom:30px; }
.page-header h1 { font-size:1.8em; display:flex; align-items:center; gap:10px; }
.page-header h1 i { color:var(--primary); }
.page-header p { color:var(--text-muted); margin-top:5px; }

/* STATS */
.stats-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(220px,1fr)); gap:20px; margin-bottom:30px; }
.stat-card { background:var(--bg-card); padding:20px; border-radius:12px; box-shadow:var(--shadow); display:flex; align-items:center; gap:15px; border:1px solid var(--border); }
.stat-icon { width:55px; height:55px; border-radius:12px; display:flex; align-items:center; justify-content:center; color:#fff; font-size:1.5em; flex-shrink:0; }
.stat-info h3 { font-size:1.5em; margin:0; }
.stat-info p { color:var(--text-muted); font-size:.85em; margin:0; }

/* CARD */
.card { background:var(--bg-card); padding:25px; border-radius:14px; box-shadow:var(--shadow); margin-bottom:25px; border:1px solid var(--border); }
.card h1, .card h2 { margin-bottom:20px; display:flex; align-items:center; gap:10px; font-size:1.3em; }
.card h1 i, .card h2 i { color:var(--primary); }
.grid-2 { display:grid; grid-template-columns:repeat(auto-fit,minmax(400px,1fr)); gap:20px; }

/* TABLE */
.table { width:100%; border-collapse:collapse; }
.table th { text-align:left; padding:12px; background:var(--bg); border-bottom:2px solid var(--border); font-size:.85em; text-transform:uppercase; color:var(--text-muted); }
.table td { padding:12px; border-bottom:1px solid var(--border); }
.table tr:hover td { background:var(--bg); }
.table code { background:var(--bg); padding:2px 6px; border-radius:4px; font-size:.85em; }

/* BADGES */
.badge { padding:4px 10px; border-radius:20px; font-size:.75em; font-weight:600; text-transform:uppercase; }
.badge-admin { background:rgba(245,158,11,.15); color:var(--warning); }
.badge-user { background:rgba(59,130,246,.15); color:var(--info); }
.badge-active { background:rgba(16,185,129,.15); color:var(--success); }
.badge-banned { background:rgba(239,68,68,.15); color:var(--danger); }
.badge-info { background:rgba(99,102,241,.15); color:var(--primary); }

/* QUICK ACTIONS */
.quick-actions { display:grid; grid-template-columns:repeat(auto-fit,minmax(180px,1fr)); gap:15px; margin-top:20px; }
.action-btn { background:var(--bg-card); padding:25px; border-radius:12px; border:2px solid var(--border); text-align:center; transition:.3s; color:var(--text); display:flex; flex-direction:column; gap:10px; align-items:center; }
.action-btn:hover { border-color:var(--primary); transform:translateY(-3px); box-shadow:var(--shadow); }
.action-btn i { font-size:2em; color:var(--primary); }
.action-btn span { font-weight:600; font-size:.9em; }

/* ACTIONS CELL */
.actions form { display:inline-flex; gap:3px; }

/* FOOTER */
.footer { text-align:center; padding:25px; color:var(--text-muted); border-top:1px solid var(--border); margin-top:50px; font-size:.9em; }

/* RESPONSIVE */
@media (max-width:768px) {
    .navbar { padding:12px 15px; }
    .nav-center { order:3; width:100%; justify-content:center; }
    .hero h1 { font-size:1.9em; }
    .page-header h1 { font-size:1.4em; }
    .grid-2 { grid-template-columns:1fr; }
    .table { font-size:.85em; }
    .table th, .table td { padding:8px; }
}
CSSEOF

cat > "$WEB_ROOT/assets/js/main.js" << 'JSEOF'
// Theme Toggle
const themeToggle = document.getElementById('themeToggle');
const savedTheme = localStorage.getItem('theme') || 'dark';
document.documentElement.setAttribute('data-theme', savedTheme);
updateThemeIcon(savedTheme);

if (themeToggle) {
    themeToggle.addEventListener('click', () => {
        const current = document.documentElement.getAttribute('data-theme');
        const next = current === 'dark' ? 'light' : 'dark';
        document.documentElement.setAttribute('data-theme', next);
        localStorage.setItem('theme', next);
        updateThemeIcon(next);
    });
}
function updateThemeIcon(theme) {
    const icon = themeToggle?.querySelector('i');
    if (icon) icon.className = theme === 'dark' ? 'fas fa-sun' : 'fas fa-moon';
}

// Live Stats (auto-refresh)
if (document.querySelector('.stats-grid') && typeof fetch !== 'undefined') {
    setInterval(async () => {
        try {
            const res = await fetch('/api/stats.php');
            if (!res.ok) return;
            const data = await res.json();
            document.querySelectorAll('[data-stat]').forEach(el => {
                const key = el.getAttribute('data-stat');
                if (data[key] !== undefined) el.textContent = data[key];
            });
        } catch(e) {}
    }, 10000);
}

// User menu toggle for mobile
document.querySelectorAll('.user-btn').forEach(btn => {
    btn.addEventListener('click', e => {
        e.stopPropagation();
        btn.parentElement.classList.toggle('open');
    });
});
document.addEventListener('click', () => {
    document.querySelectorAll('.user-menu').forEach(m => m.classList.remove('open'));
});
JSEOF

echo -e "${GREEN}  ✓ CSS & JS dibuat${NC}"

# ============ STEP 7: NGINX CONFIG ============
echo -e "${CYAN}[7/8] Konfigurasi Nginx...${NC}"

cat > "$NGINX_CONF" << NGINXEOF
server {
    listen 80;
    listen [::]:80;
    server_name $SUBDOMAIN;
    root $WEB_ROOT;
    index index.php index.html;

    client_max_body_size 50M;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
    }

    location ~ /\.(?!well-known).* { deny all; }
    location ~* \.(env|log|sql)\$ { deny all; }

    access_log /var/log/nginx/$SUBDOMAIN.access.log;
    error_log /var/log/nginx/$SUBDOMAIN.error.log;
}
NGINXEOF

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/ 2>/dev/null
[[ -f /etc/nginx/sites-enabled/default ]] && rm -f /etc/nginx/sites-enabled/default

if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx
    echo -e "${GREEN}  ✓ Nginx OK${NC}"
else
    echo -e "${RED}  ✗ Nginx error!${NC}"; nginx -t; exit 1
fi

chown -R www-data:www-data "$WEB_ROOT"
chmod -R 755 "$WEB_ROOT"
chmod 640 "$WEB_ROOT/includes/config.php"
echo -e "${GREEN}  ✓ Permission OK${NC}"

# ============ STEP 8: SSL + FIREWALL ============
echo -e "${CYAN}[8/8] SSL & Firewall...${NC}"

SERVER_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || curl -4 -s --max-time 5 ipv4.icanhazip.com 2>/dev/null)
DOMAIN_IP=$(dig +short A "$SUBDOMAIN" @8.8.8.8 2>/dev/null | head -1)
[[ -z "$DOMAIN_IP" ]] && DOMAIN_IP=$(getent ahostsv4 "$SUBDOMAIN" 2>/dev/null | awk '{print $1}' | head -1)

SSL_STATUS="dilewati"
if [[ "$SERVER_IP" == "$DOMAIN_IP" ]]; then
    apt install certbot python3-certbot-nginx -y -qq 2>/dev/null
    if certbot --nginx -d "$SUBDOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect >/dev/null 2>&1; then
        echo -e "${GREEN}  ✓ SSL aktif!${NC}"
        SSL_STATUS="aktif ✅"
    else
        echo -e "${YELLOW}  ⚠️  SSL gagal, coba manual: certbot --nginx -d $SUBDOMAIN${NC}"
        SSL_STATUS="gagal ⚠️"
    fi
else
    echo -e "${YELLOW}  ⚠️  DNS belum siap (Server: $SERVER_IP, Domain: $DOMAIN_IP)${NC}"
    echo -e "${YELLOW}  → Pasang SSL nanti: certbot --nginx -d $SUBDOMAIN${NC}"
fi

if command -v ufw >/dev/null 2>&1; then
    ufw allow 80/tcp >/dev/null 2>&1
    ufw allow 443/tcp >/dev/null 2>&1
    ufw allow 22/tcp >/dev/null 2>&1
    echo -e "${GREEN}  ✓ Firewall OK${NC}"
fi

# ============ SELESAI ============
PROTO="https"; [[ "$SSL_STATUS" != *"aktif"* ]] && PROTO="http"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║       ✅ INSTALASI BERHASIL!                    ${NC}  ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}🔗 AKSES WEB:${NC}"
echo -e "  Home      : ${YELLOW}$PROTO://$SUBDOMAIN${NC}"
echo -e "  Login     : ${YELLOW}$PROTO://$SUBDOMAIN/login.php${NC}"
echo -e "  Register  : ${YELLOW}$PROTO://$SUBDOMAIN/register.php${NC}"
echo -e "  Admin     : ${YELLOW}$PROTO://$SUBDOMAIN/admin/${NC}"
echo ""
echo -e "${MAGENTA}🔑 KREDENSIAL ADMIN:${NC}"
echo -e "  Username  : ${YELLOW}$ADMIN_USER${NC}"
echo -e "  Password  : ${YELLOW}$ADMIN_PASS${NC}"
echo -e "  Email     : ${YELLOW}$ADMIN_EMAIL${NC}"
echo ""
echo -e "${CYAN}📁 INFO:${NC}"
echo -e "  Web Root  : $WEB_ROOT"
echo -e "  Database  : $DB_NAME (user: wpuser)"
echo -e "  DB Pass   : $DB_PASS"
echo -e "  SSL       : $SSL_STATUS"
echo ""
echo -e "${GREEN}✨ Selamat! Web panel kamu siap dipakai! 🎉${NC}"
