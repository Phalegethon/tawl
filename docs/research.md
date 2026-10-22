**Sistem yükünü anlaşılır kılmak: araç araştırması ve kullanım senaryoları**

Araştırma tarihi: 22 Ekim 2026. Bu bölüm araştırma aşamasını anlatır; sonradan geliştirilen yerel nabiz prototipinin gerçek cihaz doğrulaması docs/progress.md dosyasındadır. Kapsam: paylaşılan htop görüntüsünden hareketle macOS öncelikli kişisel bilgisayar izleme; geliştirici uygulamaları, arka plan işler ve Docker/VM yükleri. İşletim sistemi sürümü ve işlemci modeli ayrıca doğrulanmadı. Ürün özellikleri resmî belgeler ve depolar üzerinden araştırıldı; bu bilgisayarda araç kurulumu, canlı performans ölçümü veya uygulamalı karşılaştırma yapılmadı. Aşağıdaki ürün önerileri bu nedenle deneme sırasıdır; ölçülmüş performans sıralaması değildir.

**Kullanıcının sonraki kararı: sıfırdan ürün, canlı terminal + rapor komutları.** Hazır araç kurma/deneme önerisi kapsamdan çıkarıldı. Kullanıcı herhangi bir şey kurulmasını istemiyor. Aşağıdaki pazar araştırması yalnızca özellik, tasarım ve teknik sınırlar için referans olarak korunuyor. Yeni ürünün başlangıç noktası uygulama/proje sahipliği, anlaşılır yük açıklaması ve zaman içindeki kanıtlar. Terminal biçimi kullanıcı tarafından seçildi; ayrıntılı ürün kapsamı ayrı tasarım taslağında ele alınıyor.

**Paylaştığın görüntü ne söylüyor?** Bunlar görüntünün çekildiği ana ait gözlemler; bilgisayarın şu anki durumu değildir.

| Görünen veri | Anlaşılır karşılığı | Bu veriyle tek başına söylenemeyen |
|---|---|---|
| 12 CPU göstergesi yaklaşık %58–83 arasında | Çekirdeklerin basit ortalaması yaklaşık %69,3; belirgin işlem yükü var | İşin yavaşlamasına CPU'nun neden olduğu veya işlemcinin performans kapasitesinin tam %69'unun kullanıldığı |
| Bellek 26,3 / 32 GB | htop'un raporladığı kullanım yaklaşık %82 | RAM'in yetersiz olduğu; macOS bellek baskısı ve sıkıştırma bilgisi görüntüde yok |
| Swap 19,3 / 20 GB | Diskte kayda değer swap kullanımı var | Şu anda yoğun swap trafiği olduğu, diskin %96 dolu olduğu veya sabit bir “20 GB ek RAM” sınırına gelindiği |
| Load average 18,07 / 12,98 / 11,61 | 1, 5 ve 15 dakikalık yük ortalamaları; kısa dönem değeri daha yüksek | “CPU %1807” veya darboğazın kesin kaynağı |
| VS Code Helper (Plugin): CPU %114,3 | Yaklaşık 1,14 çekirdeğin CPU zamanı kadar kullanım | Bütün bilgisayarın kapasitesinin %114'ü; hangi eklentinin sorumlu olduğu |
| Aynı satırda VIRT 1910G, RES 226M | Sanal adres alanı ile yerleşik bellek farklı büyüklükler | VS Code'un 1,9 TB fiziksel RAM kullandığı |
| Claude, VS Code ve sanallaştırma süreçleri | Birden çok uygulama ailesi aynı anda kaynak tüketiyor | Her ailenin toplamı; yalnızca görünen satırlarla eksiksiz uygulama toplamı çıkarılamaz |
| Yaklaşık 9 günlük uptime | Uzun süredir çalışan bir sistem | Birikmiş swap'ın tamamının son yavaşlama sırasında oluştuğu |

