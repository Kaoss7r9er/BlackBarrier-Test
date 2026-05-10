"""
Black Barrier — Veritabanı Yöneticisi (db_yonetici.py)
========================================================
Bu modül tüm SQLite işlemlerini kapsar.
FastAPI arka ucundan import edilerek kullanılır.

Bağımlılıklar:
    pip install bcrypt==4.0.1
"""

import sqlite3
from datetime import datetime, timedelta
from pathlib import Path
import bcrypt

# ── Yapılandırma ──────────────────────────────────────────────
DB_YOLU = Path(__file__).parent / "veritabani" / "blackbarrier.db"
SEMA_YOLU = Path(__file__).parent / "veritabani" / "sema.sql"



# ══════════════════════════════════════════════════════════════
#  BAĞLANTI YÖNETİMİ
# ══════════════════════════════════════════════════════════════

def baglanti_al() -> sqlite3.Connection:
    """Thread-safe SQLite bağlantısı döndürür."""
    baglanti = sqlite3.connect(
        DB_YOLU,
        check_same_thread=False,
        detect_types=sqlite3.PARSE_DECLTYPES
    )
    baglanti.row_factory = sqlite3.Row   # Sonuçları dict gibi kullanmak için
    baglanti.execute("PRAGMA journal_mode = WAL")
    baglanti.execute("PRAGMA foreign_keys = ON")
    return baglanti


def veritabanini_baslat():
    """
    Uygulama ilk kez çalıştığında şemayı oluşturur.
    Uvicorn başlarken çağrılmalıdır (startup event).
    """
    DB_YOLU.parent.mkdir(parents=True, exist_ok=True)
    sema = SEMA_YOLU.read_text(encoding="utf-8")

    with baglanti_al() as baglanti:
        baglanti.executescript(sema)
        baglanti.commit()

    # Mevcut kullanıcılara ad_soyad ve grup_id sütunları ekle (migration)
    _migrasyon_uygula()

    print(f"[DB] Veritabanı hazır: {DB_YOLU}")


def _migrasyon_uygula():
    """Mevcut veritabanına yeni sütunları ekler (geriye uyumluluk)."""
    with baglanti_al() as bg:
        # kullanicilar tablosuna ad_soyad sütunu ekle (yoksa)
        try:
            bg.execute("ALTER TABLE kullanicilar ADD COLUMN ad_soyad TEXT DEFAULT ''")
            bg.commit()
        except sqlite3.OperationalError:
            pass  # Sütun zaten var

        # kullanicilar tablosuna grup_id sütunu ekle (yoksa)
        try:
            bg.execute("ALTER TABLE kullanicilar ADD COLUMN grup_id INTEGER DEFAULT 1")
            bg.commit()
        except sqlite3.OperationalError:
            pass  # Sütun zaten var


# ══════════════════════════════════════════════════════════════
#  YETKİ GRUPLARI
# ══════════════════════════════════════════════════════════════

def yetki_gruplari_getir() -> list[dict]:
    """Tüm yetki gruplarını döndürür."""
    with baglanti_al() as bg:
        return [dict(s) for s in bg.execute(
            "SELECT * FROM yetki_gruplari ORDER BY id ASC"
        ).fetchall()]


def yetki_grubu_ekle(grup_adi: str, aciklama: str = "", izinler: str = "{}") -> int:
    """Yeni yetki grubu oluşturur. Döndürür: yeni grubun id'si."""
    with baglanti_al() as bg:
        imle = bg.execute(
            """INSERT INTO yetki_gruplari (grup_adi, aciklama, izinler)
               VALUES (?, ?, ?)""",
            (grup_adi, aciklama, izinler)
        )
        bg.commit()
        return imle.lastrowid


def yetki_grubu_sil(grup_id: int) -> bool:
    """Yetki grubunu siler. Varsayılan gruplar (id<=3) silinemez."""
    if grup_id <= 3:
        return False  # Varsayılan gruplar korumalı
    with baglanti_al() as bg:
        etkilenen = bg.execute(
            "DELETE FROM yetki_gruplari WHERE id = ?", (grup_id,)
        ).rowcount
        bg.commit()
    return etkilenen > 0


# ══════════════════════════════════════════════════════════════
#  KULLANICI İŞLEMLERİ
# ══════════════════════════════════════════════════════════════

