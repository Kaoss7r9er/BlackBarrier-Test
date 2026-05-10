/**
 * Black Barrier — Single Page Application (SPA) Yöneticisi
 * =========================================================
 * Tüm sayfaların yönlendirmesi (hash tabanlı) ve 
 * görünüm (view) geçişleri bu dosya üzerinden yönetilir.
 */

const App = (function () {
    'use strict';

    // Geçerli görünümlerin listesi
    const GORUNUMLER = ['dashboard', 'kurallar', 'yonlendirme', 'dhcp', 'trafik', 'ayarlar'];
    const VARSAYILAN_GORUNUM = 'dashboard';

    function init() {
        // Oturum kontrolünü yap (oturum.js üzerinden)
        if (typeof Oturum !== 'undefined') {
            const bilgi = Oturum.oturumKontrol();
            if (!bilgi) return; // Zaten yönlendirildi
        }

        // Hash değişimini dinle
        window.addEventListener('hashchange', () => {
            let hash = window.location.hash.substring(1);
            if (!hash) hash = VARSAYILAN_GORUNUM;
            gorunumDegistir(hash);
        });

        // İlk yüklemede hash yoksa veya varsa uygula
        let initialHash = window.location.hash.substring(1);
        if (!initialHash || !GORUNUMLER.includes(initialHash)) {
            window.location.hash = VARSAYILAN_GORUNUM;
            // gorunumDegistir tetiklenecek
        } else {
            gorunumDegistir(initialHash);
        }
        
        // Ayarlar sekmesindeki tabları başlat (ayarlar.html'den taşındı)
        ayarlarTablariniBaslat();
    }

    function gorunumDegistir(hedefGorunum) {
        if (!GORUNUMLER.includes(hedefGorunum)) {
            hedefGorunum = VARSAYILAN_GORUNUM;
        }

        // 1. Tüm görünümleri gizle, sadece hedefi göster
        GORUNUMLER.forEach(gorunum => {
            const element = document.getElementById(`gorunum-${gorunum}`);
            if (element) {
                if (gorunum === hedefGorunum) {
                    element.classList.remove('hidden');
                    element.classList.add('flex'); // Tüm görünümlerimiz flex tabanlı
                } else {
                    element.classList.add('hidden');
                    element.classList.remove('flex');
                }
            }
        });

        // 2. Sol Menü (Sidebar) aktif linkini güncelle
        document.querySelectorAll('nav a').forEach(link => {
            const href = link.getAttribute('href');
            if (href === `#${hedefGorunum}`) {
                link.classList.remove('hover:bg-white', 'border-transparent', 'hover:border-slate-300');
                link.classList.add('bg-white', 'border-l-4', 'border-l-birincil', 'border-y', 'border-r', 'border-y-slate-300', 'border-r-slate-300', 'shadow-sm');
                
                // İkon rengini güncelle
                const ikon = link.querySelector('.material-symbols-outlined');
                if (ikon) {
                    ikon.classList.remove('text-slate-500');
                    ikon.classList.add('text-birincil');
                }
                
                // Metin rengini güncelle
                const span = link.querySelectorAll('span')[1];
                if (span) {
                    span.classList.remove('text-slate-600', 'text-slate-700');
                    span.classList.add('text-slate-900');
                }
            } else {
                link.classList.add('hover:bg-white', 'border-transparent', 'hover:border-slate-300');
                link.classList.remove('bg-white', 'border-l-4', 'border-l-birincil', 'border-y', 'border-r', 'border-y-slate-300', 'border-r-slate-300', 'shadow-sm');
                
                // İkon rengini eski haline getir
                const ikon = link.querySelector('.material-symbols-outlined');
                if (ikon) {
                    ikon.classList.add('text-slate-500');
                    ikon.classList.remove('text-birincil');
                }

                // Metin rengini eski haline getir
                const span = link.querySelectorAll('span')[1];
                if (span) {
                    span.classList.add('text-slate-600');
                    span.classList.remove('text-slate-900');
                }
            }
        });

        // 3. Özel Durumlar (örn: Sağ paneli sadece dashboard'da göster)
        const sagPanel = document.getElementById('sag-panel');
        if (sagPanel) {
            if (hedefGorunum === 'dashboard') {
                sagPanel.classList.remove('hidden');
                sagPanel.classList.add('flex');
            } else {
                sagPanel.classList.add('hidden');
                sagPanel.classList.remove('flex');
            }
        }

        // TODO: Her modül için initialize fonksiyonlarını tetikle
        // Örn: if (hedefGorunum === 'kurallar' && typeof Kurallar !== 'undefined') Kurallar.yukle();
    }

    // Ayarlar sayfasının iç sekmeleri
    function ayarlarTablariniBaslat() {
        const tabs = document.querySelectorAll('.ayar-tab');
        const contents = document.querySelectorAll('.ayar-icerik');

        tabs.forEach(tab => {
            tab.addEventListener('click', () => {
                // Tüm tabları pasif yap
                tabs.forEach(t => {
                    t.classList.remove('bg-birincil', 'text-white', 'border-transparent');
                    t.classList.add('bg-transparent', 'text-slate-600', 'hover:bg-slate-100', 'border-transparent');
                });
                // Tıklanan tabı aktif yap
                tab.classList.remove('bg-transparent', 'text-slate-600', 'hover:bg-slate-100');
                tab.classList.add('bg-birincil', 'text-white', 'border-transparent');

                // Tüm içerikleri gizle
                contents.forEach(c => c.classList.add('hidden'));

                // İlgili içeriği göster
                const targetId = tab.getAttribute('data-hedef');
                const hedefEl = document.getElementById(targetId);
                if (hedefEl) {
                    hedefEl.classList.remove('hidden');
                }
            });
        });
    }

    // Başlat
    document.addEventListener('DOMContentLoaded', init);

    return {
        gorunumDegistir
    };

})();
