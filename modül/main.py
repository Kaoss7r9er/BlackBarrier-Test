"""
Black Barrier — FastAPI Ana Uygulama (main.py)
=====================================================
Bu dosya db_yonetici.py'nin FastAPI ile nasıl kullanıldığını gösterir.
Aynı zamanda statik HTML dosyalarını sunar.

Çalıştırmak için:
    uvicorn main:app --host 0.0.0.0 --port 8000 --reload
"""

import sys
import os
import secrets
from pathlib import Path
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Depends, status, Request
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime, timedelta, timezone
import jwt                  # pip install PyJWT

# ── Proje kök dizinini sys.path'e ekle ─────────────────────────
# main.py "modül/" klasöründe, db_yonetici.py bir üst dizinde.
PROJE_KOK = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJE_KOK))

import db_yonetici as db

# ── Güvenlik Yapılandırması ────────────────────────────────────
# Ortam değişkeninden oku; yoksa rastgele bir anahtar üret
# (NOT: Rastgele anahtar her başlatmada değişir, üretimde .env kullanılmalı)
GIZLI_ANAHTAR = os.environ.get("BB_SECRET_KEY", secrets.token_hex(32))
ALGORITMA = "HS256"
TOKEN_SURESI_DK = 60

oauth2_sema = OAuth2PasswordBearer(tokenUrl="/api/giris")


# ── Pydantic Modelleri (Input Doğrulama) ───────────────────────

class GuvenlikKuraliEkle(BaseModel):
    kural_adi: str = Field(..., min_length=1, max_length=100)
    yon: str = Field(..., pattern="^(giris|cikis|ilet)$")
    protokol: str = Field(..., pattern="^(tcp|udp|icmp|herhangi)$")
    eylem: str = Field(..., pattern="^(izin_ver|engelle|reddet)$")
    kaynak_ip: Optional[str] = None
    hedef_ip: Optional[str] = None
    kaynak_port: Optional[str] = None
    hedef_port: Optional[str] = None
    oncelik: int = Field(100, ge=1, le=999)
    aciklama: Optional[str] = None


class YonlendirmeKuraliEkle(BaseModel):
    kural_adi: str = Field(..., min_length=1, max_length=100)
    tur: str = Field(..., pattern="^(masquerade|dnat|snat)$")
    protokol: str = Field(..., pattern="^(tcp|udp|herhangi)$")
    dis_arayuz: Optional[str] = None
    ic_arayuz: Optional[str] = None
    dis_port: Optional[str] = None
    ic_ip: Optional[str] = None
    ic_port: Optional[str] = None
    aciklama: Optional[str] = None


class DhcpAyarGuncelle(BaseModel):
    aktif: bool
    alt_ag: Optional[str] = None
    alt_ag_maskesi: Optional[str] = None
    havuz_baslangic: Optional[str] = None
    havuz_bitis: Optional[str] = None
    ag_gecidi: Optional[str] = None
    dns_sunuculari: Optional[str] = None
    kira_suresi: int = Field(86400, ge=300)


class KullaniciEkle(BaseModel):
    kullanici_adi: str = Field(..., min_length=2, max_length=50)
    sifre: str = Field(..., min_length=4, max_length=128)
    ad_soyad: str = Field("", max_length=100)
    grup_id: int = Field(2, ge=1)  # Varsayılan: yonetici grubu


class YetkiGrubuEkle(BaseModel):
    grup_adi: str = Field(..., min_length=2, max_length=50)
    aciklama: str = Field("", max_length=200)
    izinler: str = Field("{}", max_length=500)


class SistemTercihiGuncelle(BaseModel):
    tercihler: dict  # {"hostname": "...", "domain": "...", "dark_mode": true}


# ── JWT Yardımcı Fonksiyonlar ──────────────────────────────────

def token_olustur(kullanici: dict) -> str:
    """Kullanıcı bilgilerini içeren JWT token oluşturur."""
    bitis = datetime.now(timezone.utc) + timedelta(minutes=TOKEN_SURESI_DK)
    payload = {
        "sub": kullanici["kullanici_adi"],
        "uid": kullanici["id"],
        "rol": kullanici.get("rol", "admin"),
        "grup_adi": kullanici.get("grup_adi", "yonetici"),
        "ad_soyad": kullanici.get("ad_soyad", ""),
        "exp": bitis
    }
    return jwt.encode(payload, GIZLI_ANAHTAR, algorithm=ALGORITMA)