def kullanici_olustur(kullanici_adi: str, sifre: str, rol: str = "admin",
                      ad_soyad: str = "", grup_id: int = 1) -> int:
    """
    Yeni yönetici oluşturur. Şifreyi bcrypt ile hashler.
    Döndürür: yeni kullanıcının id'si
    """
    hash_deger = bcrypt.hashpw(sifre.encode(), bcrypt.gensalt()).decode()
    with baglanti_al() as bg:
        imle = bg.execute(
            """INSERT INTO kullanicilar (kullanici_adi, sifre_hash, rol, ad_soyad, grup_id)
               VALUES (?, ?, ?, ?, ?)""",
            (kullanici_adi, hash_deger, rol, ad_soyad, grup_id)
        )
        bg.commit()
        return imle.lastrowid


def kullanici_dogrula(kullanici_adi: str, sifre: str) -> dict | None:
    """
    Kullanıcı adı + şifre doğrulaması.
    Başarılıysa kullanıcı dict'ini (grup bilgisiyle), değilse None döndürür.
    """
    with baglanti_al() as bg:
        satir = bg.execute(
            """SELECT k.*, yg.grup_adi, yg.izinler as grup_izinleri
               FROM kullanicilar k
               LEFT JOIN yetki_gruplari yg ON k.grup_id = yg.id
               WHERE k.kullanici_adi = ?""",
            (kullanici_adi,)
        ).fetchone()

    if satir and bcrypt.checkpw(sifre.encode(), satir["sifre_hash"].encode()):
        # Son giriş zamanını güncelle
        with baglanti_al() as bg:
            bg.execute(
                "UPDATE kullanicilar SET son_giris_t = ? WHERE id = ?",
                (datetime.now().isoformat(), satir["id"])
            )
            bg.commit()
        return dict(satir)
    return None


def kullanici_var_mi() -> bool:
    """Veritabanında en az bir kullanıcı var mı kontrol eder."""
    with baglanti_al() as bg:
        sayi = bg.execute("SELECT COUNT(*) FROM kullanicilar").fetchone()[0]
    return sayi > 0


def kullanicilari_getir() -> list[dict]:
    """Tüm kullanıcıları grup bilgileriyle listeler."""
    with baglanti_al() as bg:
        return [dict(s) for s in bg.execute(
            """SELECT k.id, k.kullanici_adi, k.ad_soyad, k.rol, k.grup_id,
                      k.olusturma_t, k.son_giris_t,
                      yg.grup_adi, yg.izinler as grup_izinleri
               FROM kullanicilar k
               LEFT JOIN yetki_gruplari yg ON k.grup_id = yg.id
               ORDER BY k.id ASC"""
        ).fetchall()]


def kullanici_bilgisi_getir(kullanici_adi: str) -> dict | None:
    """Tek bir kullanıcının detaylı bilgilerini döndürür."""
    with baglanti_al() as bg:
        satir = bg.execute(
            """SELECT k.id, k.kullanici_adi, k.ad_soyad, k.rol, k.grup_id,
                      k.olusturma_t, k.son_giris_t,
                      yg.grup_adi, yg.izinler as grup_izinleri
               FROM kullanicilar k
               LEFT JOIN yetki_gruplari yg ON k.grup_id = yg.id
               WHERE k.kullanici_adi = ?""",
            (kullanici_adi,)
        ).fetchone()
    return dict(satir) if satir else None


def kullanici_sil(kullanici_id: int) -> bool:
    """Kullanıcıyı siler. Başarılıysa True döner."""
    with baglanti_al() as bg:
        etkilenen = bg.execute(
            "DELETE FROM kullanicilar WHERE id = ?", (kullanici_id,)
        ).rowcount
        bg.commit()
    return etkilenen > 0


# ══════════════════════════════════════════════════════════════
#  GİRİŞ KAYITLARI
# ══════════════════════════════════════════════════════════════

def giris_kaydi_ekle(kullanici_id: int | None, kullanici_adi: str,
                     ip_adresi: str = "", user_agent: str = "",
                     basarili: bool = True) -> int:
    """Giriş denemesini loglar."""
    with baglanti_al() as bg:
        imle = bg.execute(
            """INSERT INTO giris_kayitlari
               (kullanici_id, kullanici_adi, ip_adresi, user_agent, basarili)
               VALUES (?, ?, ?, ?, ?)""",
            (kullanici_id, kullanici_adi, ip_adresi, user_agent,
             1 if basarili else 0)
        )
        bg.commit()
        return imle.lastrowid


