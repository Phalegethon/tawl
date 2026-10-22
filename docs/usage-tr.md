# TAWL

**Terminal Activity & Workload Lens** — macOS yükünü **uygulama, proje ve kullanım alanı düzeyinde** okumak için canlı terminal ve rapor aracı.

“Makine zorlanıyor mu?”, “Hangi uygulamalar kaynak tüketiyor?” ve “Yavaşlama sırasında ne değişti?” sorularını ölçüm zamanı, kapsam ve açıklamayla birlikte cevaplar. Enter süreç listesini, ikinci Enter seçili sürecin kanıtlarını ve önerilerini açar.

## Çalıştırma

Bu klasörde oluşturulan `tawl` ikilisi doğrudan çalışır; PATH'e kurulum gerekmez:

```sh
cd tawl
./tawl
```

Kaynak koddan yeniden derlemek için mevcut Xcode/Swift araçları yeterli:

```sh
make build
make test
```

Harici Swift paketi, Homebrew paketi, servis, web sunucusu veya yetkili yardımcı kurulmaz. İlk doğrulanan ortam **Apple Silicon, macOS 27.0.1, Swift 6.4**. Paket hedefindeki macOS 15 alt sınırı, o sürümde çalışmasının test edildiği anlamına gelmez. Linux/Windows desteği yok.

## Komutlar

```sh
./tawl status --sample 3s
./tawl status --json
./tawl watch --record ./oturum.tawl
./tawl record --duration 10m --output ./oturum.tawl
./tawl report ./oturum.tawl --last 5m
./tawl report ./oturum.tawl --json
./tawl --help
```

`status` kendi kısa örneklemesini yapar. `report` açıkça verilen dosyayı çevrimdışı okur; bilgisayarın o andaki yükünü yeniden ölçmez. `--last`, dosyanın son ölçümüne göre hesaplanır. Sürelerde `s`, `m`, `h` kullanılabilir; `status --sample` 0.1–10 saniye, kayıt süresi en fazla 24 saattir. `record` varsayılan süresi 60 saniyedir; dosya boyut sınırı daha erken durdurabilir.

## Canlı ekranda

| Kontrol | İşlev |
|---|---|
| ↑/↓ veya j/k | İş yükü veya ayrıntıda süreç seç |
| Enter | İş yükünde süreç listesi; süreçte değerlendirme ve öneriler |
| Tab | Uygulamalar → Projeler → Kullanım alanları |
| 1 / 2 / 3 / 4 / 5 | İş yükü adı / CPU / ayak izi / Δ bellek / üye sayısına göre sırala |
| Seçili 1–5 tuşuna tekrar veya r | Sıralama yönünü tersine çevir |
| 0 / s | Otomatik sıralama / sonraki sıralama alanı |
| o | Seçili iş yükünün yalnız öneri bulunan süreçlerini göster; tekrar basınca tüm süreçler |
| x | Süreç kapatma penceresini aç: aday seç, etkiyi incele, onayla |
| e | Son gönderilen kapatma isteğinin önce/sonra kaynak karşılaştırmasını aç |
| d (karşılaştırmada) | Grafikler ve değerlerle tek HTML raporu kaydet |
| a (kayıt sonucunda) | Kaydedilen raporu tarayıcıda aç |
| g | CPU çekirdekleri / GPU panelini göster veya gizle (açılışta açık) |
| [ / ] | Çok sayıda çekirdek/aygıt varsa donanım sayfasını değiştir |
| b | Bellek/swap odağı: uygulamaları ayak izine göre sırala, sistem swap'ını incele; tekrar basınca odağı kapat |
| / | Ad içinde ara; Enter uygula, Esc temizle |
| h, ardından ←/→ | Bu oturumun gerçek geçmiş ölçümleri |
| Space | Görüntüyü sabitle; toplama devam eder |
| m | Canlı zamana “yavaşlama” işareti ekle |
| PgUp/PgDn, Home/End | Uzun listelerde gezin |
| Fare tekerleği | Listede seçimi, değerlendirmede sayfa içi konumu kaydır |
| ?, Esc | Yardım / geri |
| q veya Ctrl-C | Çık; terminal ayarlarını geri yükle |