def mevcut_kullanici(token: str = Depends(oauth2_sema)) -> dict:
    try:
        veri = jwt.decode(token, GIZLI_ANAHTAR, algorithms=[ALGORITMA])
        kullanici_adi = veri.get("sub")
        if not kullanici_adi:
            raise HTTPException(status_code=401, detail="Geçersiz token")
        return {
            "kullanici_adi": kullanici_adi,
            "uid": veri.get("uid"),
            "rol": veri.get("rol", "admin"),
            "grup_adi": veri.get("grup_adi", "yonetici"),
            "ad_soyad": veri.get("ad_soyad", "")
        }
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token süresi dolmuş")
    except jwt.PyJWTError:
        raise HTTPException(status_code=401, detail="Token doğrulanamadı")


# ── Uygulama Yaşam Döngüsü (Lifespan) ────────────────────────

@asynccontextmanager
async def yasam_dongusu(app: FastAPI):
    """Uvicorn başlarken veritabanını hazırla ve kalıcı kuralları yükle."""
    db.veritabanini_baslat()

    # Kural kalıcılığı: DB'deki kuralları nftables'a yeniden uygula
    kurallar = db.kurallari_getir(sadece_aktif=True)
    print(f"[DB] {len(kurallar)} kural yükleniyor...")
    # TODO: Her kural için nftables komutunu çalıştır
    # (Bu kısım, ağ modülünü yazan arkadaşın görevi)

    yield  # Uygulama çalışıyor

    # Kapatma sırasında yapılacak işlemler (opsiyonel)
    print("[DB] Uygulama kapatılıyor...")


# ── Uygulama Oluşturma ────────────────────────────────────────

app = FastAPI(
    title="Black Barrier API",
    version="1.0",
    lifespan=yasam_dongusu
)

# CORS Middleware — ön uç aynı sunucudan sunulmazsa gerekli
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],      # Üretimde kısıtlanmalı
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Statik Dosya Sunumu ────────────────────────────────────────
# HTML, CSS, JS dosyalarını sunmak için
app.mount("/varliklar", StaticFiles(directory=str(PROJE_KOK / "varliklar")), name="varliklar")


# ── Sayfa Endpoint'leri (HTML Sunumu) ──────────────────────────

@app.get("/", include_in_schema=False)
async def anasayfa():
    return FileResponse(str(PROJE_KOK / "index.html"))


@app.get("/{sayfa_adi}.html", include_in_schema=False)
async def sayfa_sun(sayfa_adi: str):
    dosya = PROJE_KOK / f"{sayfa_adi}.html"
    if not dosya.exists():
        raise HTTPException(404, "Sayfa bulunamadı")
    return FileResponse(str(dosya))


# ══════════════════════════════════════════════════════════════
#  KİMLİK DOĞRULAMA API
# ══════════════════════════════════════════════════════════════

@app.post("/api/giris")
async def giris(request: Request, form: OAuth2PasswordRequestForm = Depends()):
    """Kullanıcı girişi — başarılıysa JWT token döndürür."""
    # İstemci bilgilerini al (log için)
    istemci_ip = request.client.host if request.client else "bilinmiyor"
    user_agent = request.headers.get("user-agent", "bilinmiyor")

    kullanici = db.kullanici_dogrula(form.username, form.password)
    if not kullanici:
        # Başarısız giriş logu
        db.giris_kaydi_ekle(
            kullanici_id=None,
            kullanici_adi=form.username,
            ip_adresi=istemci_ip,
            user_agent=user_agent,
            basarili=False
        )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Kullanıcı adı veya şifre hatalı"
        )

    # Başarılı giriş logu
    db.giris_kaydi_ekle(
        kullanici_id=kullanici["id"],
        kullanici_adi=kullanici["kullanici_adi"],
        ip_adresi=istemci_ip,
        user_agent=user_agent,
        basarili=True
    )

    token = token_olustur(kullanici)
    return {"access_token": token, "token_type": "bearer"}


@app.get("/api/ben")
async def profil_bilgisi(aktif_kullanici=Depends(mevcut_kullanici)):
    """Giriş yapan kullanıcının profil bilgilerini döndürür."""
    bilgi = db.kullanici_bilgisi_getir(aktif_kullanici["kullanici_adi"])
    if not bilgi:
        raise HTTPException(404, "Kullanıcı bulunamadı")
    # Şifre hash'ini döndürme
    bilgi.pop("sifre_hash", None)
    return bilgi