def giris_kayitlari_getir(kullanici_id: int | None = None,
                          limit: int = 50) -> list[dict]:
    """Giriş kayıtlarını döndürür. kullanici_id verilirse filtreler."""
    sorgu = "SELECT * FROM giris_kayitlari"
    parametreler = []
    if kullanici_id:
        sorgu += " WHERE kullanici_id = ?"
        parametreler.append(kullanici_id)
    sorgu += " ORDER BY zaman DESC LIMIT ?"
    parametreler.append(limit)

    with baglanti_al() as bg:
        return [dict(s) for s in bg.execute(sorgu, parametreler).fetchall()]


# ══════════════════════════════════════════════════════════════
#  SİSTEM TERCİHLERİ
# ══════════════════════════════════════════════════════════════

def sistem_tercihi_kaydet(kullanici_id: int, anahtar: str, deger: str) -> bool:
    """Kullanıcı tercihini kaydeder (upsert)."""
    with baglanti_al() as bg:
        bg.execute(
            """INSERT INTO sistem_tercihleri (kullanici_id, anahtar, deger, guncelleme_t)
               VALUES (?, ?, ?, ?)
               ON CONFLICT(kullanici_id, anahtar) DO UPDATE SET
                   deger=excluded.deger, guncelleme_t=excluded.guncelleme_t""",
            (kullanici_id, anahtar, deger, datetime.now().isoformat())
        )
        bg.commit()
    return True


def sistem_tercihleri_getir(kullanici_id: int) -> dict:
    """Kullanıcının tüm tercihlerini {anahtar: deger} olarak döndürür."""
    with baglanti_al() as bg:
        satirlar = bg.execute(
            "SELECT anahtar, deger FROM sistem_tercihleri WHERE kullanici_id = ?",
            (kullanici_id,)
        ).fetchall()
    return {s["anahtar"]: s["deger"] for s in satirlar}


# ══════════════════════════════════════════════════════════════
#  GÜVENLİK KURALLARI
# ══════════════════════════════════════════════════════════════

def kurallari_getir(sadece_aktif: bool = True) -> list[dict]:
  """
  Tüm güvenlik kurallarını öncelik sırasıyla döndürür.
  Servis başlangıcında nftables'a uygulamak için kullanılır.
  """
  sorgu = "SELECT * FROM guvenlik_kurallari"
  if sadece_aktif:
      sorgu += " WHERE aktif = 1"
  sorgu += " ORDER BY oncelik ASC, id ASC"

  with baglanti_al() as bg:
      return [dict(s) for s in bg.execute(sorgu).fetchall()]


def kural_ekle(veri: dict) -> int:
    """
    Yeni güvenlik kuralı ekler.
    veri dict'i şu anahtarları içermelidir:
        kural_adi, yon, protokol, eylem
    Opsiyonel: kaynak_ip, hedef_ip, kaynak_port, hedef_port, oncelik, aciklama
    """
    # Opsiyonel alanlar için varsayılan değerler
    varsayilan = {
        "kaynak_ip": None, "hedef_ip": None,
        "kaynak_port": None, "hedef_port": None,
        "oncelik": 100, "aciklama": None
    }
    tam_veri = {**varsayilan, **veri}

    with baglanti_al() as bg:
        imle = bg.execute(
            """INSERT INTO guvenlik_kurallari
               (kural_adi, yon, protokol, kaynak_ip, hedef_ip,
                kaynak_port, hedef_port, eylem, oncelik, aciklama)
               VALUES (:kural_adi, :yon, :protokol, :kaynak_ip, :hedef_ip,
                       :kaynak_port, :hedef_port, :eylem,
                       :oncelik, :aciklama)""",
            tam_veri
        )
        bg.commit()
        return imle.lastrowid


def kural_sil(kural_id: int) -> bool:
    """Kuralı siler. Başarılıysa True döner."""
    with baglanti_al() as bg:
        etkilenen = bg.execute(
            "DELETE FROM guvenlik_kurallari WHERE id = ?", (kural_id,)
        ).rowcount
        bg.commit()
    return etkilenen > 0


def kural_durum_degistir(kural_id: int, aktif: bool) -> bool:
    """Kuralı aktifleştirir veya devre dışı bırakır."""
    with baglanti_al() as bg:
        etkilenen = bg.execute(
            """UPDATE guvenlik_kurallari
               SET aktif = ?, guncelleme_t = ?
               WHERE id = ?""",
            (1 if aktif else 0, datetime.now().isoformat(), kural_id)
        ).rowcount
        bg.commit()
    return etkilenen > 0