Minimum 80×24. Açılışta üstte CPU çekirdek grafikleri ve GPU aygıt toplamı bulunur; g ile CPU/bellek/disk/ağ özet grafiklerine dönülür. Donanım görünümünde bellek baskısı, swap, disk ve ağ bilgisi kısa özet satırında kalır. 120 sütundan itibaren seçili işin CPU/bellek geçmişi ve öne çıkan süreçleri sağ panelde açılır. Sayısal sütunlar sağa hizalanır; seçim tüm satır boyunca görünür.

Ayrıntıda her süreç tek satırdır: PID, ad, CPU, ayak izi, bellek değişimi ve yer varsa açık kalma süresi birlikte karşılaştırılır. Seçili sürecin değerlendirmesi geniş ekranda sağda, dar ekranda altta gösterilir. İkinci Enter, CPU ve ayak izi geçmişi ile gözlem sürelerini içeren grafik değerlendirmeyi açar. İlk görünümde kısa bir sonraki adım bulunur; ayrıntılı gerekçeler aşağıdadır. Geniş değerlendirme ekranında sistem swap bağlamı da gösterilir. Esc bir önceki düzeye döner. Ayrıntı listesinde **1–4** sıralama tuşları kullanılır; üye sayısı yalnız grup listesinde anlamlıdır.

Gözlem çubukları CPU için **30**, düşük etkinlik için **600 saniyelik** koşulun ne kadarının ölçüldüğünü gösterir; güven puanı veya sorun olasılığı değildir. `Kanıt yok` ve `?` eksik ölçümü, `0 sn` henüz birikmemiş veya kesilmiş süreyi belirtir. Kaynak ölçümü eksikken “eşik aşılmadı” sonucu çıkarılmaz.

Canlı arayüz terminal penceresinin iç alanını kullanır ve kabuk geçmişini koruyan ayrı ekran tamponunda çizilir. Fare tekerleği uygulama içinde gezinir; ekran yenilemeleri terminal geçmişine yeni satırlar eklemez. Çıkışta terminal giriş, imleç, satır sarma ve fare modları geri yüklenir. Terminal uygulamasının kendi kaydırma çubuğunu gizlemesi veya fare hareketini uygulamaya iletmesi terminalin desteğine/ayarlarına bağlıdır; TAWL kalıcı terminal tercihlerini değiştirmez.

CPU turkuaz, GPU mor, bellek sarı, disk mavi, ağ yeşildir. Yüksek tüketimde **ilgili sayısal alan** sarı/kırmızı olur; adın yanında `CPU!`, `RAM!` veya `Δ!` etiketi hangi kaynağın dikkat istediğini gösterir. `RAM!` bellek ayak izi uyarısıdır; fiziksel RAM yüzdesi değildir.

İnceleme eşikleri: CPU **≥1 çekirdek sarı, ≥2 kırmızı**; ayak izi **≥2 GiB sarı, ≥4 GiB kırmızı**; son ölçümde bellek artışı **≥100 MiB sarı**. Bunlar darboğaz veya sızıntı teşhisi değildir. Bellek baskısı geçmişinde `▁` normal, `▄` uyarı, `█` kritik ve `·` eksik ölçüm demektir. `NO_COLOR=1 ./tawl` renkleri kapatır; şekil, etiket ve sayılar anlamı korur. Ekran koyu terminal zemini için tasarlanmıştır.

Ana izleme ve süreç grafikleri son **en fazla 120 saniyenin örneklerini** gösterir; eşit süreli bir zaman ekseni değildir. Zaman aralığı üstte yazılır. Sütuna birden çok örnek sığarsa tepe değer, herhangi bir eksik varsa `·` çizilir; 5 saniyeyi aşan toplama boşlukları da işaretlenir. CPU sistem grafiği 0–100%; disk/ağ yönleri ortak otomatik ölçek kullanır. Seçili iş grafiklerinin otomatik ölçeği yanlarında yazılır. Uygulama satırındaki CPU çubuğu toplam mantıksal çekirdek kapasitesine, bellek çubuğu **o listedeki en büyük ayak izine** göredir; RAM doluluk oranı değildir.