# ══════════════════════════════════════════════════════════════
#  KULLANICI YÖNETİMİ API
# ══════════════════════════════════════════════════════════════

@app.get("/api/kullanicilar")
async def kullanicilari_listele(aktif_kullanici=Depends(mevcut_kullanici)):
    """Tüm kullanıcıları listeler."""
    return db.kullanicilari_getir()


@app.post("/api/kullanicilar", status_code=201)
async def kullanici_olustur(
    veri: KullaniciEkle,
    aktif_kullanici=Depends(mevcut_kullanici)
):
    """Yeni kullanıcı oluşturur."""
    try:
        yeni_id = db.kullanici_olustur(
            kullanici_adi=veri.kullanici_adi,
            sifre=veri.sifre,
            ad_soyad=veri.ad_soyad,
            grup_id=veri.grup_id
        )
        return {"id": yeni_id, "mesaj": "Kullanıcı oluşturuldu"}
    except Exception as e:
        if "UNIQUE" in str(e):
            raise HTTPException(409, "Bu kullanıcı adı zaten mevcut")
        raise HTTPException(500, f"Kullanıcı oluşturulamadı: {e}")


@app.delete("/api/kullanicilar/{kullanici_id}")
async def kullanici_kaldir(
    kullanici_id: int,
    aktif_kullanici=Depends(mevcut_kullanici)
):
    """Kullanıcıyı siler. Kendini silemez."""
    if aktif_kullanici.get("uid") == kullanici_id:
        raise HTTPException(400, "Kendi hesabınızı silemezsiniz")
    if not db.kullanici_sil(kullanici_id):
        raise HTTPException(404, "Kullanıcı bulunamadı")
    return {"mesaj": "Kullanıcı silindi"}


# ══════════════════════════════════════════════════════════════
#  YETKİ GRUPLARI API
# ══════════════════════════════════════════════════════════════

@app.get("/api/yetki-gruplari")
async def yetki_gruplari_listele(aktif_kullanici=Depends(mevcut_kullanici)):
    """Tüm yetki gruplarını listeler."""
    return db.yetki_gruplari_getir()


@app.post("/api/yetki-gruplari", status_code=201)
async def yetki_grubu_olustur(
    veri: YetkiGrubuEkle,
    aktif_kullanici=Depends(mevcut_kullanici)
):
    """Yeni yetki grubu oluşturur."""
    try:
        yeni_id = db.yetki_grubu_ekle(veri.grup_adi, veri.aciklama, veri.izinler)
        return {"id": yeni_id, "mesaj": "Yetki grubu oluşturuldu"}
    except Exception as e:
        if "UNIQUE" in str(e):
            raise HTTPException(409, "Bu grup adı zaten mevcut")
        raise HTTPException(500, f"Grup oluşturulamadı: {e}")


@app.delete("/api/yetki-gruplari/{grup_id}")
async def yetki_grubu_kaldir(
    grup_id: int,
    aktif_kullanici=Depends(mevcut_kullanici)
):
    """Yetki grubunu siler. Varsayılan gruplar silinemez."""
    if not db.yetki_grubu_sil(grup_id):
        raise HTTPException(400, "Bu grup silinemez (varsayılan grup veya bulunamadı)")
    return {"mesaj": "Yetki grubu silindi"}


# ══════════════════════════════════════════════════════════════
#  GİRİŞ KAYITLARI API
# ══════════════════════════════════════════════════════════════

@app.get("/api/giris-kayitlari")
async def giris_kayitlari_listele(aktif_kullanici=Depends(mevcut_kullanici)):
    """Mevcut kullanıcının giriş kayıtlarını döndürür."""
    return db.giris_kayitlari_getir(
        kullanici_id=aktif_kullanici.get("uid"),
        limit=50
    )


@app.get("/api/giris-kayitlari/tumu")
async def tum_giris_kayitlari(aktif_kullanici=Depends(mevcut_kullanici)):
    """Tüm kullanıcıların giriş kayıtlarını döndürür (admin)."""
    return db.giris_kayitlari_getir(limit=100)


# ══════════════════════════════════════════════════════════════
#  SİSTEM TERCİHLERİ API
# ══════════════════════════════════════════════════════════════

@app.get("/api/sistem-tercihleri")
async def sistem_tercihlerini_getir(aktif_kullanici=Depends(mevcut_kullanici)):
    """Mevcut kullanıcının tercihlerini döndürür."""
    return db.sistem_tercihleri_getir(aktif_kullanici.get("uid"))