# ══════════════════════════════════════════════════════════════
#  YÖNLENDİRME KURALLARI
# ══════════════════════════════════════════════════════════════

def yonlendirme_kurallari_getir(sadece_aktif: bool = True) -> list[dict]:
    sorgu = "SELECT * FROM yonlendirme_kurallari"
    if sadece_aktif:
        sorgu += " WHERE aktif = 1"
    with baglanti_al() as bg:
        return [dict(s) for s in bg.execute(sorgu).fetchall()]


def yonlendirme_kurali_ekle(veri: dict) -> int:
    """
    Yeni NAT/yönlendirme kuralı ekler.
    veri: kural_adi, tur, protokol, [dis_arayuz, ic_arayuz,
          dis_port, ic_ip, ic_port, aciklama]
    """
    with baglanti_al() as bg:
        imle = bg.execute(
            """INSERT INTO yonlendirme_kurallari
               (kural_adi, tur, protokol, dis_arayuz, ic_arayuz,
                dis_port, ic_ip, ic_port, aciklama)
               VALUES (:kural_adi, :tur, :protokol, :dis_arayuz, :ic_arayuz,
                       :dis_port, :ic_ip, :ic_port, :aciklama)""",
            veri
        )
        bg.commit()
        return imle.lastrowid


def yonlendirme_kurali_sil(kural_id: int) -> bool:
    with baglanti_al() as bg:
        etkilenen = bg.execute(
            "DELETE FROM yonlendirme_kurallari WHERE id = ?", (kural_id,)
        ).rowcount
        bg.commit()
    return etkilenen > 0


# ══════════════════════════════════════════════════════════════
#  DHCP İŞLEMLERİ
# ══════════════════════════════════════════════════════════════

def dhcp_ayarlarini_getir(arayuz: str) -> dict | None:
    """Belirtilen arayüzün DHCP ayarlarını döndürür."""
    with baglanti_al() as bg:
        satir = bg.execute(
            "SELECT * FROM dhcp_ayarlari WHERE arayuz = ?", (arayuz,)
        ).fetchone()
    return dict(satir) if satir else None


def dhcp_ayarlarini_kaydet(arayuz: str, veri: dict) -> bool:
    """
    DHCP ayarlarını günceller (upsert — yoksa ekler).
    veri: aktif, alt_ag, alt_ag_maskesi, havuz_baslangic,
          havuz_bitis, ag_gecidi, dns_sunuculari, kira_suresi
    """
    tam_veri = {**veri, "arayuz": arayuz, "guncelleme_t": datetime.now().isoformat()}
    with baglanti_al() as bg:
        bg.execute(
            """INSERT INTO dhcp_ayarlari
                   (arayuz, aktif, alt_ag, alt_ag_maskesi,
                    havuz_baslangic, havuz_bitis, ag_gecidi,
                    dns_sunuculari, kira_suresi, guncelleme_t)
               VALUES (:arayuz, :aktif, :alt_ag, :alt_ag_maskesi,
                       :havuz_baslangic, :havuz_bitis, :ag_gecidi,
                       :dns_sunuculari, :kira_suresi, :guncelleme_t)
               ON CONFLICT(arayuz) DO UPDATE SET
                   aktif=excluded.aktif,
                   alt_ag=excluded.alt_ag,
                   alt_ag_maskesi=excluded.alt_ag_maskesi,
                   havuz_baslangic=excluded.havuz_baslangic,
                   havuz_bitis=excluded.havuz_bitis,
                   ag_gecidi=excluded.ag_gecidi,
                   dns_sunuculari=excluded.dns_sunuculari,
                   kira_suresi=excluded.kira_suresi,
                   guncelleme_t=excluded.guncelleme_t""",
            tam_veri
        )
        bg.commit()
    return True


def dhcp_kiralamalari_getir(arayuz: str | None = None) -> list[dict]:
    """Aktif DHCP kiralamalarını döndürür."""
    sorgu = "SELECT * FROM dhcp_kiralamalari WHERE durum = 'aktif'"
    parametreler = []
    if arayuz:
        sorgu += " AND arayuz = ?"
        parametreler.append(arayuz)
    sorgu += " ORDER BY kira_baslangic DESC"

    with baglanti_al() as bg:
        return [dict(s) for s in bg.execute(sorgu, parametreler).fetchall()]