Otomatik sıralama, bellek baskısı varken ayak izini, diğer durumda CPU'yu esas alır. Elle seçilen alan baskı değişince değişmez; başlıktaki ok sıralama yönünü gösterir. Bellek değişimi işaretli değere göre sıralanır; bilinmeyen ölçümler iki yönde de sonda kalır. Seçili işin kimliği sıralama sırasında korunur. Süreç kaybolursa eski değerler açıkça etiketlenir ve güncel kapatma önerisi üretilmez. Öneri filtresinde koşulları artık karşılamayan seçim görünür adayla değiştirilir; aday kalmazsa temizlenir. Uygulanan arama filtresi Enter sonrasında da görünür. Yönlendirilmiş çıktı için `status` veya `report` kullanın.

## CPU çekirdekleri ve GPU

**g** ile ana ekrandaki donanım alanını açıp kapat. Açılışta açıktır. Her CPU grafiği bir mantıksal işlemcinin meşgul zamanını gösterir; hepsi sabit **%0–100** ölçeğini kullanır. **E** verim, **P** performans çekirdeğidir; tür doğrulanamazsa **?** kalır. Yüzde iki okuma arasından hesaplanır. İlk örnek, uzun ölçüm boşluğu, topoloji veya sayaç sıfırlanması ölçülmemiş olarak gösterilir. **≥%80 sarı, ≥%95 kırmızı** yalnız yükü vurgular; otomatik darboğaz teşhisi değildir.

Bu Mac'te **12 CPU (4 E / 8 P)** ve **38 çekirdekli Apple M2 Max GPU** doğrulandı. GPU grafiği sürücünün yayımladığı **aygıt toplamıdır**; 38 sayısı donanım çekirdek sayısıdır. Tek tek GPU çekirdeklerinin kullanım yüzdesi bu kaynakta yoktur. Aynı yüzdeyi çekirdeklere kopyalamıyoruz ve “kaç GPU çekirdeği çalışıyor” sayısı türetmiyoruz. Ölçüm okunamazsa sıfır yerine — görünür. Ölçümler sistem genelidir; yalnız LLM işlemini ayırmaz. E/P yüzdeleri eşit işlem gücü anlamına gelmez.

80×24'te bu makinenin 12 CPU çekirdeği, GPU ve en az altı uygulama satırı birlikte görünür. Daha fazla çekirdek/aygıtta **[ / ]** ile sayfa değişir; sayfa kapsamı başlıkta gösterilir. Space ve h, donanım grafiklerini de aynı sabit/geçmiş ana bağlar. Eski kayıtlarda donanım alanları yoksa ölçüm bulunamadığı belirtilir; yeni kayıtlar bunları isteğe bağlı alanlar olarak taşır.

LLM yükünü incelerken önce boşta durumu, ardından model yükleme ve yanıt üretimi sırasındaki CPU/GPU grafikleri ile bellek baskısını karşılaştır. GPU yüzdesi, token/s veya GPU belleği değildir. Teknik kaynaklar ve sınırlar [CPU/GPU ölçüm notunda](research/2026-10-22-hardware-telemetry.md).

## Sayılar ne anlama geliyor?

