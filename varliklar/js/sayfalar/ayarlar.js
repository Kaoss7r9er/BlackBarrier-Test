/**
 * Black Barrier — Ayarlar & Kullanıcı Yönetimi İşlemleri
 */

const AyarlarModulu = (function () {
    'use strict';

    function init() {
        if (!document.getElementById('yonetim-kullanicilar')) return; // Sayfada değilsek çık

        olayDinleyicileriAta();
        verileriYukle();
    }

    function olayDinleyicileriAta() {
        // İç sekmeler
        const tablar = document.querySelectorAll('.yonetim-tab');
        const icerikler = document.querySelectorAll('.yonetim-icerik');

        tablar.forEach(tab => {
            tab.addEventListener('click', () => {
                // Tab stillerini sıfırla
                tablar.forEach(t => {
                    t.classList.remove('bg-birincil', 'text-white');
                    t.classList.add('bg-slate-200', 'text-slate-600');
                });
                // Aktif tab
                tab.classList.remove('bg-slate-200', 'text-slate-600');
                tab.classList.add('bg-birincil', 'text-white');

                // İçerikleri gizle
                icerikler.forEach(c => c.classList.add('hidden'));

                // Hedef içeriği göster
                const hedef = document.getElementById(tab.dataset.hedef);
                if (hedef) hedef.classList.remove('hidden');
            });
        });

        // Kaydet Butonları
        document.getElementById('btnEtiketKaydet')?.addEventListener('click', etiketKaydet);
        document.getElementById('btnGrupKaydet')?.addEventListener('click', grupKaydet);
        document.getElementById('btnKullaniciKaydet')?.addEventListener('click', kullaniciKaydet);
    }

    async function verileriYukle() {
        try {
            await etiketleriCek();
            await gruplariCek();
            await kullanicilariCek();
        } catch (error) {
            console.error("Veriler yüklenemedi", error);
        }
    }

    // --- API ÇAĞRILARI VE TABLO DOLDURMA ---

    async function etiketleriCek() {
        const token = localStorage.getItem('bb_token');
        const yanit = await fetch('/api/etiketler', {
            headers: { 'Authorization': `Bearer ${token}` }
        });
        if (!yanit.ok) return;

        const etiketler = await yanit.json();
        
        // Tabloyu doldur
        const govde = document.getElementById('etiketlerTablosuGövde');
        if (govde) {
            govde.innerHTML = '';
            etiketler.forEach(e => {
                govde.innerHTML += `
                    <tr class="border-b border-slate-100 hover:bg-slate-50">
                        <td class="py-3 px-4 font-bold text-slate-800">${e.etiket_adi}</td>
                        <td class="py-3 px-4">
                            <span class="${e.renk} text-white px-2 py-1 text-[10px] uppercase font-bold rounded-sm shadow-sm">${e.etiket_adi}</span>
                        </td>
                        <td class="py-3 px-4">
                            <button onclick="AyarlarModulu.etiketSil(${e.id})" class="text-durum-kritik hover:underline text-xs font-bold uppercase"><span class="material-symbols-outlined text-sm align-middle">delete</span> Sil</button>
                        </td>
                    </tr>
                `;
            });
        }

        // Kullanıcı ekleme formundaki Select'i doldur
        const select = document.getElementById('yeni_kullanici_etiketler');
        if (select) {
            select.innerHTML = '';
            etiketler.forEach(e => {
                select.innerHTML += `<option value="${e.id}">${e.etiket_adi}</option>`;
            });
        }
    }

    async function gruplariCek() {
        const token = localStorage.getItem('bb_token');
        const yanit = await fetch('/api/yetki-gruplari', {
            headers: { 'Authorization': `Bearer ${token}` }
        });
        if (!yanit.ok) return;

        const gruplar = await yanit.json();
        
        const govde = document.getElementById('gruplarTablosuGövde');
        if (govde) {
            govde.innerHTML = '';
            gruplar.forEach(g => {
                const silinebilir = g.id > 3; // varsayılanlar silinemez
                govde.innerHTML += `
                    <tr class="border-b border-slate-100 hover:bg-slate-50">
                        <td class="py-3 px-4 font-bold text-slate-800">${g.grup_adi}</td>
                        <td class="py-3 px-4 text-xs">${g.aciklama || '-'}</td>
                        <td class="py-3 px-4">
                            ${silinebilir ? `<button onclick="AyarlarModulu.grupSil(${g.id})" class="text-durum-kritik hover:underline text-xs font-bold uppercase"><span class="material-symbols-outlined text-sm align-middle">delete</span> Sil</button>` : '<span class="text-slate-400 text-xs">Sistem</span>'}
                        </td>
                    </tr>
                `;
            });
        }

        const select = document.getElementById('yeni_kullanici_grup');
        if (select) {
            select.innerHTML = '';
            gruplar.forEach(g => {
                select.innerHTML += `<option value="${g.id}">${g.grup_adi}</option>`;
            });
        }
    }

    async function kullanicilariCek() {
        const token = localStorage.getItem('bb_token');
        const yanit = await fetch('/api/kullanicilar', {
            headers: { 'Authorization': `Bearer ${token}` }
        });
        if (!yanit.ok) return;

        const kullanicilar = await yanit.json();
        
        const govde = document.getElementById('kullanicilarTablosuGövde');
        if (govde) {
            govde.innerHTML = '';
            kullanicilar.forEach(k => {
                let etiketHtml = '';
                if (k.etiketler && k.etiketler.length > 0) {
                    etiketHtml = k.etiketler.map(e => `<span class="${e.renk} text-white px-1.5 py-0.5 text-[9px] uppercase font-bold rounded-sm inline-block mr-1">${e.etiket_adi}</span>`).join('');
                } else {
                    etiketHtml = '<span class="text-slate-400 text-xs">-</span>';
                }

                govde.innerHTML += `
                    <tr class="border-b border-slate-100 hover:bg-slate-50 cursor-pointer">
                        <td class="py-3 px-4 font-bold text-birincil">${k.kullanici_adi}</td>
                        <td class="py-3 px-4">${k.ad_soyad || '-'}</td>
                        <td class="py-3 px-4"><span class="bg-slate-800 text-white px-2 py-0.5 text-[10px] uppercase font-bold rounded-sm">${k.grup_adi || k.rol}</span></td>
                        <td class="py-3 px-4">${etiketHtml}</td>
                        <td class="py-3 px-4">
                            <button onclick="AyarlarModulu.kullaniciSil(${k.id})" class="text-durum-kritik hover:underline text-xs font-bold uppercase"><span class="material-symbols-outlined text-sm align-middle">delete</span></button>
                        </td>
                    </tr>
                `;
            });
        }
    }

    // --- KAYDETME İŞLEMLERİ ---

    async function etiketKaydet() {
        const adi = document.getElementById('yeni_etiket_adi').value;
        const renk = document.getElementById('yeni_etiket_renk').value || 'bg-slate-500';
        if (!adi) return alert('Etiket adı zorunlu');

        const token = localStorage.getItem('bb_token');
        const yanit = await fetch('/api/etiketler', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
            body: JSON.stringify({ etiket_adi: adi, renk: renk })
        });

        if (yanit.ok) {
            document.getElementById('yeni_etiket_adi').value = '';
            document.getElementById('formEtiketEkle').classList.add('hidden');
            etiketleriCek();
        } else {
            alert('Hata: ' + (await yanit.json()).detail);
        }
    }

    async function grupKaydet() {
        const adi = document.getElementById('yeni_grup_adi').value;
        const aciklama = document.getElementById('yeni_grup_aciklama').value;
        if (!adi) return alert('Grup adı zorunlu');

        const token = localStorage.getItem('bb_token');
        const yanit = await fetch('/api/yetki-gruplari', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
            body: JSON.stringify({ grup_adi: adi, aciklama: aciklama, izinler: "{}" })
        });

        if (yanit.ok) {
            document.getElementById('yeni_grup_adi').value = '';
            document.getElementById('formGrupEkle').classList.add('hidden');
            gruplariCek();
        } else {
            alert('Hata: ' + (await yanit.json()).detail);
        }
    }

    async function kullaniciKaydet() {
        const adi = document.getElementById('yeni_kullanici_adi').value;
        const sifre = document.getElementById('yeni_kullanici_sifre').value;
        const ad_soyad = document.getElementById('yeni_kullanici_ad').value;
        const grup = document.getElementById('yeni_kullanici_grup').value;
        
        // Çoklu etiket seçimi
        const selectEtiketler = document.getElementById('yeni_kullanici_etiketler');
        const etiketler = Array.from(selectEtiketler.selectedOptions).map(opt => parseInt(opt.value));

        if (!adi || !sifre) return alert('Adı ve Şifre zorunlu');

        const token = localStorage.getItem('bb_token');
        const yanit = await fetch('/api/kullanicilar', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
            body: JSON.stringify({
                kullanici_adi: adi,
                sifre: sifre,
                ad_soyad: ad_soyad,
                grup_id: parseInt(grup),
                etiketler: etiketler
            })
        });

        if (yanit.ok) {
            document.getElementById('yeni_kullanici_adi').value = '';
            document.getElementById('yeni_kullanici_sifre').value = '';
            document.getElementById('formKullaniciEkle').classList.add('hidden');
            kullanicilariCek();
        } else {
            alert('Hata: ' + (await yanit.json()).detail);
        }
    }

    // --- SİLME İŞLEMLERİ (Globalden erişilebilir olmalı onclick için) ---

    async function etiketSil(id) {
        if (!confirm('Emin misiniz?')) return;
        const token = localStorage.getItem('bb_token');
        await fetch(`/api/etiketler/${id}`, { method: 'DELETE', headers: { 'Authorization': `Bearer ${token}` }});
        etiketleriCek();
        kullanicilariCek(); // Etiketler güncellendi, kullanıcı tablosu da yansımalı
    }

    async function grupSil(id) {
        if (!confirm('Emin misiniz?')) return;
        const token = localStorage.getItem('bb_token');
        await fetch(`/api/yetki-gruplari/${id}`, { method: 'DELETE', headers: { 'Authorization': `Bearer ${token}` }});
        gruplariCek();
    }

    async function kullaniciSil(id) {
        if (!confirm('Emin misiniz?')) return;
        const token = localStorage.getItem('bb_token');
        await fetch(`/api/kullanicilar/${id}`, { method: 'DELETE', headers: { 'Authorization': `Bearer ${token}` }});
        kullanicilariCek();
    }

    // Dışa aktar
    return {
        init,
        etiketSil,
        grupSil,
        kullaniciSil
    };

})();

// Yüklenince veya app.js içerisinden çağrılabilir.
document.addEventListener('DOMContentLoaded', () => {
    // Küçük bir gecikme ile çalıştır (DOM hazır olduktan sonra)
    setTimeout(AyarlarModulu.init, 500);
});
