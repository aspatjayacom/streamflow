#!/bin/bash

set -e

echo "================================"
echo "   StreamFlow Update Script    "
echo "================================"
echo

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Direktori saat ini
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Cek apakah ini direktori streamflow yang valid
if [ ! -f "app.js" ] || [ ! -f "package.json" ]; then
    echo -e "${RED}❌ Error: Script ini harus dijalankan dari direktori StreamFlow${NC}"
    echo "   Pastikan Anda berada di folder yang berisi app.js dan package.json"
    exit 1
fi

# Tampilkan versi saat ini
CURRENT_VERSION=$(node -p "require('./package.json').version" 2>/dev/null || echo "unknown")
echo -e "${BLUE}📦 Versi saat ini: v${CURRENT_VERSION}${NC}"
echo

# Konfirmasi update
read -p "Lanjutkan update? (y/n): " -n 1 -r
echo
[[ ! $REPLY =~ ^[Yy]$ ]] && echo "Update dibatalkan." && exit 1

echo
echo -e "${YELLOW}⚠️  File-file berikut TIDAK akan ditimpa (data aman):${NC}"
echo "   • db/streamflow.db (database)"
echo "   • .env (konfigurasi)"
echo "   • public/uploads/* (file upload)"
echo "   • logs/* (log files)"
echo

# Step 1: Stop aplikasi jika berjalan via PM2
echo -e "${BLUE}🔄 Step 1/6: Menghentikan aplikasi...${NC}"
if command -v pm2 &> /dev/null; then
    pm2 stop streamflow 2>/dev/null || echo "   (Aplikasi tidak berjalan via PM2)"
else
    echo "   (PM2 tidak terinstall, skip...)"
fi

# Step 2: Backup file penting
echo -e "${BLUE}💾 Step 2/6: Backup data penting...${NC}"
BACKUP_DIR="backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup database
if [ -f "db/streamflow.db" ]; then
    cp db/streamflow.db "$BACKUP_DIR/"
    echo "   ✓ Database di-backup"
fi

# Backup .env
if [ -f ".env" ]; then
    cp .env "$BACKUP_DIR/"
    echo "   ✓ .env di-backup"
fi

# Backup uploads (hanya jika tidak terlalu besar)
if [ -d "public/uploads" ]; then
    UPLOADS_SIZE=$(du -sm public/uploads 2>/dev/null | cut -f1)
    if [ "$UPLOADS_SIZE" -lt 500 ]; then
        cp -r public/uploads "$BACKUP_DIR/" 2>/dev/null || true
        echo "   ✓ Uploads di-backup (${UPLOADS_SIZE}MB)"
    else
        echo "   ⚠ Uploads terlalu besar (${UPLOADS_SIZE}MB), skip backup"
    fi
fi

echo "   📁 Backup tersimpan di: $BACKUP_DIR"

# Step 3: Simpan daftar file yang harus dipertahankan
echo -e "${BLUE}📋 Step 3/6: Menyimpan data lokal...${NC}"

# Pindahkan file penting ke temporary
TEMP_DIR=".update_temp"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# Pindahkan database
if [ -d "db" ]; then
    mv db "$TEMP_DIR/"
    echo "   ✓ Database dipindahkan"
fi

# Pindahkan .env
if [ -f ".env" ]; then
    mv .env "$TEMP_DIR/"
    echo "   ✓ .env dipindahkan"
fi

# Pindahkan uploads
if [ -d "public/uploads" ]; then
    mv public/uploads "$TEMP_DIR/"
    echo "   ✓ Uploads dipindahkan"
fi

# Pindahkan logs
if [ -d "logs" ]; then
    mv logs "$TEMP_DIR/"
    echo "   ✓ Logs dipindahkan"
fi

# Step 4: Pull update dari GitHub
echo -e "${BLUE}📥 Step 4/6: Mengunduh update dari GitHub...${NC}"

# Cek apakah ini git repo
if [ -d ".git" ]; then
    # Reset perubahan lokal pada file source (bukan data)
    git fetch origin
    git reset --hard origin/main 2>/dev/null || git reset --hard origin/master
    echo "   ✓ Source code diperbarui"
else
    echo -e "${RED}   ❌ Bukan git repository. Tidak bisa update otomatis.${NC}"
    echo "   Silakan clone ulang dari GitHub atau download manual."
    
    # Restore file yang dipindahkan
    [ -d "$TEMP_DIR/db" ] && mv "$TEMP_DIR/db" ./
    [ -f "$TEMP_DIR/.env" ] && mv "$TEMP_DIR/.env" ./
    [ -d "$TEMP_DIR/uploads" ] && mkdir -p public && mv "$TEMP_DIR/uploads" public/
    [ -d "$TEMP_DIR/logs" ] && mv "$TEMP_DIR/logs" ./
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Step 5: Restore data yang dipindahkan
echo -e "${BLUE}🔄 Step 5/6: Mengembalikan data lokal...${NC}"

# Restore database
if [ -d "$TEMP_DIR/db" ]; then
    rm -rf db  # Hapus db kosong dari git
    mv "$TEMP_DIR/db" ./
    echo "   ✓ Database dikembalikan"
fi

# Restore .env
if [ -f "$TEMP_DIR/.env" ]; then
    mv "$TEMP_DIR/.env" ./
    echo "   ✓ .env dikembalikan"
fi

# Restore uploads
if [ -d "$TEMP_DIR/uploads" ]; then
    mkdir -p public
    rm -rf public/uploads  # Hapus folder kosong dari git
    mv "$TEMP_DIR/uploads" public/
    echo "   ✓ Uploads dikembalikan"
fi

# Restore logs
if [ -d "$TEMP_DIR/logs" ]; then
    rm -rf logs
    mv "$TEMP_DIR/logs" ./
    echo "   ✓ Logs dikembalikan"
fi

# Cleanup temp
rm -rf "$TEMP_DIR"

# Step 6: Update dependencies
echo -e "${BLUE}📦 Step 6/6: Menginstall dependencies baru...${NC}"
npm install --production
echo "   ✓ Dependencies diperbarui"

# Tampilkan versi baru
NEW_VERSION=$(node -p "require('./package.json').version" 2>/dev/null || echo "unknown")

# Restart aplikasi
echo
echo -e "${BLUE}▶️  Menjalankan ulang aplikasi...${NC}"
if command -v pm2 &> /dev/null; then
    pm2 restart streamflow 2>/dev/null || pm2 start app.js --name streamflow
    pm2 save
    echo "   ✓ Aplikasi berjalan via PM2"
else
    echo "   ⚠ PM2 tidak terinstall. Jalankan manual: node app.js"
fi

echo
echo "================================"
echo -e "${GREEN}✅ UPDATE SELESAI!${NC}"
echo "================================"
echo
echo -e "📦 Versi sebelumnya: ${YELLOW}v${CURRENT_VERSION}${NC}"
echo -e "📦 Versi sekarang:   ${GREEN}v${NEW_VERSION}${NC}"
echo
echo "📁 Backup tersedia di: $SCRIPT_DIR/$BACKUP_DIR"
echo "   (Hapus manual jika tidak diperlukan)"
echo
echo -e "${GREEN}🌐 StreamFlow siap digunakan!${NC}"
echo "================================"
