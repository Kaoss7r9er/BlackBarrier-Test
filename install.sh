#!/bin/bash
# ══════════════════════════════════════════════════════════════
#  BLACK BARRIER FIREWALL — OTOMATİK KURULUM BETİĞİ (v2)
#  Ubuntu Server 24.04 LTS
#  Kullanım: sudo bash install.sh
# ══════════════════════════════════════════════════════════════

# NOT: set -e kullanılmıyor. Kısmi kurulum kalıntılarını önlemek için
# her kritik adımda hata kontrolü ayrı ayrı yapılıyor.

# ── Renk Tanımları ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Yardımcı Fonksiyonlar ─────────────────────────────────────
bilgi()   { echo -e "${CYAN}[BİLGİ]${NC} $1"; }
basari()  { echo -e "${GREEN}[  ✓  ]${NC} $1"; }
uyari()   { echo -e "${YELLOW}[UYARI]${NC} $1"; }
hata()    { echo -e "${RED}[HATA!]${NC} $1"; }
adim()    { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════════════${NC}"; \
            echo -e "${BOLD}${CYAN}  $1${NC}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════${NC}"; }

# ── Sabitler ───────────────────────────────────────────────────
INSTALL_DIR="/opt/blackbarrier/Firewall"
REPO_URL="https://github.com/Kaoss7r9er/BlackBarrier-Test.git"
VENV_DIR="${INSTALL_DIR}/.venv"
SERVICE_NAME="blackbarrier"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
NETPLAN_FILE="/etc/netplan/50-blackbarrier.yaml"
SYSCTL_FILE="/etc/sysctl.d/99-blackbarrier.conf"

# ══════════════════════════════════════════════════════════════
#  BAŞLANGIÇ EKRANI
# ══════════════════════════════════════════════════════════════
clear
echo -e "${BOLD}${CYAN}"
echo "  ██████╗ ██╗      █████╗  ██████╗██╗  ██╗"
echo "  ██╔══██╗██║     ██╔══██╗██╔════╝██║ ██╔╝"
echo "  ██████╔╝██║     ███████║██║     █████╔╝ "
echo "  ██╔══██╗██║     ██╔══██║██║     ██╔═██╗ "
echo "  ██████╔╝███████╗██║  ██║╚██████╗██║  ██╗"
echo "  ╚═════╝ ╚══════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝"
echo -e "${NC}"
echo -e "${BOLD}  BLACK BARRIER FIREWALL — OTOMATİK KURULUM v2${NC}"
echo -e "${DIM}  Ubuntu Server 24.04 LTS | nftables | FastAPI${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"

# ══════════════════════════════════════════════════════════════
#  ÖN KONTROLLER
# ══════════════════════════════════════════════════════════════

# Root yetki kontrolü
if [ "$EUID" -ne 0 ]; then
    hata "Bu betik root (sudo) yetkileri ile çalıştırılmalıdır!"
    echo -e "  Kullanım: ${YELLOW}sudo bash install.sh${NC}"
    exit 1
fi

# İşletim sistemi kontrolü
if ! grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
    uyari "Bu betik Ubuntu Server için tasarlanmıştır. Devam etmek istiyor musunuz?"
    read -p "  (e/h): " devam
    [[ "$devam" != "e" && "$devam" != "E" ]] && exit 0
fi

# Önceki kurulum kontrolü — kök dizin veya alt dizin varsa temizle
# (Clone yarıda kalsa bile /opt/blackbarrier mevcut olabilir)
if [ -d "/opt/blackbarrier" ]; then
    echo ""
    uyari "Önceki kurulum tespit edildi: /opt/blackbarrier"
    read -p "  Eski kurulumu SİLİP sıfırdan mı kurmak istiyorsunuz? (e/h): " sifirla
    if [[ "$sifirla" == "e" || "$sifirla" == "E" ]]; then
        bilgi "Eski servis durduruluyor ve dosyalar temizleniyor..."
        systemctl stop ${SERVICE_NAME}.service 2>/dev/null || true
        systemctl disable ${SERVICE_NAME}.service 2>/dev/null || true
        rm -f "$SERVICE_FILE"
        rm -rf "/opt/blackbarrier"
        rm -f "$NETPLAN_FILE"
        rm -f "$SYSCTL_FILE"
        systemctl daemon-reload 2>/dev/null || true
        basari "Eski kurulum temizlendi."
    else
        hata "Kurulum kullanıcı tarafından iptal edildi."
        exit 0
    fi
fi

# ══════════════════════════════════════════════════════════════
#  ADIM 1/7 — SİSTEM PAKETLERİ
# ══════════════════════════════════════════════════════════════
adim "ADIM 1/7 — Sistem Paketleri Kuruluyor"

bilgi "Paket listesi güncelleniyor..."
if ! apt-get update -qq; then
    hata "Paket listesi güncellenemedi! İnternet bağlantısını kontrol edin."
    exit 1
fi

PACKAGES=("python3" "python3-pip" "python3-venv" "git" "nftables" "curl" "net-tools" "sqlite3")

for pkg in "${PACKAGES[@]}"; do
    if dpkg -s "$pkg" &>/dev/null; then
        echo -e "  ${DIM}● ${pkg} zaten kurulu${NC}"
    else
        echo -ne "  ${YELLOW}● ${pkg} kuruluyor...${NC}"
        apt-get install -y "$pkg" -qq > /dev/null 2>&1
        echo -e "\r  ${GREEN}● ${pkg} kuruldu${NC}          "
    fi
done

# Sürüm kontrolü
PYTHON_VER=$(python3 --version 2>&1)
NFT_VER=$(nft --version 2>&1)
basari "Paketler hazır — ${PYTHON_VER} | ${NFT_VER}"

# ══════════════════════════════════════════════════════════════
#  ADIM 2/7 — AĞ YAPILANDIRMASI (NETPLAN)
# ══════════════════════════════════════════════════════════════
adim "ADIM 2/7 — Ağ Arayüzü Yapılandırması (Netplan)"

# Mevcut arayüzleri göster
bilgi "Sistemde tespit edilen ağ arayüzleri:"
echo ""
ip -br link show | grep -v "^lo" | while read -r line; do
    echo -e "  ${CYAN}●${NC} $line"
done
echo ""

# WAN arayüzü
read -p "  Dış Ağ (WAN) arayüz adı (Örn: enp0s3): " WAN_IF
while [ -z "$WAN_IF" ]; do
    hata "WAN arayüzü boş olamaz!"
    read -p "  Dış Ağ (WAN) arayüz adı: " WAN_IF
done

# LAN arayüzü
read -p "  İç Ağ (LAN) arayüz adı (Örn: enp0s8): " LAN_IF
while [ -z "$LAN_IF" ]; do
    hata "LAN arayüzü boş olamaz!"
    read -p "  İç Ağ (LAN) arayüz adı: " LAN_IF
done

# WAN ayarları
echo ""
read -p "  ${WAN_IF} (WAN) için DHCP (otomatik IP) kullanılsın mı? (e/h): " WAN_DHCP

# LAN ayarları
read -p "  ${LAN_IF} (LAN) için statik IP girin (Örn: 192.168.1.1/24): " LAN_IP
while [ -z "$LAN_IP" ]; do
    hata "LAN IP adresi boş olamaz!"
    read -p "  LAN statik IP (Örn: 192.168.1.1/24): " LAN_IP
done

# Netplan dosyası oluştur
bilgi "Netplan yapılandırması yazılıyor..."

# WAN bloğu
if [[ "$WAN_DHCP" == "e" || "$WAN_DHCP" == "E" || -z "$WAN_DHCP" ]]; then
    WAN_BLOCK="    ${WAN_IF}:\n      dhcp4: true"
else
    read -p "  ${WAN_IF} için statik IP girin (Örn: 203.0.113.10/24): " WAN_IP
    read -p "  ${WAN_IF} için gateway girin (Örn: 203.0.113.1): " WAN_GW
    WAN_BLOCK="    ${WAN_IF}:\n      dhcp4: false\n      addresses:\n        - ${WAN_IP}"
    if [ -n "$WAN_GW" ]; then
        WAN_BLOCK="${WAN_BLOCK}\n      routes:\n        - to: default\n          via: ${WAN_GW}\n      nameservers:\n        addresses: [8.8.8.8, 1.1.1.1]"
    fi
fi

cat > "$NETPLAN_FILE" <<NETPLAN_EOF
# Black Barrier Firewall — Ağ Yapılandırması (Otomatik Oluşturuldu)
network:
  version: 2
  renderer: networkd
  ethernets:
$(echo -e "$WAN_BLOCK")
    ${LAN_IF}:
      dhcp4: false
      addresses:
        - ${LAN_IP}
NETPLAN_EOF

chmod 600 "$NETPLAN_FILE"
netplan apply 2>/dev/null || uyari "Netplan uygulanırken uyarı oluştu, devam ediliyor..."
basari "Ağ yapılandırması tamamlandı (${NETPLAN_FILE})"

# ══════════════════════════════════════════════════════════════
#  ADIM 3/7 — PROJE DOSYALARINI İNDİRME
# ══════════════════════════════════════════════════════════════
adim "ADIM 3/7 — Proje Dosyaları İndiriliyor"

# Kısmi clone kalıntılarını temizle (önceki adımda temizlenmemiş olabilir)
if [ -d "/opt/blackbarrier" ]; then
    uyari "Eski dizin kalıntısı temizleniyor..."
    rm -rf /opt/blackbarrier
fi

bilgi "GitHub deposundan klonlanıyor..."

# Güvenli klonlama: geçici dizine klonla, sonra doğru yere taşı
GECICI_KLON=$(mktemp -d)
if git clone "$REPO_URL" "$GECICI_KLON/repo" --quiet 2>&1; then
    basari "Depo başarıyla klonlandı."
else
    hata "GitHub deposundan klonlama başarısız!"
    hata "İnternet bağlantısını ve repo URL'sini kontrol edin: ${REPO_URL}"
    rm -rf "$GECICI_KLON"
    exit 1
fi

# Dizin yapısını tespit et ve doğru yere taşı
bilgi "Dizin yapısı kontrol ediliyor..."
if [ -f "$GECICI_KLON/repo/Firewall/db_yonetici.py" ]; then
    # Repo yapısı: repo/Firewall/... → /opt/blackbarrier/Firewall/...
    mkdir -p /opt/blackbarrier
    cp -r "$GECICI_KLON/repo/"* /opt/blackbarrier/
    basari "Proje dosyaları hazır (yapı: repo/Firewall/...)"
elif [ -f "$GECICI_KLON/repo/db_yonetici.py" ]; then
    # Repo kökünde doğrudan dosyalar var → /opt/blackbarrier/Firewall/...
    mkdir -p "$INSTALL_DIR"
    cp -r "$GECICI_KLON/repo/"* "$INSTALL_DIR/"
    basari "Proje dosyaları hazır (yapı: repo kök)"
else
    hata "Klonlanan depoda beklenen dosyalar bulunamadı!"
    hata "db_yonetici.py dosyası aranıyor ama bulunamıyor."
    ls -la "$GECICI_KLON/repo/" 2>/dev/null
    rm -rf "$GECICI_KLON"
    exit 1
fi

# Geçici dizini temizle
rm -rf "$GECICI_KLON"

# Son doğrulama
if [ ! -f "${INSTALL_DIR}/db_yonetici.py" ]; then
    hata "Kurulum dizininde dosyalar eksik: ${INSTALL_DIR}"
    exit 1
fi

basari "Kurulum dizini: ${INSTALL_DIR}"

# ══════════════════════════════════════════════════════════════
#  ADIM 4/7 — PYTHON SANAL ORTAM VE BAĞIMLILIKLAR
# ══════════════════════════════════════════════════════════════
adim "ADIM 4/7 — Python Sanal Ortam ve Bağımlılıklar"

bilgi "Python sanal ortamı oluşturuluyor..."
if ! python3 -m venv "$VENV_DIR"; then
    hata "Python sanal ortamı oluşturulamadı!"
    exit 1
fi

bilgi "pip güncelleniyor..."
"${VENV_DIR}/bin/pip" install --upgrade pip --quiet

bilgi "Bağımlılıklar kuruluyor..."
if ! "${VENV_DIR}/bin/pip" install \
    bcrypt \
    fastapi \
    "uvicorn[standard]" \
    PyJWT \
    python-multipart \
    --quiet; then
    hata "Python bağımlılıkları kurulamadı!"
    exit 1
fi

# Doğrulama
"${VENV_DIR}/bin/python" -c "
import bcrypt, fastapi, uvicorn, jwt
print('  Bağımlılıklar doğrulandı ✓')
print(f'  FastAPI={fastapi.__version__}')
"
basari "Python ortamı hazır (${VENV_DIR})"

# ══════════════════════════════════════════════════════════════
#  ADIM 5/7 — VERİTABANI KURULUMU VE ADMİN HESABI
# ══════════════════════════════════════════════════════════════
adim "ADIM 5/7 — Veritabanı Kurulumu ve Yönetici Hesabı"

# Veritabanı testlerini çalıştır
bilgi "Veritabanı testleri çalıştırılıyor..."
cd "$INSTALL_DIR"
"${VENV_DIR}/bin/python" test_veritabani.py || {
    uyari "Bazı testler başarısız oldu. Kurulum devam ediyor..."
}

# Admin bilgilerini al
echo ""
bilgi "Yönetim paneli için hesap bilgilerini belirleyin:"
read -p "  Kullanıcı adı: " ADMIN_USER
while [ -z "$ADMIN_USER" ]; do
    hata "Kullanıcı adı boş olamaz!"
    read -p "  Kullanıcı adı: " ADMIN_USER
done

read -s -p "  Şifre (gizli giriş): " ADMIN_PASS
echo ""
while [ -z "$ADMIN_PASS" ]; do
    hata "Şifre boş olamaz!"
    read -s -p "  Şifre (gizli giriş): " ADMIN_PASS
    echo ""
done

# kurulum.py ile veritabanı ve admin oluştur
bilgi "Veritabanı şeması ve admin hesabı oluşturuluyor..."
cd "${INSTALL_DIR}/FastAPI"
"${VENV_DIR}/bin/python" kurulum.py \
    --kullanici "$ADMIN_USER" \
    --sifre "$ADMIN_PASS" \
    --varsayilan-kurallar

# Doğrulama
DB_FILE="${INSTALL_DIR}/veritabani/blackbarrier.db"
if [ -f "$DB_FILE" ]; then
    KULLANICI_SAYISI=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM kullanicilar;" 2>/dev/null || echo "0")
    KURAL_SAYISI=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM guvenlik_kurallari;" 2>/dev/null || echo "0")
    basari "Veritabanı hazır — ${KULLANICI_SAYISI} kullanıcı, ${KURAL_SAYISI} kural"
else
    uyari "Veritabanı dosyası oluşturulamadı!"
fi

# ══════════════════════════════════════════════════════════════
#  ADIM 6/7 — IP YÖNLENDİRME VE NFTABLES
# ══════════════════════════════════════════════════════════════
adim "ADIM 6/7 — IP Yönlendirme ve nftables Yapılandırması"

# IP Forwarding
bilgi "IPv4 yönlendirme (forwarding) etkinleştiriliyor..."
sysctl -w net.ipv4.ip_forward=1 > /dev/null
echo "net.ipv4.ip_forward=1" > "$SYSCTL_FILE"
sysctl -p "$SYSCTL_FILE" > /dev/null 2>&1
basari "IP forwarding aktif"

# nftables servisini başlat
bilgi "nftables servisi başlatılıyor..."
systemctl enable nftables --quiet 2>/dev/null
systemctl start nftables 2>/dev/null || true

# nftables kurallarını oluştur
bilgi "nftables filtre ve NAT kuralları oluşturuluyor..."

# Mevcut blackbarrier tablosunu temizle (varsa)
nft delete table inet blackbarrier 2>/dev/null || true
nft delete table ip bb_nat 2>/dev/null || true

# Filtre tablosu
nft add table inet blackbarrier
nft add chain inet blackbarrier input '{ type filter hook input priority 0; policy accept; }'
nft add chain inet blackbarrier forward '{ type filter hook forward priority 0; policy accept; }'
nft add chain inet blackbarrier output '{ type filter hook output priority 0; policy accept; }'
basari "Filtre zincirleri oluşturuldu (input/forward/output)"

# NAT tablosu — LAN'dan WAN'a masquerade
nft add table ip bb_nat
nft add chain ip bb_nat postrouting '{ type nat hook postrouting priority 100; }'
nft add rule ip bb_nat postrouting oifname "$WAN_IF" masquerade
basari "NAT masquerade aktif (${LAN_IF} → ${WAN_IF})"

# Kuralları kalıcı yap
nft list ruleset > /etc/nftables.conf
basari "nftables kuralları /etc/nftables.conf dosyasına kaydedildi"

# ══════════════════════════════════════════════════════════════
#  ADIM 7/7 — SYSTEMD SERVİSİ
# ══════════════════════════════════════════════════════════════
adim "ADIM 7/7 — Systemd Servisi (Otomatik Başlatma)"

# JWT için güvenli anahtar üret
BB_SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")
bilgi "JWT gizli anahtarı otomatik üretildi."

# Servis dosyasını oluştur
cat > "$SERVICE_FILE" <<SERVICE_EOF
[Unit]
Description=Black Barrier Güvenlik Duvarı Yönetim Paneli
After=network-online.target nftables.service
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=${INSTALL_DIR}/modül
Environment="PATH=${VENV_DIR}/bin:/usr/bin"
Environment="BB_SECRET_KEY=${BB_SECRET}"
ExecStart=${VENV_DIR}/bin/uvicorn main:app --host 0.0.0.0 --port 8000 --workers 1
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# Servisi etkinleştir ve başlat
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}.service --quiet
systemctl start ${SERVICE_NAME}.service