| Alan | Sözleşme |
|---|---|
| Sistem CPU % | İki okuma arasındaki toplam CPU sayaçlarından hesaplanan kapasite yüzdesi |
| Uygulama CPU çekirdek | Süreçlerin CPU zaman farkı / geçen süre. **1.00 = bir mantıksal çekirdek**; 100% makine kapasitesi değildir. P/E çekirdeklerinin performansı eşit varsayılmaz, bu zaman eşdeğeridir. |
| Bellek ayak izi | macOS `ri_phys_footprint`; aynı gruptaki görünen süreçler toplanır. RAM yüzdesi veya kapatınca kesin boşalacak miktar değildir. Sıkıştırılmış bellek ve muhasebe nedeniyle uygulama toplamlarını fiziksel RAM kapasitesiyle eşitlemeyin. |
| Δ bellek | Aynı PID + başlangıç zamanına ait sürecin son geçerli aralıktaki değişimi; süreç eklenmesi/çıkması ayrı bir etkidir. Eksik üye farkları tam grup büyümesi sayılmaz. |
| Bellek baskısı | İşletim sisteminin normal / uyarı / kritik sinyali. Okunamazsa “ölçülemedi”. |
| Swap ve swap hareketi | Diskte tutulan toplam swap ile aralıktaki swap-in/out ayrı metrikler. Hızlar sayfa sayaçlarından türetilir; SSD'ye yazılan fiziksel bayt miktarı değildir. Büyük fakat hareketsiz swap tek başına darboğaz kanıtı değildir. |
| Disk hızı | Sayaç yayımlayan fiziksel IOKit blok sürücülerinin okuma/yazma hızları. Sanal disk görüntüleri dışlanır. Gecikme, kuyruk, dosya veya uygulama bazında neden ölçümü değildir. |
| Ağ hızı | `en*` Ethernet/Wi-Fi arayüzleri; loopback, tüneller, sanal köprüler ve başka isimlerdeki arayüzler dışarıda. Uygulama bazında ağ dağılımı yok. |
| Açık kalma süresi | İşletim sisteminin süreç başlangıcından ölçüm anına kadar geçen süre. Kullanıcının en son ne zaman kullandığını göstermez. Okunamıyorsa veya eski kayıtta bulunmuyorsa bilinmez. |
| `?`, `—`, `*` | Bilinmeyen/henüz hesaplanmayan değer veya kısmi toplam; sıfır değildir. |

İlk örnek yalnız baz çizgisidir. Sayaç sıfırlanması, süreç kimliği değişmesi, aygıt değişimi ve 15 saniyeyi aşan ölçüm boşluğu hızların yeniden kurulmasına yol açar. Çok kısa ömürlü işler iki ölçüm arasında kaçabilir. Temel örnekleme aralığı 2 saniyedir; tek bir okuma atomik sistem anlık görüntüsü değildir.

## Gruplama ve yorum

- İç içe yardımcı `.app` süreçleri dış uygulamanın altında birleştirilir. Uygulama dışındaki çocuklarda canlı ebeveyn zinciri kullanılabilir. Eşleşmeyen süreç çalıştırılabilir dosya kimliğine, o da okunamazsa kendi yaşam kimliğine bağlanır. Kullanıcıya görünen VM veya çok kiracılı yardımcıların gerçek sahibi her zaman belirlenemez.
- Proje için okunabilen çalışma dizininden, sınırlı sayıda üst dizinde `.git`, `package.json`, `Package.swift`, `pyproject.toml`, `go.mod` veya `Cargo.toml` aranır. Monorepo alt paketi en yakın işaretle eşleşebilir. Argüman/ortam taranmaz; komut başka dizinde çalışmışsa doğru proje bulunamayabilir. Kanıt yoksa “projesi belirlenemeyen” grubunda kalır.
- Kullanım alanları projeden bağımsızdır: **Tarayıcılar, Geliştirme, Yapay zekâ, İletişim, Sanallaştırma, Veritabanları, Medya, Sistem, Diğer**. Bilinen uygulama/süreç adları kullanılır; tanınan uygulamanın yardımcıları aynı alanda kalır. Belirsiz uygulamalar Diğer'e gider. Bu sınıflama uygulamanın genel alanıdır, o anda hangi işi yaptığının tespiti değildir; bu sürümde kullanıcı tanımlı kategoriler yoktur.
- Bellek baskısı doğrudan gözlem olarak açıklanır. Sistem CPU bulgusu en az 30 saniyelik kesintisiz ölçümlerde her örneğin %85 üzerinde olmasını gerektirir. Süreç düzeyindeki öneri eşikleri aşağıda ayrıdır.
- “En büyük tüketici” kök neden demek değildir. Bellek sızıntısı teşhisi, GPU/ısı kısıtlaması, SSD gecikmesi ve ağ gecikmesi teşhisi bu sürümde yok. Daha az CPU her zaman daha hızlı uygulama anlamına gelmez.