@app.put("/api/sistem-tercihleri")
async def sistem_tercihlerini_kaydet(
    veri: SistemTercihiGuncelle,
    aktif_kullanici=Depends(mevcut_kullanici)
):
    """Kullanıcı tercihlerini kaydeder."""
    uid = aktif_kullanici.get("uid")
    for anahtar, deger in veri.tercihler.items():
        db.sistem_tercihi_kaydet(uid, anahtar, str(deger))
    return {"mesaj": "Tercihler kaydedildi"}


# ══════════════════════════════════════════════════════════════
#  GÜVENLİK KURALLARI API
# ══════════════════════════════════════════════════════════════

@app.get("/api/kurallar")
async def kurallari_listele(aktif_kullanici=Depends(mevcut_kullanici)):
    return db.kurallari_getir()


@app.post("/api/kurallar", status_code=201)
async def kural_olustur(
    veri: GuvenlikKuraliEkle,
    aktif_kullanici=Depends(mevcut_kullanici)
):
    yeni_id = db.kural_ekle(veri.model_dump())
    return {"id": yeni_id, "mesaj": "Kural eklendi"}


@app.delete("/api/kurallar/{kural_id}")
async def kural_kaldir(kural_id: int, aktif_kullanici=Depends(mevcut_kullanici)):
    if not db.kural_sil(kural_id):
        raise HTTPException(404, "Kural bulunamadı")
    return {"mesaj": "Kural silindi"}


@app.patch("/api/kurallar/{kural_id}/durum")
async def kural_durum_guncelle(
    kural_id: int,
    aktif: bool,
    aktif_kullanici=Depends(mevcut_kullanici)
):
    if not db.kural_durum_degistir(kural_id, aktif):
        raise HTTPException(404, "Kural bulunamadı")
    return {"mesaj": "Kural durumu güncellendi"}


# ── Yönlendirme Endpoint'leri ──────────────────────────────────

@app.get("/api/yonlendirme")
async def yonlendirme_listele(aktif_kullanici=Depends(mevcut_kullanici)):
    return db.yonlendirme_kurallari_getir()


@app.post("/api/yonlendirme", status_code=201)
async def yonlendirme_ekle(
    veri: YonlendirmeKuraliEkle,
    aktif_kullanici=Depends(mevcut_kullanici)
):
    yeni_id = db.yonlendirme_kurali_ekle(veri.model_dump())
    return {"id": yeni_id, "mesaj": "Yönlendirme kuralı eklendi"}


@app.delete("/api/yonlendirme/{kural_id}")
async def yonlendirme_kaldir(kural_id: int, aktif_kullanici=Depends(mevcut_kullanici)):
    if not db.yonlendirme_kurali_sil(kural_id):
        raise HTTPException(404, "Kural bulunamadı")
    return {"mesaj": "Yönlendirme kuralı silindi"}


# ── DHCP Endpoint'leri ─────────────────────────────────────────

@app.get("/api/dhcp/{arayuz}")
async def dhcp_ayarlari(arayuz: str, aktif_kullanici=Depends(mevcut_kullanici)):
    ayarlar = db.dhcp_ayarlarini_getir(arayuz)
    if not ayarlar:
        raise HTTPException(404, "Arayüz bulunamadı")
    return ayarlar


@app.put("/api/dhcp/{arayuz}")
async def dhcp_guncelle(
    arayuz: str,
    veri: DhcpAyarGuncelle,
    aktif_kullanici=Depends(mevcut_kullanici)
):
    db.dhcp_ayarlarini_kaydet(arayuz, veri.model_dump())
    return {"mesaj": "DHCP ayarları güncellendi"}


@app.get("/api/dhcp/{arayuz}/kiralamalar")
async def kiralamalar(arayuz: str, aktif_kullanici=Depends(mevcut_kullanici)):
    return db.dhcp_kiralamalari_getir(arayuz)


# ── Trafik ve Panel Endpoint'leri ──────────────────────────────

@app.get("/api/trafik")
async def trafik_loglari(
    limit: int = 100,
    eylem: Optional[str] = None,
    aktif_kullanici=Depends(mevcut_kullanici)
):
    return db.trafik_kayitlarini_getir(limit=limit, eylem_filtresi=eylem)


@app.get("/api/panel/ozet")
async def panel_ozeti(aktif_kullanici=Depends(mevcut_kullanici)):
    return db.trafik_istatistiklerini_getir()