# Servisin başladığını doğrula
sleep 2
if systemctl is-active --quiet ${SERVICE_NAME}.service; then
    basari "Servis başarıyla başlatıldı ve otomatik başlatmaya eklendi"
else
    uyari "Servis başlatılamadı. Logları kontrol edin:"
    echo -e "  ${YELLOW}sudo journalctl -u ${SERVICE_NAME} -n 20${NC}"
fi

# ══════════════════════════════════════════════════════════════
#  KURULUM TAMAMLANDI
# ══════════════════════════════════════════════════════════════

# LAN IP adresini al
LAN_IP_ADDR=$(ip -4 addr show "$LAN_IF" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
if [ -z "$LAN_IP_ADDR" ]; then
    LAN_IP_ADDR=$(echo "$LAN_IP" | cut -d'/' -f1)
fi

echo ""
echo -e "${GREEN}${BOLD}"
echo "  ══════════════════════════════════════════════════"
echo "       ✓  KURULUM BAŞARIYLA TAMAMLANDI  ✓"
echo "  ══════════════════════════════════════════════════"
echo -e "${NC}"
echo -e "  ${BOLD}Web Paneli:${NC}      ${CYAN}http://${LAN_IP_ADDR}:8000${NC}"
echo -e "  ${BOLD}Kullanıcı:${NC}       ${CYAN}${ADMIN_USER}${NC}"
echo -e "  ${BOLD}WAN Arayüzü:${NC}    ${WAN_IF}"
echo -e "  ${BOLD}LAN Arayüzü:${NC}    ${LAN_IF} (${LAN_IP})"
echo -e "  ${BOLD}Veritabanı:${NC}      ${DB_FILE}"
echo -e "  ${BOLD}Servis:${NC}          systemctl status ${SERVICE_NAME}"
echo -e "  ${BOLD}Loglar:${NC}          journalctl -u ${SERVICE_NAME} -f"
echo ""
echo -e "${DIM}  Faydalı komutlar:${NC}"
echo -e "  ${DIM}├─ sudo systemctl restart ${SERVICE_NAME}${NC}"
echo -e "  ${DIM}├─ sudo nft list ruleset${NC}"
echo -e "  ${DIM}└─ sudo journalctl -u ${SERVICE_NAME} -n 50${NC}"
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