## Süreç önerileri

Seçili işte `o`, inceleme önerisi bulunan süreçleri ayırır. Öneriler yalnız sahipliği ve uygulama uygunluğu doğrulanan süreçlerde üretilir. Sistem, veritabanı ve sanallaştırma servisleri için kaynak uyarıları gösterilir; kapatma önerisi verilmez.

- **Sürekli CPU:** en az 30 saniye kesintisiz ≥1 çekirdek. Derleme veya beklenen bir iş olabileceği belirtilir.
- **Bellek baskısı:** sistem baskısı varken süreç ayak izi ≥2 GiB. Büyük tüketim kesin neden veya kapatınca kazanılacak RAM olarak sunulmaz.
- **Uzun süredir açık, düşük etkinlik adayı:** süreç yaşı ≥2 saat ve kesintisiz 600 saniye boyunca bilinen CPU <0.02 çekirdek, disk okuma ve yazma ayrı ayrı <1 KiB/sn, ayak izi ≥256 MiB. Eksik ölçüm, süreç kimliği değişmesi veya ölçüm boşluğu süreyi keser. Pencere/klavye etkileşimi ve süreç bazında ağ etkinliği ölçülmediği için **“kullanılmıyor” sonucu çıkarılmaz**.

Önce uygulamadaki işi/sekmesini kontrol edip çalışmalarını kaydet. **x**, ana listeden, süreç listesinden ve değerlendirmeden **Süreç kapatma** penceresini açar. Ana listeden açıldığında seçili işin adayları öne gelir; süreç ayrıntısından açıldığında seçtiğin süreç korunur. Pencere açmak ve listede gezinmek istek göndermez.

1. **↑/↓** ile süreci seç. **Tab**, seçili işin tüm süreçleri ile bütün uygulamalardaki öneriler arasında geçer.
2. **Durum** sütunu **ÖNERİ**, **MANUEL** veya engeli gösterir. Otomatik öneri yoksa da kendi doğrulanmış uygulama sürecini MANUEL olarak seçebilirsin. Altta etkilenecek uygulama, tek PID kapsamı ve gerekçe görünür. Sahiplik doğrulanamıyorsa veya süreç korunuyorsa neden burada açıklanır. **Toplam uygulama belleğinin yüksek olması her alt sürece otomatik öneri üretmez; öneri bulunmaması tek başına kapatmayı engellemez.**
3. **Enter veya i**, adayın etki/onay penceresini açar. Burada uygulama, PID, süreç adı, öneri ve olası veri kaybını incele. Varsayılan **Vazgeç**tir; **→ veya Tab** ile “Sonlandırma isteği gönder”i seçip **Enter veya Space** ile onayla. Uzun etki bilgisi varsa önce aşağı kaydırarak tamamını gör.
4. **Esc**, onaydan süreç kontrolüne; tekrar Esc önceki izleme ekranına döner. Yerel doğrulama veya yetki hatası kontrol penceresinde kalır; denenen süreç kırmızı **ENGELLİ** görünür ve Enter/i yeniden denemeyi sağlar. Terminalin üst süreç zinciri okunamıyorsa bu durum hedef sürecin korunduğu iddiasından ayrı açıklanır. Geçmiş/sabit bağlamda canlı ölçüme dönüş tuşu belirtilir.

Enter terminalinde tepki vermiyorsa aynı akışı **x → i → sağ ok → Space** ile kullanabilirsin. i yalnız incelemeyi açar; Space seçili düğmeyi uygular ve varsayılan seçim Vazgeç olarak kalır.

İstek kabul edilince kaynak karşılaştırması açılır. **Esc** ile kontrol penceresine dönebilir, **e** ile aynı karşılaştırmayı tekrar açabilirsin. `o` eski süreç listesinde öneri filtresini kullanmaya devam eder.

