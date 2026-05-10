/**
 * Black Barrier — Merkezi Oturum Yönetimi (oturum.js)
 * ====================================================
 * Tüm panel sayfalarında include edilerek:
 *  1. Token yoksa giriş sayfasına yönlendirir
 *  2. Token payload'ından kullanıcı bilgilerini çıkarır
 *  3. Profil alanlarını otomatik doldurur
 *  4. API isteklerine Authorization header ekler
 *  5. Çıkış fonksiyonu sağlar
 */

const Oturum = (function () {
    'use strict';

    const TOKEN_ANAHTAR = 'bb_token';
    const KULLANICI_ANAHTAR = 'bb_kullanici';
    const GIRIS_SAYFASI = '/';

    // ── Token İşlemleri ─────────────────────────────────

    function tokenAl() {
        return localStorage.getItem(TOKEN_ANAHTAR);
    }

    function tokenPayloadCoz(token) {
        try {
            const parcalar = token.split('.');
            if (parcalar.length !== 3) return null;
            const payload = JSON.parse(atob(parcalar[1]));
            return payload;
        } catch (e) {
            return null;
        }
    }

    function tokenSuresiDolduMu(payload) {
        if (!payload || !payload.exp) return true;
        const simdi = Math.floor(Date.now() / 1000);
        return simdi >= payload.exp;
    }

    // ── Oturum Kontrolü ─────────────────────────────────

    function oturumKontrol() {
        const token = tokenAl();
        if (!token) {
            cikisYap();
            return null;
        }

        const payload = tokenPayloadCoz(token);
        if (!payload || tokenSuresiDolduMu(payload)) {
            cikisYap();
            return null;
        }

        return {
            kullanici_adi: payload.sub || '',
            uid: payload.uid || 0,
            rol: payload.rol || 'admin',
            grup_adi: payload.grup_adi || 'yonetici',
            ad_soyad: payload.ad_soyad || '',
            basHarfler: basHarfHesapla(payload.ad_soyad || payload.sub || 'BB')
        };
    }

    function basHarfHesapla(isim) {
        if (!isim) return 'BB';
        const parcalar = isim.trim().split(/\s+/);
        if (parcalar.length >= 2) {
            return (parcalar[0][0] + parcalar[1][0]).toUpperCase();
        }
        return isim.substring(0, 2).toUpperCase();
    }

    function grupEtiketiAl(grup_adi) {
        const etiketler = {
            'super_admin': { metin: 'SÜPER ADMİN', renk: 'bg-slate-800 text-white' },
            'yonetici': { metin: 'YÖNETİCİ', renk: 'bg-birincil text-white' },
            'izleyici': { metin: 'İZLEYİCİ', renk: 'bg-slate-400 text-white' }
        };
        return etiketler[grup_adi] || { metin: grup_adi.toUpperCase(), renk: 'bg-slate-500 text-white' };
    }

    // ── Profil Alanlarını Doldur ─────────────────────────

    function profilDoldur(bilgi) {
        if (!bilgi) return;

        // Profil butonundaki baş harfler
        document.querySelectorAll('#profilButonu .profil-bh, #profilButonu .size-6, #profilButonu .size-8').forEach(el => {
            if (!el.querySelector('*') || el.classList.contains('size-6') || el.classList.contains('size-8')) {
                // Sadece metin içeren elementlerde güncelle
                const children = el.children;
                if (children.length === 0 || el.textContent.trim() === 'AD') {
                    el.textContent = bilgi.basHarfler;
                }
            }
        });

        // Profil menüsündeki isim ve rol
        const profilMenusu = document.getElementById('profilMenusu');
        if (profilMenusu) {
            const isimEl = profilMenusu.querySelector('.profil-isim');
            const rolEl = profilMenusu.querySelector('.profil-rol');
            const bhEl = profilMenusu.querySelector('.profil-bh-buyuk');

            if (isimEl) isimEl.textContent = bilgi.ad_soyad || bilgi.kullanici_adi;
            if (rolEl) {
                const etiket = grupEtiketiAl(bilgi.grup_adi);
                rolEl.textContent = etiket.metin;
            }
            if (bhEl) bhEl.textContent = bilgi.basHarfler;
        }

        // Sidebar profil alanları
        document.querySelectorAll('.profil-kullanici-adi').forEach(el => {
            el.textContent = bilgi.ad_soyad || bilgi.kullanici_adi;
        });
        document.querySelectorAll('.profil-rol-adi').forEach(el => {
            const etiket = grupEtiketiAl(bilgi.grup_adi);
            el.textContent = etiket.metin;
        });
    }

    // ── API İstekleri ───────────────────────────────────

    async function apiIstegi(url, secenek = {}) {
        const token = tokenAl();
        if (!token) {
            cikisYap();
            return null;
        }

        const varsayilan = {
            headers: {
                'Authorization': `Bearer ${token}`,
                'Content-Type': 'application/json',
                ...(secenek.headers || {})
            }
        };

        const birlesik = { ...secenek, headers: varsayilan.headers };

        try {
            const yanit = await fetch(url, birlesik);
            if (yanit.status === 401) {
                cikisYap();
                return null;
            }
            return yanit;
        } catch (hata) {
            console.error('[Oturum] API hatası:', hata);
            return null;
        }
    }

    // ── Çıkış ───────────────────────────────────────────

    function cikisYap() {
        localStorage.removeItem(TOKEN_ANAHTAR);
        localStorage.removeItem(KULLANICI_ANAHTAR);
        // Giriş sayfasındaysak yönlendirme yapma
        if (!window.location.pathname.endsWith('index.html') && window.location.pathname !== '/') {
            window.location.href = GIRIS_SAYFASI;
        }
    }

    // ── Sayfa Yüklendiğinde Çalıştır ────────────────────

    function baslat() {
        const bilgi = oturumKontrol();
        if (!bilgi) return null;

        profilDoldur(bilgi);

        // Çıkış butonlarını bağla
        document.querySelectorAll('.cikis-btn, [data-cikis]').forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.preventDefault();
                cikisYap();
            });
        });

        return bilgi;
    }

    // ── Public API ──────────────────────────────────────

    return {
        baslat,
        tokenAl,
        apiIstegi,
        cikisYap,
        oturumKontrol,
        grupEtiketiAl,
        basHarfHesapla
    };

})();

// Sayfa yüklendiğinde otomatik başlat
document.addEventListener('DOMContentLoaded', () => {
    window._oturumBilgisi = Oturum.baslat();
});
