-- ============================================================
--  Black Barrier Güvenlik Duvarı — SQLite Veritabanı Şeması
--  Dosya: veritabani/sema.sql
-- ============================================================

PRAGMA journal_mode = WAL;   -- Eş zamanlı okuma/yazma için
PRAGMA foreign_keys = ON;    -- İlişkisel bütünlük kontrolü

-- ------------------------------------------------------------
-- 1. YETKİ GRUPLARI
--    Dinamik yetki grupları. Kullanıcılara atanır.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS yetki_gruplari (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    grup_adi      TEXT    NOT NULL UNIQUE,
    aciklama      TEXT,
    izinler       TEXT    NOT NULL DEFAULT '{}',  -- JSON: {"kurallar": true, "yonlendirme": true, ...}
    olusturma_t   TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- Varsayılan yetki grupları
INSERT OR IGNORE INTO yetki_gruplari (grup_adi, aciklama, izinler) VALUES
    ('super_admin', 'Tam sistem erişimi — tüm modüller ve kullanıcı yönetimi',
     '{"kurallar":true,"yonlendirme":true,"dhcp":true,"trafik":true,"ayarlar":true,"kullanici_yonetimi":true}'),
    ('yonetici', 'Ağ yönetimi — kullanıcı yönetimi hariç tüm modüller',
     '{"kurallar":true,"yonlendirme":true,"dhcp":true,"trafik":true,"ayarlar":true,"kullanici_yonetimi":false}'),
    ('izleyici', 'Salt okunur erişim — sadece izleme ve loglar',
     '{"kurallar":false,"yonlendirme":false,"dhcp":false,"trafik":true,"ayarlar":false,"kullanici_yonetimi":false}');

-- ------------------------------------------------------------
-- 2. KULLANICILAR
--    Yönetici hesapları. Şifreler bcrypt ile hashlenir,
--    düz metin ASLA saklanmaz.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS kullanicilar (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    kullanici_adi TEXT    NOT NULL UNIQUE,
    sifre_hash    TEXT    NOT NULL,           -- bcrypt hash
    ad_soyad      TEXT    DEFAULT '',         -- Görünen isim
    rol           TEXT    NOT NULL DEFAULT 'admin', -- Geriye uyumluluk
    grup_id       INTEGER DEFAULT 1,          -- Yetki grubu FK
    olusturma_t   TEXT    NOT NULL DEFAULT (datetime('now')),
    son_giris_t   TEXT,
    FOREIGN KEY (grup_id) REFERENCES yetki_gruplari(id) ON DELETE SET DEFAULT
);

-- ------------------------------------------------------------
-- 3. GÜVENLİK KURALLARI (nftables)
--    Sistem her yeniden başladığında bu tablo okunarak
--    kurallar nftables'a yeniden uygulanır.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS guvenlik_kurallari (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    kural_adi     TEXT    NOT NULL,
    yon           TEXT    NOT NULL CHECK(yon IN ('giris','cikis','ilet')), -- INPUT/OUTPUT/FORWARD
    protokol      TEXT    NOT NULL CHECK(protokol IN ('tcp','udp','icmp','herhangi')),
    kaynak_ip     TEXT,                       -- NULL = tüm kaynaklar
    hedef_ip      TEXT,                       -- NULL = tüm hedefler
    kaynak_port   TEXT,                       -- NULL = tüm portlar, örn: "80" veya "8080-8090"
    hedef_port    TEXT,
    eylem         TEXT    NOT NULL CHECK(eylem IN ('izin_ver','engelle','reddet')),
    oncelik       INTEGER NOT NULL DEFAULT 100, -- küçük = önce işle
    aktif         INTEGER NOT NULL DEFAULT 1,   -- 1=aktif, 0=devre dışı
    aciklama      TEXT,
    olusturma_t   TEXT    NOT NULL DEFAULT (datetime('now')),
    guncelleme_t  TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- Servis başlarken aktif kuralları sıralı çekmek için index
CREATE INDEX IF NOT EXISTS idx_kural_oncelik
    ON guvenlik_kurallari (aktif, oncelik);

-- ------------------------------------------------------------
-- 4. YÖNLENDİRME KURALLARI (NAT / Port Yönlendirme)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS yonlendirme_kurallari (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    kural_adi       TEXT    NOT NULL,
    tur             TEXT    NOT NULL CHECK(tur IN ('masquerade','dnat','snat')),
    protokol        TEXT    NOT NULL CHECK(protokol IN ('tcp','udp','herhangi')),
    dis_arayuz      TEXT,                     -- WAN arayüzü, örn: "eth0"
    ic_arayuz       TEXT,                     -- LAN arayüzü, örn: "eth1"
    dis_port        TEXT,                     -- Dışarıdan gelen port
    ic_ip           TEXT,                     -- Yönlendirilecek iç IP
    ic_port         TEXT,                     -- İç IP'deki hedef port
    aktif           INTEGER NOT NULL DEFAULT 1,
    aciklama        TEXT,
    olusturma_t     TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- ------------------------------------------------------------
-- 5. DHCP AYARLARI
--    Her ağ arayüzü için bir satır tutulur.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp_ayarlari (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    arayuz          TEXT    NOT NULL UNIQUE,  -- 'LAN', 'OPT_VLAN_1' vb.
    aktif           INTEGER NOT NULL DEFAULT 0,
    alt_ag          TEXT,                     -- örn: 192.168.1.0
    alt_ag_maskesi  TEXT,                     -- örn: 255.255.255.0
    havuz_baslangic TEXT,                     -- örn: 192.168.1.100
    havuz_bitis     TEXT,                     -- örn: 192.168.1.200
    ag_gecidi       TEXT,                     -- Gateway IP
    dns_sunuculari  TEXT,                     -- virgülle ayrılmış, örn: "8.8.8.8,1.1.1.1"
    kira_suresi     INTEGER NOT NULL DEFAULT 86400, -- saniye cinsinden (varsayılan: 1 gün)
    guncelleme_t    TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- Varsayılan arayüzleri ekle
INSERT OR IGNORE INTO dhcp_ayarlari (arayuz, aktif)
    VALUES ('LAN', 0), ('OPT_VLAN_1', 0);

-- ------------------------------------------------------------
-- 6. DHCP KİRALAMALARI (Aktif Leases)
--    Arayüzdeki "Aktif İstemci Kiralamaları" tablosunu doldurur.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dhcp_kiralamalari (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    arayuz          TEXT    NOT NULL,
    ip_adresi       TEXT    NOT NULL,
    mac_adresi      TEXT    NOT NULL,
    host_adi        TEXT,
    kira_baslangic  TEXT    NOT NULL DEFAULT (datetime('now')),
    kira_bitis      TEXT    NOT NULL,
    durum           TEXT    NOT NULL DEFAULT 'aktif'
                    CHECK(durum IN ('aktif','suresi_dolmus','rezerve'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_kira_mac_arayuz
    ON dhcp_kiralamalari (mac_adresi, arayuz);

-- ------------------------------------------------------------
-- 7. TRAFİK KAYITLARI (Firewall Logs)
--    Engellenen veya izin verilen bağlantıların logu.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS trafik_kayitlari (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    zaman           TEXT    NOT NULL DEFAULT (datetime('now')),
    kural_id        INTEGER REFERENCES guvenlik_kurallari(id) ON DELETE SET NULL,
    eylem           TEXT    NOT NULL CHECK(eylem IN ('izin_ver','engelle','reddet')),
    protokol        TEXT,
    kaynak_ip       TEXT,
    kaynak_port     INTEGER,
    hedef_ip        TEXT,
    hedef_port      INTEGER,
    arayuz          TEXT,
    paket_boyutu    INTEGER,
    aciklama        TEXT
);

-- Son kayıtları hızlı çekmek için index
CREATE INDEX IF NOT EXISTS idx_trafik_zaman
    ON trafik_kayitlari (zaman DESC);

-- ------------------------------------------------------------
-- 8. GİRİŞ KAYITLARI (Oturum Logları)
--    Kim, ne zaman, hangi cihazdan giriş yaptı.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS giris_kayitlari (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    kullanici_id    INTEGER REFERENCES kullanicilar(id) ON DELETE CASCADE,
    kullanici_adi   TEXT    NOT NULL,
    ip_adresi       TEXT,
    user_agent      TEXT,
    basarili        INTEGER NOT NULL DEFAULT 1,  -- 1=başarılı, 0=başarısız
    zaman           TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_giris_zaman
    ON giris_kayitlari (zaman DESC);

-- ------------------------------------------------------------
-- 9. SİSTEM TERCİHLERİ (Kullanıcı Bazlı Kalıcı Ayarlar)
--    Her kullanıcının kendi tercihleri ayrı tutulur.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sistem_tercihleri (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    kullanici_id    INTEGER NOT NULL REFERENCES kullanicilar(id) ON DELETE CASCADE,
    anahtar         TEXT    NOT NULL,
    deger           TEXT,
    guncelleme_t    TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE(kullanici_id, anahtar)
);