def dhcp_kiralamasi_ekle_veya_guncelle(veri: dict) -> int:
    """
    MAC adresi zaten varsa günceller, yoksa yeni kiralama ekler.
    veri: arayuz, ip_adresi, mac_adresi, host_adi, kira_bitis
    """
    with baglanti_al() as bg:
        imle = bg.execute(
            """INSERT INTO dhcp_kiralamalari
               (arayuz, ip_adresi, mac_adresi, host_adi, kira_bitis)
               VALUES (:arayuz, :ip_adresi, :mac_adresi, :host_adi, :kira_bitis)
               ON CONFLICT(mac_adresi, arayuz) DO UPDATE SET
                   ip_adresi   = excluded.ip_adresi,
                   host_adi    = excluded.host_adi,
                   kira_bitis  = excluded.kira_bitis,
                   kira_baslangic = datetime('now'),
                   durum       = 'aktif'""",
            veri
        )
        bg.commit()
        return imle.lastrowid


def suresi_dolan_kiralamalari_temizle() -> int:
    """Süresi dolmuş kiralamaları 'suresi_dolmus' olarak işaretler."""
    with baglanti_al() as bg:
        etkilenen = bg.execute(
            """UPDATE dhcp_kiralamalari
               SET durum = 'suresi_dolmus'
               WHERE kira_bitis < datetime('now') AND durum = 'aktif'"""
        ).rowcount
        bg.commit()
    return etkilenen


# ══════════════════════════════════════════════════════════════
#  TRAFİK KAYITLARI
# ══════════════════════════════════════════════════════════════

def trafik_kaydi_ekle(veri: dict) -> int:
    """
    Yeni trafik log kaydı ekler.
    veri: eylem, protokol, kaynak_ip, kaynak_port,
          hedef_ip, hedef_port, [kural_id, arayuz, paket_boyutu, aciklama]
    """
    # Opsiyonel alanlar için varsayılan değerler
    varsayilan = {
        "kural_id": None, "arayuz": None,
        "paket_boyutu": None, "aciklama": None
    }
    tam_veri = {**varsayilan, **veri}

    with baglanti_al() as bg:
        imle = bg.execute(
            """INSERT INTO trafik_kayitlari
               (kural_id, eylem, protokol, kaynak_ip, kaynak_port,
                hedef_ip, hedef_port, arayuz, paket_boyutu, aciklama)
               VALUES (:kural_id, :eylem, :protokol, :kaynak_ip, :kaynak_port,
                       :hedef_ip, :hedef_port, :arayuz, :paket_boyutu, :aciklama)""",
            tam_veri
        )
        bg.commit()
        return imle.lastrowid


def trafik_kayitlarini_getir(
    limit: int = 100,
    eylem_filtresi: str | None = None,
    kaynak_ip_filtresi: str | None = None
) -> list[dict]:
    """
    Trafik kayıtlarını en yeniden eskiye sıralar.
    Filtreler opsiyoneldir.
    """
    kosullar = []
    parametreler = []

    if eylem_filtresi:
        kosullar.append("eylem = ?")
        parametreler.append(eylem_filtresi)
    if kaynak_ip_filtresi:
        kosullar.append("kaynak_ip LIKE ?")
        parametreler.append(f"%{kaynak_ip_filtresi}%")

    sorgu = "SELECT * FROM trafik_kayitlari"
    if kosullar:
        sorgu += " WHERE " + " AND ".join(kosullar)
    sorgu += " ORDER BY zaman DESC LIMIT ?"
    parametreler.append(limit)

    with baglanti_al() as bg:
        return [dict(s) for s in bg.execute(sorgu, parametreler).fetchall()]


def trafik_istatistiklerini_getir() -> dict:
    """Kontrol paneli için özet istatistikler döndürür."""
    with baglanti_al() as bg:
        toplam = bg.execute("SELECT COUNT(*) FROM trafik_kayitlari").fetchone()[0]
        engellenen = bg.execute(
            "SELECT COUNT(*) FROM trafik_kayitlari WHERE eylem = 'engelle'"
        ).fetchone()[0]
        son_1_saat = bg.execute(
            """SELECT COUNT(*) FROM trafik_kayitlari
               WHERE zaman >= datetime('now', '-1 hour')"""
        ).fetchone()[0]

    return {
        "toplam_kayit": toplam,
        "engellenen_baglanti": engellenen,
        "son_1_saat_aktivite": son_1_saat,
        "aktif_kural_sayisi": len(kurallari_getir(sadece_aktif=True))
    }