İstek yalnız seçili sürece **SIGTERM** gönderir. Bu, uygulamanın normal Quit menüsü değildir: kayıt diyaloğu açılmayabilir, kaydedilmemiş değişiklikler kaybolabilir ve bağlı sekme/pencere/işler ya da uygulamanın tamamı etkilenebilir. Diğer üyelere doğrudan sinyal gönderilmez. Otomatik tekrar, toplu kapatma veya SIGKILL yoktur.

Onay **30 saniye** geçerlidir. Enter anında yeni ölçüm alınır; sahiplik doğrulanmalı, süreç ve uygulama aynı kalmalıdır. Önerinin azalması veya kaybolması, açıkça seçilmiş hedefe verilen onayı değiştirmez; öneri ve kapatma uygunluğu ayrı kontrollerdir. İşletim sisteminden alınan audit-token, başlangıç zamanı, çalıştırılabilir dosya ve kullanıcı kimliği tekrar doğrulanır. macOS gerekli kimliği vermiyorsa işlem engellenir; daha zayıf PID-only yönteme geçilmez. TAWL, üst süreçleri, sistem/veritabanı/VM hizmetleri ve başka kullanıcılara ait süreçler korunur. Geçmiş ve sabit görüntülerden kapatma yapılmaz.

**İstek gönderildi**, **çıkış doğrulandı**, **hâlâ çalışıyor**, **kimlik değişti** ve **sonuç doğrulanamadı** ayrı gösterilir. Yardımcı süreç uygulama tarafından yeniden açılabilir; tek sürecin çıkışı uygulamanın tümünün kapandığını göstermez. Ayrıntılar [süreç kapatma güvenliği](research/process-control-safety.md) notunda bulunur.

Terminal bracketed-paste destekliyorsa yapıştırılan metin komut olarak işlenmez; onay için tuşları kullan. Öncelik değiştirme, RAM temizleme veya sistem ayarına müdahale yoktur.

## Kapatma öncesi ve sonrası

Onaylanan **SIGTERM isteği kabul edilince** karşılaştırma otomatik açılır. İstekten **önceki 30 saniye** sabitlenir, sonraki **60 saniye** ölçülür. Üstte uygulama/PID, istek zamanı ve sürecin ayrı kapanma sonucu görünür. Dört grafik en küçük 80×24 ekranda da birlikte okunur:

- **Sistem CPU:** iki dönemin süre ağırlıklı ortalamaları ve yüzde puan farkı; sabit 0–100% ölçek.
- **Bellek baskısı:** normal/uyarı/kritik seyri ve iki dönemin son geçerli durumu. Kategorilerden sayısal ortalama üretilmez.
- **Swap stoku:** diskte tutulan son miktarlar ve fark. Küçük değişimi görünür kılan ortak yakınlaştırılmış ölçek açıkça yazılır.
- **Swap yazımı:** RAM→disk hareketinin süre ağırlıklı ortalaması. Swap miktarı aynı kalırken yeni yazımın durduğu görülebilir.

Bu ekranın zaman ekseni **eşit süreli ve sabittir: −30…+60 saniye**; dikey çizgi istek anıdır. Nokta eksik ölçümü, boş alan henüz gelmemiş zamanı, taban çizgisi ölçülmüş sıfırı gösterir. CPU/yazım için gerçek kapsanan süre belirtilir; eksik geçmiş tam 30 saniye sayılmaz. İstek sınırını aşan hız aralığı sonraki dönemin ortalamasına katılmaz. Beş saniyeden eski veya okunamayan son baskı/stok bilinmeyen kalır.

**Esc/Enter** ile normal ekrana dönsen de ölçüm sürer; **e** aynı raporu açar. 60 saniyede sonuç sabitlenir. Yalnız son kabul edilmiş isteğin raporu oturum belleğinde tutulur; iptal veya reddedilen yeni onay raporu değiştirmez. Yeni onay hazırlanırken önceki hedefin native izleme kimliği bırakılır; eski kapanma sonucu henüz kesinleşmediyse doğrulanamadı olarak kalır. Otomatik disk kaydı yoktur; d ile dışa aktarmadığın rapor araç kapanınca kaybolur.

