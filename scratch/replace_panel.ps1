$path = "C:\Users\taha0\Downloads\BlackBarrier-Firewall-main\BlackBarrier-Firewall-main\Firewall\panel.html"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$content = [System.IO.File]::ReadAllText($path, $utf8NoBom)

$newContent = @"
                <!-- 2. Sekme: Kullanıcılar -->
                <div id="kullanicilarPenceresi" class="ayar-icerik hidden space-y-6">
                    
                    <!-- İç Sekmeler -->
                    <div class="flex items-center gap-2 border-b-2 border-slate-200 pb-2">
                        <button class="yonetim-tab bg-birincil text-white px-4 py-2 font-bold text-sm uppercase transition-colors hover:bg-birincil-acik" data-hedef="yonetim-kullanicilar">Kullanıcılar</button>
                        <button class="yonetim-tab bg-slate-200 text-slate-600 px-4 py-2 font-bold text-sm uppercase transition-colors hover:bg-slate-300" data-hedef="yonetim-gruplar">Yetki Grupları</button>
                        <button class="yonetim-tab bg-slate-200 text-slate-600 px-4 py-2 font-bold text-sm uppercase transition-colors hover:bg-slate-300" data-hedef="yonetim-etiketler">Etiketler</button>
                    </div>

                    <!-- Kullanıcılar Sekmesi -->
                    <div id="yonetim-kullanicilar" class="yonetim-icerik space-y-6">
                        <!-- Kullanıcı Ekleme Formu -->
                        <div id="formKullaniciEkle" class="hidden bg-yuzey border-2 border-birincil shadow-sm p-6 mb-6">
                            <h4 class="text-sm font-bold uppercase mb-4 text-birincil border-b-2 border-slate-100 pb-2">Yeni Kullanıcı Ekle</h4>
                            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                                <div class="flex flex-col gap-2">
                                    <label class="text-[11px] font-kod text-slate-600 font-bold uppercase">Kullanıcı Adı</label>
                                    <input id="yeni_kullanici_adi" class="w-full border-2 border-slate-300 focus:border-birincil outline-none p-2 text-sm font-kod bg-white" type="text" />
                                </div>
                                <div class="flex flex-col gap-2">
                                    <label class="text-[11px] font-kod text-slate-600 font-bold uppercase">Şifre</label>
                                    <input id="yeni_kullanici_sifre" class="w-full border-2 border-slate-300 focus:border-birincil outline-none p-2 text-sm font-kod bg-white" type="password" />
                                </div>
                                <div class="flex flex-col gap-2">
                                    <label class="text-[11px] font-kod text-slate-600 font-bold uppercase">İsim Soyisim</label>
                                    <input id="yeni_kullanici_ad" class="w-full border-2 border-slate-300 focus:border-birincil outline-none p-2 text-sm font-kod bg-white" type="text" />
                                </div>
                                <div class="flex flex-col gap-2">
                                    <label class="text-[11px] font-kod text-slate-600 font-bold uppercase">Yetki Grubu</label>
                                    <select id="yeni_kullanici_grup" class="w-full border-2 border-slate-300 focus:border-birincil outline-none p-2 text-sm font-kod bg-white">
                                        <!-- Dinamik Doldurulacak -->
                                    </select>
                                </div>
                                <div class="flex flex-col gap-2 md:col-span-2">
                                    <label class="text-[11px] font-kod text-slate-600 font-bold uppercase">Etiketler (İsteğe Bağlı, CTRL ile çoklu seçim)</label>
                                    <select id="yeni_kullanici_etiketler" multiple class="w-full border-2 border-slate-300 focus:border-birincil outline-none p-2 text-sm font-kod bg-white h-24">
                                        <!-- Dinamik Doldurulacak -->
                                    </select>
                                </div>
                            </div>
                            <div class="mt-4 flex justify-end gap-2">
                                <button onclick="document.getElementById('formKullaniciEkle').classList.add('hidden')" class="px-4 py-2 border-2 border-slate-300 text-slate-600 font-bold uppercase text-xs hover:bg-slate-100 transition-colors">İptal</button>
                                <button id="btnKullaniciKaydet" class="px-4 py-2 bg-birincil text-white font-bold uppercase text-xs hover:bg-birincil-acik transition-colors">Kaydet</button>
                            </div>
                        </div>

                        <div class="bg-yuzey border-2 border-kenarlik-kalin shadow-sm">
                            <div class="p-4 border-b-2 border-slate-200 flex justify-between items-center bg-slate-50">
                                <h3 class="text-sm font-bold uppercase tracking-wide">Sistem Hesapları</h3>
                                <button onclick="document.getElementById('formKullaniciEkle').classList.toggle('hidden')" class="flex items-center gap-2 text-[10px] bg-birincil text-white px-3 py-2 uppercase font-bold hover:bg-birincil-acik transition-colors">
                                    <span class="material-symbols-outlined text-[14px]">person_add</span> Yeni Kullanıcı
                                </button>
                            </div>
                            <div class="overflow-x-auto">
                                <table class="w-full text-left veri-tablosu whitespace-nowrap font-kod text-sm text-slate-700">
                                    <thead class="bg-slate-100 border-b-2 border-slate-300">
                                        <tr>
                                            <th class="py-3 px-4 uppercase text-xs font-bold text-slate-500">Kullanıcı Adı</th>
                                            <th class="py-3 px-4 uppercase text-xs font-bold text-slate-500">İsim</th>
                                            <th class="py-3 px-4 uppercase text-xs font-bold text-slate-500">Grup</th>
                                            <th class="py-3 px-4 uppercase text-xs font-bold text-slate-500">Etiketler</th>
                                            <th class="py-3 px-4 uppercase text-xs font-bold text-slate-500">İşlem</th>
                                        </tr>
                                    </thead>
                                    <tbody id="kullanicilarTablosuGövde">
                                        <!-- Dinamik -->
                                    </tbody>
                                </table>
                            </div>
                        </div>
                    </div>

                    <!-- Gruplar Sekmesi -->
                    <div id="yonetim-gruplar" class="yonetim-icerik hidden space-y-6">
                        <div id="formGrupEkle" class="hidden bg-yuzey border-2 border-birincil shadow-sm p-6 mb-6">
                            <h4 class="text-sm font-bold uppercase mb-4 text-birincil border-b-2 border-slate-100 pb-2">Yeni Yetki Grubu Ekle</h4>
                            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                                <div class="flex flex-col gap-2">
                                    <label class="text-[11px] font-kod text-slate-600 font-bold uppercase">Grup Adı</label>
                                    <input id="yeni_grup_adi" class="w-full border-2 border-slate-300 focus:border-birincil outline-none p-2 text-sm font-kod bg-white" type="text" />
                                </div>
                                <div class="flex flex-col gap-2">
                                    <label class="text-[11px] font-kod text-slate-600 font-bold uppercase">Açıklama</label>
                                    <input id="yeni_grup_aciklama" class="w-full border-2 border-slate-300 focus:border-birincil outline-none p-2 text-sm font-kod bg-white" type="text" />
                                </div>
                            </div>
                            <div class="mt-4 flex justify-end gap-2">
                                <button onclick="document.getElementById('formGrupEkle').classList.add('hidden')" class="px-4 py-2 border-2 border-slate-300 text-slate-600 font-bold uppercase text-xs hover:bg-slate-100 transition-colors">İptal</button>
                                <button id="btnGrupKaydet" class="px-4 py-2 bg-birincil text-white font-bold uppercase text-xs hover:bg-birincil-acik transition-colors">Kaydet</button>
                            </div>
                        </div>

                        <div class="bg-yuzey border-2 border-kenarlik-kalin shadow-sm">
                            <div class="p-4 border-b-2 border-slate-200 flex justify-between items-center bg-slate-50">
                                <h3 class="text-sm font-bold uppercase tracking-wide">Yetki Grupları</h3>
                                <button onclick="document.getElementById('formGrupEkle').classList.toggle('hidden')" class="flex items-center gap-2 text-[10px] bg-birincil text-white px-3 py-2 uppercase font-bold hover:bg-birincil-acik transition-colors">
                                    <span class="material-symbols-outlined text-[14px]">group_add</span> Yeni Grup
                                </button>
                            </div>
                            <div class="overflow-x-auto">
                                <table class="w-full text-left veri-tablosu whitespace-nowrap font-kod text-sm text-slate-700">
                                    <thead class="bg-slate-100 border-b-2 border-slate-300">
                                        <tr>
                                            <th class="py-3 px-4 uppercase text-xs font-bold text-slate-500">Grup Adı</th>
                                            <th class="py-3 px-4 uppercase text-xs font-bold text-slate-500">Açıklama</th>
                                            <th class="py-3 px-4 uppercase text-xs font-bold text-slate-500">İşlem</th>
                                        </tr>
                                    </thead>
                                    <tbody id="gruplarTablosuGövde">
                                        <!-- Dinamik -->
                                    </tbody>
                                </table>
                            </div>
                        </div>
                    </div>

                    <!-- Etiketler Sekmesi -->
                    <div id="yonetim-etiketler" class="yonetim-icerik hidden space-y-6">
                        <div id="formEtiketEkle" class="hidden bg-yuzey border-2 border-birincil shadow-sm p-6 mb-6">
                            <h4 class="text-sm font-bold uppercase mb-4 text-birincil border-b-2 border-slate-100 pb-2">Yeni Etiket Ekle</h4>
                            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                                <div class="flex flex-col gap-2">
                                    <label class="text-[11px] font-kod text-slate-600 font-bold uppercase">Etiket Adı</label>
                                    <input id="yeni_etiket_adi" class="w-full border-2 border-slate-300 focus:border-birincil outline-none p-2 text-sm font-kod bg-white" type="text" />
                                </div>
                                <div class="flex flex-col gap-2">
                                    <label class="text-[11px] font-kod text-slate-600 font-bold uppercase">Renk Sınıfı (Tailwind)</label>
                                    <input id="yeni_etiket_renk" class="w-full border-2 border-slate-300 focus:border-birincil outline-none p-2 text-sm font-kod bg-white" type="text" placeholder="Örn: bg-red-500" value="bg-slate-500" />
                                </div>
                            </div>
                            <div class="mt-4 flex justify-end gap-2">
                                <button onclick="document.getElementById('formEtiketEkle').classList.add('hidden')" class="px-4 py-2 border-2 border-slate-300 text-slate-600 font-bold uppercase text-xs hover:bg-slate-100 transition-colors">İptal</button>
                                <button id="btnEtiketKaydet" class="px-4 py-2 bg-birincil text-white font-bold uppercase text-xs hover:bg-birincil-acik transition-colors">Kaydet</button>
                            </div>
                        </div>

                        <div class="bg-yuzey border-2 border-kenarlik-kalin shadow-sm">
                            <div class="p-4 border-b-2 border-slate-200 flex justify-between items-center bg-slate-50">
                                <h3 class="text-sm font-bold uppercase tracking-wide">Sistem Etiketleri</h3>
                                <button onclick="document.getElementById('formEtiketEkle').classList.toggle('hidden')" class="flex items-center gap-2 text-[10px] bg-birincil text-white px-3 py-2 uppercase font-bold hover:bg-birincil-acik transition-colors">
                                    <span class="material-symbols-outlined text-[14px]">sell</span> Yeni Etiket
                                </button>
                            </div>
                            <div class="overflow-x-auto">
                                <table class="w-full text-left veri-tablosu whitespace-nowrap font-kod text-sm text-slate-700">
                                    <thead class="bg-slate-100 border-b-2 border-slate-300">
                                        <tr>
                                            <th class="py-3 px-4 uppercase text-xs font-bold text-slate-500">Etiket Adı</th>
                                            <th class="py-3 px-4 uppercase text-xs font-bold text-slate-500">Görünüm</th>
                                            <th class="py-3 px-4 uppercase text-xs font-bold text-slate-500">İşlem</th>
                                        </tr>
                                    </thead>
                                    <tbody id="etiketlerTablosuGövde">
                                        <!-- Dinamik -->
                                    </tbody>
                                </table>
                            </div>
                        </div>
                    </div>

                </div>
"@

$content = $content -replace '(?s)<!-- 2. Sekme: Kullanıcılar -->\s*<div id="kullanicilarPenceresi" class="ayar-icerik hidden space-y-6">.*?</div>\s*</div>\s*<!-- 3. Sekme: Güncelleme -->', ($newContent + "`r`n`r`n                <!-- 3. Sekme: Güncelleme -->")
[System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