CPU yüzdeleri çok iş parçacıklı süreçlerde 100'ü aşabilir. Apple Silicon'daki farklı çekirdek türleri ve değişen frekanslar nedeniyle “çekirdeklerin zaman ortalaması” ile “iş yapma kapasitesi” aynı ölçü değildir. [Apple: süreç CPU kullanımı](https://developer.apple.com/tutorials/instruments/identifying-a-hang), [Apple: yük ortalaması](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/getloadavg.3.html).

Bellek yorumunda macOS'un Memory Pressure göstergesi, kullanılan GB miktarından daha anlamlı bir başlangıçtır; swap hızı, boş bellek ve diğer bellek bileşenleri bu değerlendirmeye girer. Sanal adres alanının büyüklüğü doğrudan fiziksel tüketim değildir. Bu ekran için ilk inceleme adayım bellek baskısı/swap hareketi ile VS Code ve Claude uygulama ailelerinin zaman içindeki yükü olurdu; bu bir araştırma önceliği, teşhis değil. [Apple: bellek kullanımı](https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac), [Apple: tahsis ve bellek ayak izi](https://developer.apple.com/documentation/xcode/analyzing-the-memory-usage-of-your-metal-app).

**Asıl ihtiyaç üç ayrı soruyu cevaplamak.** Birincisi, sistemin şu an ne yaptığı: CPU, bellek, disk, ağ ve GPU. İkincisi, bu tüketimin hangi uygulamaya veya işe ait olduğu. Üçüncüsü, gözlenen tüketimin kullanıcının yaşadığı gecikmeyle ilişkisi. Birinci soruyu çoğu monitör cevaplar. İkinci soruda süreç gruplaması ve proje bilgisi gerekir. Üçüncü soru için süre, geçmiş, bekleme/baskı belirtileri ve mümkünse karşılaştırmalı ölçüm gerekir.

Yüksek kullanım her zaman sorun değildir: derleme sırasında çalışan CPU yararlı iş yapıyor olabilir. Düşük toplam CPU da sorunsuzluk kanıtı değildir: tek iş parçacığı, kilit, kısa süreli sıçrama veya uzak servis beklemesi gecikme yaratabilir. Kaynak başına kullanım, doygunluk/bekleme ve hata sinyallerini ayıran USE yaklaşımı bu ürünün teşhis mantığı için iyi bir temel sunar. [Brendan Gregg: USE yöntemi](https://www.brendangregg.com/usemethod.html).

**Bugün yeni ürün geliştirmeden de sadeleştirebiliriz.** Activity Monitor'da bellek sekmesinde Memory Pressure ve en büyük tüketicilere; CPU sekmesinde en yüksek tüketen birkaç uygulamaya bakmak ilk adım. View → All Processes, Hierarchically yardımcı süreçlerin ilişkisini görmeyi kolaylaştırır; bu görünümün kendisi her uygulamaya kusursuz bir toplam üretmez. Gereksiz sütunları gizlemek ve daha sık yenilemenin gerçekten gerekli olup olmadığını değerlendirmek okunabilirliği artırır. [Apple: süreç görünümleri ve sütunlar](https://support.apple.com/en-au/guide/activity-monitor/-actmntr1001/mac).

Menü çubuğunda yalnız CPU, bellek baskısı ve gerektiğinde disk/ağ etkinliği bırakılabilir. Ayrıntılar bir tıklamayla açılır; teknik süreç listesi ikinci seviyede kalır. Bu, kısa vadeli sadeleştirme önerisi. Geçmişteki olayları açıklamak ve proje sahipliğini bulmak için aşağıdaki daha kapsamlı adaylar gerekir.

**Mevcut araçların karşılaştırması.** “Sınır” sütunu aracın değersiz olduğunu değil, bu kullanıcı ihtiyacının hangi bölümünü ayrıca çözmek gerektiğini anlatır.

| Araç | Model ve platform | Bu ihtiyaçta güçlü olduğu yer | Sınır / değerlendirme |
|---|---|---|---|
| [Mac Performance Monitor](https://github.com/Zesty0wl/mac-performance-monitor) | Ücretsiz, MIT; macOS 15+, Apple Silicon | Sistem ve süreç geçmişini birlikte inceleme; uygulama grupları; olay incelemesi | Açık kaynak ilk deneme adayım. Güncel donanımda doğruluk ve kendi tüketimi ölçülmeli |
| [Vitals](https://vitalsmac.com/features/apps-not-processes) | Ticari; macOS 15+, Intel ve Apple Silicon | Helper'ları uygulama altında toplama; proje, port ve ajan bağlamı | En yakın ürün yaklaşımı adaylarından; yeni ürün, gruplama doğruluğu uygulamalı sınanmadı |
| [Stats](https://github.com/exelban/stats) | Ücretsiz, MIT; macOS 12+ | Menülerde özelleştirilebilir kaynak özeti | Sürekli göz ucuyla bakmak için uygun; neden-sonuç yorumunu kullanıcı yapar |
| [iStat Menus](https://bjango.com/mac/istatmenus/) | Ticari; güncel sayfada macOS 13.5+ | Geçmiş, en çok tüketen uygulamalar, bellek baskısı ve süreye bağlı bildirim kuralları | Çok sayıda modül açılırsa karmaşıklık geri gelir; 14 günlük deneme var |
| [iStatistica Pro](https://www.imagetasks.com/istatistica/pro/) | Ticari; macOS, Intel/Apple Silicon | Pencere tabanlı dashboard, uygulama CPU geçmişi | Bazı sensör ve süreç ayrıntıları ek eklenti ister; otomatik kök neden analizi doğrulanmadı |
| [btop](https://github.com/aristocratos/btop) | Açık kaynak, Apache-2.0; macOS/Linux ve diğer desteklenen sistemler | Terminalde grafikler ve süreç ağacı; güncel macOS sürümünde Apple Silicon GPU desteği | htop'tan daha görsel; yorumlama yükünün önemli bölümü sürer |
| [bottom](https://github.com/ClementTsang/bottom) | Açık kaynak, MIT; macOS/Linux/Windows | Özelleştirilebilir terminal grafikleri ve süreç görünümü | Platformlar arasında metrik kapsamı aynı değil; uygulama/proje teşhisi odak noktası değil |
| [Glances](https://glances.readthedocs.io/en/latest/) | Açık kaynak, LGPL-3.0; macOS/Linux/Windows | Terminal/web görünümü, eklentiler, dışa aktarım ve container izleme | Eşik uyarısı kök neden kanıtı değildir; sensör/GPU/I/O yetenekleri platforma göre değişir |
| [Netdata](https://learn.netdata.cloud/docs/collecting-metrics/collectors/operating-systems/macos) | Açık kaynak ajan ve ticari bulut seçenekleri | Sürekli zaman serileri, uyarılar; yerel makineyle sunucu/container ortamını birlikte değerlendirme | Tek Mac'te sade kullanım için daha büyük bir sistem; güncel macOS modülleri ayrı ayrı doğrulanmalı |
| [macmon — vladkens](https://github.com/vladkens/macmon) | Ücretsiz, MIT; Apple Silicon | CPU/GPU/ANE, güç ve sıcaklık; güncel sürümde süreç ayrıntıları da var | Terminal ve düşük seviye telemetri odaklı; özel macOS arayüzleri uyumluluk yükü getirir |
| [NeoHtop](https://github.com/Abdenasser/neohtop) | Açık kaynak, MIT; macOS destekli masaüstü arayüzü | Arama, filtreleme ve süreç sabitleme | Daha düzenli bir süreç listesi; açıklayıcı teşhis katmanı belgelenmiş değil |
| [Performance Monitor — inequitas](https://github.com/inequitas/performancemonitor/blob/v1.3.1/README.md) | Açık kaynak, MIT; macOS 14+, Apple Silicon | Uygulama/helper gruplama, sade durum cümleleri, süreç açıklamaları | Ad-hoc imzalı, notarizasyonu yok; dağıtım açısından bu somut sınır dikkate alınmalı |

NeoAsitop ve asitop'u da inceledik. Donanımın çalışma durumunu anlamaya yardımcı olabilirler; ancak güncel macOS/donanım uyumluluğu ve bakım kanıtları daha sınırlı olduğu için bu ihtiyacın ilk seçenekleri yapmıyorum. [NeoAsitop deposu](https://github.com/op06072/NeoAsitop), [asitop deposu](https://github.com/tlkh/asitop).

Linux için [Mission Center](https://missioncenter.io/) uygulama odaklı sunum; Windows için [System Informer](https://www.system-informer.com/index.php) geçmişteki bir zirveden ilgili sürece inme açısından yararlı referanslar. Bunlar macOS'a kurulacak alternatifler değildir. Netdata için güncel [süreç belgesi](https://learn.netdata.cloud/docs/live-view/processes) macOS gruplamasını kapsıyor; canlı süreç tablosu ile tarihçe grafikleri farklı yeteneklerdir.

**İlk adaylarda karar değiştiren ayrıntılar var.** Mac Performance Monitor'ın sitesinde sekiz çalışan/sonlanmış süreci ortak zaman çizelgesinde karşılaştırma, CSV dışa aktarım ve uyarıdan kanıta geçiş belgeleniyor. Site 2.0 bilgisini gösterirken GitHub'daki son kararlı sürüm 17 Ekim 2026 tarihli 2.4.0 build 289. Bu tutarsızlık nedeniyle kurulum sürümü için release kaydı esas alınmalı. [Ürün özellikleri](https://macperformancemonitor.com/), [2.4.0 sürümü](https://github.com/Zesty0wl/mac-performance-monitor/releases/tag/v2.4.0.289).

MPM'nin sürüme sabitlenmiş uyarı belgesi, sabit yüksek swap'ı tek başına alarm saymıyor; eksik veriyi iyileşme kabul etmiyor ve bellek büyümesini sızıntı kanıtından ayırıyor. Aynı belge bazı yeni kurallar için daha geniş canlı doğrulama gerektiğini de belirtiyor. Bu iyi bir açıklanabilirlik yaklaşımı; bizim tarafımızdan ölçülmüş alarm doğruluğu değil. [Uyarı kuralları ve doğrulama sınırı](https://github.com/Zesty0wl/mac-performance-monitor/blob/v2.4.0.289/docs/adaptive-alerts.md).

MPM'nin 0–100 pressure index'i uygulamanın hesapladığı bir birleşik göstergedir; Apple'ın doğrudan verdiği bellek baskısı yüzdesi gibi okunmamalı. Paylaşılacak raporlar da ad/yolları otomatik anonimleştirmiyor. Uygulama sandbox içinde değil; daha geniş süreç erişimi için opsiyonel yardımcı kullanıyor. Yerel ölçümleri dışarıdaki bir AI ajana açmak da ajanın sağlayıcısına veri aktarımıyla sonuçlanabilir. Temel kayıt ile bu ek paylaşım aynı karar değildir. [Gösterge tanımı](https://github.com/Zesty0wl/mac-performance-monitor/blob/v2.4.0.289/docs/pressure-index.md), [sürümün veri/paylaşım politikası](https://github.com/Zesty0wl/mac-performance-monitor/blob/v2.4.0.289/SECURITY.md).

Vitals'ın ilk halka açık sürümü 22 Eylül 2026; araştırma sırasında changelog'da 21 Ekim tarihli 1.8.1 vardı. Üç günlük denemesi bulunuyor. Fiyat ve para birimi sayfaya/bölgeye göre değiştiği için ödeme ekranı doğrulanmadan sabit bir TL veya yıllık toplam maliyet vermiyorum. [Sürüm geçmişi](https://vitalsmac.com/changelog), [lisans koşulları](https://vitalsmac.com/terms).

Vitals'ta “bir yıla kadar geçmiş” ifadesi bir yıl boyunca ayrıntılı süreç kaydı anlamına gelmiyor: FAQ uygulama/saat ilişkilendirmesini son iki günle sınırlandırıyor; eski tarihlerde sistem ölçümleri, ayrıca günlük uygulama özetleri var. Kayıt aralığı da saniyelik adli izleme değil. Yavaşlamanın hangi saniyede başladığını bulmak önemliyse bu fark denemede özellikle sınanmalı. [Geçmişin ayrıntıları](https://vitalsmac.com/features/history).

Vitals'ın tam sistem görünümü için yönetici yetkili yardımcı isteğe bağlı. AI plan kullanım özellikleri açılırsa mevcut araç oturum bilgilerini okuyup sağlayıcılara istek gönderiyor; bunlar temel kaynak izleme için gerekli değil. Mac App Store'daki Vitals Lite da tam sürümle aynı kapsamda değil. Bu yüzden ilk karşılaştırmada kaynak izleme özellikleriyle başlanmalı ve ek entegrasyonlar ayrı değerlendirilmelidir. Bunlar üreticinin beyanıdır; bağımsız güvenlik incelemesi yapılmadı. [Gizlilik ve izinler](https://vitalsmac.com/privacy).

**Kullanım senaryoları: kullanıcıya sunulması gereken sonuçlar.** P0 ilk sürüm/ilk araç değerlendirmesi için temel; P1 takip aşaması; P2 ancak ihtiyaç doğrulanırsa. Öncelikler benim önerimdir. Her satırdaki açıklama ve aksiyon bir ürün gereksinimi önerisidir, mevcut bilgisayarda gözlenmiş olay değildir.

| Öncelik ve senaryo | Kullanıcının sorusu | Gerekli kanıt | Anlaşılır sonuç ve sonraki adım |
|---|---|---|---|
| P0 · Anlık yavaşlama | “Şimdi neden ağırlaştı?” | Son birkaç dakikanın CPU, bellek baskısı, swap hareketi, I/O ve uygulama değişimleri | En güçlü aday, dayandığı zaman aralığı ve eksik kanıt; ilgili uygulamayı incelemeye götür |
| P0 · Uygulamanın toplam etkisi | “Claude/VS Code toplam ne tüketiyor?” | Uygulama kimliği, helper ilişkileri ve tutarlı metrikler | Tek uygulama satırı; açıldığında alt süreçler ve eşleştirme gerekçesi |
| P0 · Proje sahipliği | “Bu on tane node hangi projelere ait?” | Süreç başlangıcı, ebeveynler, çalışma dizini, portlar; gerektiğinde araç entegrasyonu | Proje → görev → süreç görünümü; belirsiz eşleşme açıkça işaretli |
| P0 · Bellek baskısı | “RAM gerçekten yetmiyor mu?” | Basınç/sıkıştırma eğilimi, swap-in/out farkları, uygulama ayak izi | Dolu ama sağlıklı bellek ile baskı altında çalışan sistem ayrı anlatılır |
| P0 · Yakın geçmiş | “Beş dakika önce neden takıldı?” | Sonlanmış süreçleri de içeren zaman damgalı kayıt | Aynı zaman ekseninde baskı, tüketiciler ve başlama/bitiş olayları |
| P0 · Müdahale etkisi | “Bir uygulamayı kapatınca düzeldi mi?” | Önce/sonra benzer iş yükü pencereleri ve kullanıcının gecikme ölçütü | Kaynak değişimi ile iş süresi/tepki değişimi ayrı gösterilir |
| P1 · Docker/VM | “Docker mı, içindeki hangi servis mi?” | Host VM ölçümleri + container kimliği, limitleri ve istatistikleri | VM'nin host etkisi ile servislerin guest tüketimi iç içe ama ayrı toplamlar |
| P1 · VS Code eklentisi | “Editörü hangi eklenti yoruyor?” | Extension Host/renderer ayrımı; VS Code'un kendi profiler bilgisi | Süreçten eklenti profiline geçiş; kanıt yoksa eklenti adı tahmin edilmez |
| P1 · Ajanın başlattığı işler | “Hangi ajan oturumu hangi test/sunucuyu açtı?” | Oturum kimliği, başlatılan komutlar ve sahiplik zinciri | Ajan → proje → iş → süreç; uygulama penceresi kapanmış olsa da işin sahibi korunur |
| P1 · Boşta kalan işler | “Kullanmadığım hangi işler hâlâ açık?” | Çalışma süresi, etkinlik geçmişi, dinlenen portlar ve bağımlılıklar | Aday işler listelenir; düşük CPU'nun “gereksiz” anlamına gelmediği korunur |
| P1 · Disk beklemesi | “SSD yüzünden mi takılıyor?” | Okuma/yazma hızı, mümkün olan gecikme/kuyruk belirtileri, süreç I/O farkları | Kapasite doluluğu ile I/O baskısı ayrı; salt MB/s ile darboğaz kararı yok |
| P1 · Ağ/uzak servis | “Bilgisayar mı yavaş, internet/API mi?” | Trafik, bağlantı ölçümleri; varsa istek süreleri ve uygulama logları | Yerel yük ile uzak cevap beklemesi ayrılır; düşük trafik sağlıklı ağ kanıtı sayılmaz |
| P1 · Isı/güç | “Isındığı için mi yavaşladı?” | İşletim sisteminin termal durumu, yük/frekans/güç ilişkisi | Sıcaklık tek başına throttling sayılmaz; yükü azaltınca değişim izlenir |
| P1 · Bellek büyümesi | “Bir uygulama belleği bırakmıyor mu?” | Aynı iş yükünde uzun dönem ayak izi; boşta kalma/iş bitişi ve tekrarlar | “Sürekli büyüme gözlendi” denir; leak kanıtı için profiler'a yönlendirilir |
| P2 · GPU/yerel model | “GPU mu CPU mu darboğaz?” | GPU etkinliği, bellek/termal sınırlar ve model/iş süresi | CPU düşükken GPU baskısının gizlenmemesi; bulut modeliyle yerel model ayrımı |
| P2 · Destek için paylaşım | “Bu yavaşlamayı başkasına nasıl göstereyim?” | Olay penceresi, ölçüm sürümü, anonimleştirilmiş tüketici bilgileri | Yalnızca seçili zaman aralığının yerel raporu; hassas komut/yollar ayıklanır |

VS Code örneğinde sistem monitörü yardımcı süreci gösterebilir; eklenti ayrımı için Process Explorer ve Extension Bisect gibi editörün kendi araçları gerekir. Bu, genel monitörün uygulama içi teşhis aracına iyi bir geçiş sağlaması gereken örneklerden biridir. [Microsoft: performans sorunları](https://github.com/microsoft/vscode/wiki/Performance-Issues), [Extension Bisect](https://code.visualstudio.com/blogs/2021/02/16/extension-bisect).

**Arayüzü dört kullanıcı sorusu etrafında kurardım.** “Şimdi” görünümü kısa bir durum cümlesi, kaynakların durumları ve en çok etkileyen birkaç uygulamayı gösterir. “Uygulamalar” görünümü karşılaştırılabilir satırlar ve açılabilir helper detayları sunar. “Projeler” görünümü portları, ajan oturumlarını, sunucuları ve container'ları işe göre toplar. “Geçmiş” görünümü aynı zaman çizelgesinde olayı ve tüketicileri karşılaştırır. Bu bir tasarım önerisi; kullanıcı tarafından onaylanmış ekran veya kullanılabilirlik sonucu değildir.

Üstte tek bir “sağlık puanı 73” kullanmam. Onun yerine ölçümün zamanını ve bilgi düzeyini açıklarım: “CPU yoğun; bellek baskısı normal”, “Bellek baskısı arttı; en büyük artış X uygulamasında” veya “Bu aralık için veri yok”. Tüketim sıralaması ile yavaşlamanın olası sebebi ayrı ifadeler olmalı. Kararsız satır sıralamasını durdurma/sabitleme ve “şu anı işaretle” kontrolü, sürekli oynayan rakamları okunabilir kılar.

Örnek açıklama, tamamen varsayımsal: “Son üç dakikada bellek baskısı yükseldi. X uygulamasının bellek ayak izi aynı aralıkta arttı. Swap çıkışı da hızlandı. İlişki güçlü; uygulamanın neden belleği büyüttüğü bilinmiyor. İlgili zaman aralığını aç.” Böyle bir cümle hem yardımcıdır hem kanıtın sınırını korur.

**Sıfırdan geliştirme için uygulanabilir sınır.** Kullanıcı canlı terminal + rapor komutlarını seçti. Bu nedenle ilk araştırmadaki SwiftUI pencere önerisi güncel yön değildir. Bağımsız toplayıcı, açık kurallı değerlendirme ve yerel geçmiş fikri korunabilir; aynı çekirdek terminal ekranına ve rapor komutlarına veri verir. Depolama ve dil ayrıntıları yeni tasarım taslağında öneri olarak belirlenir; burada uygulanmış mimari iddiası yoktur.

Akış: işletim sistemi/araç ölçümleri → zaman ve birim normalizasyonu → uygulama/proje eşleştirme → geçmiş kaydı → kural değerlendirmesi → açıklama ve kanıt bağlantısı. CPU ve sayaç tabanlı metrikler iki örnek arasındaki farktan hesaplanır. Süreç kimliği yalnızca PID değil, PID + başlangıç zamanı olmalı. Ölçüm alınamadığında sıfır yazılmamalı; erişim yok, desteklenmiyor, eski veri ve uyku boşluğu farklı durumlar olarak saklanmalı.

Bellek için RSS, fiziksel ayak izi ve sanal alanı birbirine karıştırmamak gerekir. Paylaşımlı sayfalar, sıkıştırma ve Apple Silicon birleşik belleği nedeniyle süreç RAM toplamını bütün sistem RAM'ine eşitmiş gibi sunmak yanlıştır. Apple kendi uygulamasının ayak izini okumak için proc_pid_rusage örneğini veriyor; bu, bütün süreçlere aynı erişim garantisi değildir. [Apple: bellek profilleme](https://developer.apple.com/videos/play/wwdc2022/10106/).

libproc ailesi güçlü bir macOS veri kaynağıdır; ancak Apple'ın ilgili başlığı değişebilen özel arayüzler uyarısı içeriyor. Hangi çağrının hangi SDK, kullanıcı yetkisi ve dağıtım biçiminde çalıştığı ayrı doğrulanmalı. “Hepsi kararlı public API, App Store'a kesin çıkar” varsayımıyla plan yapılmamalı. [Apple XNU libproc başlığı](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/libsyscall/wrappers/libproc/libproc.h).

| Veri alanı | Uygulanabilir yaklaşım | İlk sürümde korunması gereken sınır |
|---|---|---|
| CPU ve uygulama kimliği | Sayaç farkları; bundle kimliği, süreç ömrü ve ebeveyn ilişkileri | İlk örnekten hız üretilmez; aynı adlı her süreç aynı uygulama/proje sayılmaz |
| Bellek baskısı | İşletim sistemi olayları ve VM/swap sayaçları birlikte | Normal/uyarı/kritik olaylarından Activity Monitor'la aynı sayısal grafik türetildiği iddia edilmez |
| Süreç disk etkinliği | Süreçlerin birikimli okuma/yazma baytlarından hız hesaplama | Dosya başına gecikme veya fiziksel disk beklemesi aynı sayaç değildir |
| Ağ | Önce arayüz toplamları; süreç atfı ayrı özellik | Bağlantı listesi, uygulama başına byte veya HTTP cevap süresi değildir |
| Termal/GPU | Termal durum; donanım/OS destekliyorsa ek ölçümler | Sıcaklık, güç ve bütün süreçlerin GPU payları her Mac'te aynı API ile sağlanmaz |
| Docker | Seçilen yerel daemon üzerinden liste/istatistik adaptörü | Host VM etkisi ile guest/container değerleri genel toplama iki kez eklenmez |

Apple'ın [Dispatch bellek baskısı kaynağı](https://developer.apple.com/documentation/dispatch/dispatch_source_type_memorypressure) ve [NSRunningApplication](https://developer.apple.com/documentation/appkit/nsrunningapplication) bu temel katmanlar için dayanak sağlar. Süreç disk baytları [XNU resource tanımlarında](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/resource.h) bulunur; erişim ve karşılaştırılabilirlik yine çalışma sırasında doğrulanır. Süreç bazında ağ atfı için Apple DTS'nin anlattığı [Network Extension yolu](https://developer.apple.com/forums/thread/824751) ek izin/dağıtım ve kapsam çalışması gerektirir.

Docker Desktop'ın Linux VM'i ile içindeki container'ların muhasebesi farklıdır. CLI'nin bellekten cache çıkarma davranışı da API'nin ham değerlerinden farklı olabilir. Bu yüzden her yüzde ve toplamın hangi katmana ve tanıma ait olduğu yazılmalı. [Docker VMM](https://docs.docker.com/desktop/features/vmm/), [Docker stats tanımları](https://docs.docker.com/reference/cli/docker/container/stats/).

Toplayıcı için başlangıç önerisi pencere açıkken 1–2 saniye, arka planda 5–10 saniye aralık; pahalı ayrıntıları istek üzerine okuma. Bu aralıklar performans ölçümüyle ayarlanmalı. Polling aralığında başlayıp biten kısa süreçler kaçabilir; uyku/uyanma boşluklarını interpolasyonla gerçek ölçümmüş gibi doldurmamak gerekir. Varsayılan geçmişte tam komut argümanları ve ortam değişkenleri tutulmamalı.

**Bir teşhis cümlesinin kanıt düzeyi görünür olmalı.** Önerdiğim dört durum: ölçülen gerçek; zaman ilişkisine dayalı aday; karşılaştırmalı denemeyle desteklenen etki; veri yetersiz. Bir uygulamayı durdurunca iyileşme gözlemek güçlü destek sağlar ama eşzamanlı değişen başka işler varsa tek neden kanıtı sayılmaz. LLM ilk sürümün teşhis motoru olmamalı. Sonradan eklenirse yalnızca ölçülmüş sinyalleri ve kural çıktısını açıklamalı; eksik veriyi tamamlamamalı.

Bildirimler tek örneğe değil sürekliliğe, toparlanmaya ve olayın tekrarına göre çalışmalı. Aynı durum her örnekte tekrar bildirilmemeli. İlk sürümün varsayılan eylemi inceleme olsun; süreç sonlandırma, servis durdurma veya fan kontrolü ayrı ve kullanıcı tarafından başlatılan eylemler olarak tasarlansın. Boşta görünen bir veritabanı ya da dev server'ın kapatılmasının güvenli olduğu yalnızca CPU yüzdesinden anlaşılamaz.

**Kendi ürünümüzü doğrulama deneyi.** Normal geliştirme akışında bir temel kayıt, sonra bir derleme/test ve bir çoklu uygulama oturumu değerlendirilir. Gerçek yavaşlama olursa zaman işaretlenir; sırf test için sistemi zorla swap'e sürüklemek gerekmez. Yeni araç kurulmaz. Zaten mevcut işletim sistemi araçları sistem düzeyi için, varsa Docker'ın kendi istatistikleri container düzeyi için, uygulamanın mevcut profiler'ı iç nedenler için referans alınabilir. Aynı adı taşıyan ama farklı tanımlanan metrikler birebir eşitlik testine sokulmaz.

| Kabul ölçütü önerisi | Nasıl değerlendirilir? |
|---|---|
| 10 saniyede durum anlaşılır | Kullanıcı ana kaynak baskısını ve ölçümün güncelliğini doğru söyler |
| 30 saniyede ilgili uygulama/iş bulunur | Bilinen iş yükünün uygulama/proje eşleşmesi doğru çıkar; belirsiz olan tahmin edilmez |
| Geçmişteki olay bulunabilir | Önceden işaretlenmiş bir yavaşlama aralığına ve o aralığın süreçlerine ulaşılır |
| Yüksek ama sağlıklı kullanım panik üretmez | Derleme, önbellek ve sabit swap örnekleri yanlış kesin teşhis oluşturmaz |
| Ölçülemeyen veri gizlenmez | Yardımcı/izin olmadan ilgili alan “bilinmiyor” görünür |
| Monitör ölçümü bozmaz | Kendi CPU, RAM, disk yazımı ve pil etkisi pencere açık/kapalı ölçülür |
| Müdahalenin faydası ölçülebilir | Kaynak yüzdesinin yanında görev süresi veya kullanıcının gecikme ölçütü karşılaştırılır |

Kendi tüketimi için başlangıç mühendislik hedefi, pencere kapalıyken ortalama bir çekirdeğin %1'inden düşük CPU ve yaklaşık 100 MB altı bellek olabilir. Bunlar mevcut bir aracın ölçülmüş sonucu veya garanti değildir; kayıt kapsamı ve donanıma göre kabul bütçesi değişebilir. Sık süreç taraması, sensör sorguları ve per-process geçmişin disk yazımı ayrıca ölçülmelidir.

**Kapsam ve efor önerisi.** Deneyimli tek geliştirici, macOS önceliği ve temel özelliklerle sınırlı varsayımı altında: 3–5 iş günü veri/izin fizibilite deneyi; ardından yaklaşık 3–5 hafta kişisel MVP; buna ek 4–8 hafta daha geniş cihaz testleri, geçmiş/olay güvenilirliği, imzalı dağıtım ve toparlanma davranışı. Bunlar ölçülmüş takvim veya taahhüt değil, kapsam kararı için kaba mühendislik tahminidir. Proje/ajan entegrasyonları ve tüm süreçlere ağ/GPU atfı süreyi en çok büyüten kalemlerdir.

MVP'de sistem özeti, uygulama gruplama, bellek baskısı/swap hareketi, kısa geçmiş, “olayı işaretle” ve kanıtı bulunan süreçler için temel proje eşleştirmesi birlikte ele alınmalı. Temel proje eşleştirmesi çalışma dizini/komut yolu ve gerektiğinde kullanıcının verdiği proje etiketiyle sınırlanabilir; belirsiz işler atanmamış kalır. Docker ve ayrıntılı ajan oturumu entegrasyonu ikinci aşama; gelişmiş GPU/sensör ve uygulama içi teşhis bağlantıları ihtiyaç doğrulanınca eklenebilir. Çoklu işletim sistemi, uzaktan bulut filosu, otomatik temizlik ve her soruna kesin cevap veren AI ilk kapsamı gereksiz büyütür.

**Güncel yön.** Kendi ürünümüz sıfırdan geliştirilecek; seçilen biçim canlı terminal ekranı ve rapor komutları. Hazır araç kurmak veya mevcut bir projeyi fork etmek güncel talep değildir. Araştırmadaki kullanım senaryoları ve doğrulama sınırları ürün tasarımına girdi olarak kullanılacak.

Bu araştırma mevcut araçların özelliklerini ve teknik sınırları ortaya koyar; bu bilgisayardaki darboğazı saptadığını, ürünlerin doğruluğunu/pil etkisini ölçtüğünü veya önerilen arayüzün kullanıcıyla doğrulandığını iddia etmez.