Grafikler **sistemde gözlenen değişimi** gösterir; başka işler de çalıştığı için kapatmanın kesin nedensel etkisi sayılmaz. Swap farkı kesin boşalan RAM değildir ve swap'ın sıfırlanacağı süre tahmin edilmez.

## Grafik raporu dosyaya aktarma

Karşılaştırma ekranında **d**, o anki raporu çalıştırdığın dizindeki **raporlar/** klasörüne tek `.html` dosyası olarak kaydeder. Kayıt penceresinde **tam dosya yolu** görünür; **a** tarayıcıda açar, **Esc/Enter** karşılaştırmaya döner. Yazma hatasında **d** aynı ekrandan yeniden dener.

Dosya şunları içerir: hedef/kapanan süreç adı ve PID, etkilenen uygulama, istek ve dışa aktarma zamanı, doğrulanmış veya belirsiz kapanma sonucu, önce/sonra değerleri ve farkları, kapsanan ölçüm süresi, **CPU/bellek baskısı/swap miktarı/swap yazımı için dört SVG grafik**. Sistem kaynaklarının değişimi süreç bazında kesin kazanç olarak gösterilmez.

60 saniye dolmadan kaydedersen dosya **Kısmi rapor** olarak işaretlenir. Dosya kendiliğinden güncellenmez; daha sonra d ile yeni bir kopya alabilirsin. Her dosyanın adı benzersizdir; önceki raporun üzerine yazılmaz. Grafikler ve stiller dosyanın içindedir: internet, web sunucusu veya başka bir program kurulumu gerekmez. Tarayıcının yazdır menüsünden PDF olarak da kaydedilebilir.

Dosya 0600, yeni raporlar dizini 0700 izinle oluşturulur; mevcut dizinin izinleri değiştirilmez. Rapor uygulama/süreç isimlerini ve PID'yi içerir; paylaşmadan önce içeriğine bak. Bu HTML çıktısı ayrı bir belgedir; `.tawl` oturum kaydının yerine geçmez.

## Bellek ve swap odağı

`b`, aramayı temizleyip uygulamaları büyük ayak izinden küçüğe sıralar. Yan panelde veya dar ekrandaki özet bölümünde **diskte tutulan swap**, **RAM → disk yazımı** ve **disk → RAM okuması** ayrı gösterilir. Stok ve hızların kendi ölçekleri vardır; okuma hızı, swap stokunun aynı miktarda azalacağı anlamına gelmez. Son en fazla 120 saniyelik kesintisiz stok farkı gözlemdir; swap'ın ne zaman biteceğine dair tahmin değildir.

Görünüm yazım, okuma, aktarım yok ve ölçüm bilinmiyor durumlarını ayırır. Baskı veya güncel yazım varsa amaç gereksiz işi normal kapatıp **bellek baskısının ve yeni swap yazımının azalıp azalmadığını karşılaştırmaktır**. Baskı normal ve yazım yokken sırf birikmiş swap yüksek diye uygulama kapatmak önerilmez.

Süreç başına swap payı ölçülmez. Listenin başındaki uygulama kesin swap nedeni sayılmaz; ayak izi kapatınca boşalacak GiB veya swap'ın azalacağı süre olarak sunulmaz. Swap temizleme, `purge`, `swapoff` ya da yeniden başlatma işlemi yapılmaz. Ölçüm sınırları ve dayanakları [swap araştırma notunda](research/2026-10-22-swap-evidence.md) açıklanır.

## Geçmiş, kayıt ve mahremiyet

Varsayılan geçmiş yalnız araç belleğindedir: **son 30 dakika veya tahmini 64 MiB kayıt bütçesi**. Bu bütçe JSON boyutu + giriş payına dayanır; gerçek RSS üst sınırı değildir. Ekran saklanan pencerenin başlangıç/bitişini gösterir. Araç başlamadan önceki olayların kaydı yoktur.

SABİT ve GEÇMİŞ görünümü, canlı geçmiş temizlense de gösterdiği grafiği korur. Her sabitlenen pencere ayrıca en fazla 120 saniye/8 MiB kodlanmış geçmiş tutar; seçili tek ölçüm bu bütçeyi aşıyorsa o ölçüm tek başına korunur. Bu sınır da gerçek RSS sınırı değildir. Moddan çıkınca ilgili geçmiş bırakılır.

Canlı öneriler için tam geçmişten ayrı, küçük bir süre özeti tutulur: yalnız mevcut süreç kimlikleri, son kaynak ölçümü ve 30/600 saniyeyle sınırlı süreler. Böylece tam örnekler bütçeden dolayı silinse de kesintisiz etkinlik kanıtı korunur; çıkan süreç veya ölçüm boşluğu bu kanıtı sıfırlar. Canlı görüntü sabitlenirken ona ait kanıt da korunur. Başka bir geçmiş ölçümüne geçildiğinde daha sonraki ölçümlerin kanıtı kullanılmaz.

Disk kaydı sadece `--record` / `record --output` ile başlar. Dosya 0600 izinle özel oluşturulur, mevcut dosya veya hedef sembolik bağ üzerine yazılmaz. **100 MiB** sınırında kayıt açık hata ile durur. Dosyalar otomatik silinmez. Çok süreçli bir Mac'te sınır 10 dakikadan önce gelebilir; bu sürüm tüm görünür süreçleri her örnekte kaydeder.

Kayıt biçimi sürüm 1 NDJSON'dur. Yeni kayıtlar `tawl` biçim kimliğini kullanır; dosya uzantısı olarak `.tawl` önerilir. Okuyucu eski `nabiz` biçim kimliğini ve `.nabiz` kayıtlarını da destekler; eski dosyaları yeniden adlandırmak gerekmez.

Süreç yaşı ve kullanıcıya ait uygulama olduğuna dair uygunluk bilgisi isteğe bağlı alanlardır; eski kayıtlarda bulunmadıklarında bilinmeyen kabul edilir ve kapatma önerisi üretilmez. Tam yollar, çalışma dizini, komut argümanları, ortam değişkenleri ve ağ uç noktaları yazılmaz. Uygulama/proje/süreç adları ve PID'ler bulunur; **kayıt anonim değildir**. Yerel kimlik özetleri kriptografik anonimleştirme sağlamaz. Ölçüm verileri dışarı gönderilmez. Canlı ekran açılışında yeni sürüm için GitHub yayın bilgisi arka planda, günde en çok bir kez istenir; TAWL_NO_UPDATE_CHECK=1 veya --no-update-check bu isteği kapatır. JSON rapor aynı hassasiyetle ele alınmalıdır.

Okuyucu dosya/satır boyutunu ve sayıları doğrular; bozuk ara satır veya desteklenmeyen sürümü reddeder. Yarım kalmış son satır, uyarı verilip tamamlanmış önceki bölüm okunarak kurtarılabilir. Monotonik zaman sırası bozulmuş dosya reddedilir; sistem saatinin düzeltilmesi süre hesabını değiştirmez.

## Geliştirme yapısı

`CTawl` yerel sayaçlar ve terminal köprüsüdür. `TawlCore` ölçüm farklarını, sahipliği, yorumları, geçmişi ve terminal sunumunu taşır. `Tawl` komut satırını bağlar. `RawReading` içindeki yollar yalnız bellekte kalır; kalıcı biçim `Snapshot` modelidir.

Terminal çizimi alternatif ekran tamponu ve mutlak satır konumlandırması (CUP) kullanır; satır sonu LF göndermez, otomatik satır sarmayı oturum boyunca kapatır. SGR ve eski X10 fare bildirimlerinde dikey tekerlek desteklenir. Çıkışta desteklenen kayıtlı modlar geri alınır; bu, terminal uygulamasının kaydırma çubuğu görünürlüğüne dair garanti değildir.

[Araştırma ve use case'ler](research.md) · [Ürün kapsamı](../PRODUCT.md) · [Kurulum ve güncelleme](../README.md)
