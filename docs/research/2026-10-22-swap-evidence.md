# Swap değerlendirmesi: ölçüm ve yorum sınırı

22 Ekim 2026. Bu not uygulamanın neden süreç başına “swap suçlusu” veya boşaltılacak GiB tahmini göstermediğini açıklar.

## Doğrulanan kaynaklar

- [Apple Activity Monitor — bellek kullanımı](https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac): bellek baskısı serbest bellek, swap hızı, wired ve dosya önbelleği birlikte değerlendirilerek belirlenir. Swap Used başlangıç diskinde kullanılan alan; Compressed ayrı bir ölçümdür. Uygulama başına VM Compressed görüntülenebilir, ancak bu swap dosyasındaki byte payı değildir.
- [Apple Activity Monitor — RAM gereksinimi](https://support.apple.com/guide/activity-monitor/check-if-your-mac-needs-more-ram-actmntr34865/mac): boş belleğin fazlalığı otomatik performans artışı değildir; yeşil baskı verimli kullanım anlamına gelir. Bu nedenle ürünün hedefi swap'ı sıfırlamak değildir.
- [Apple XNU `vm_statistics.h`](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/vm_statistics.h): sistem `swapins`/`swapouts` sayaçları compressor segmentleri üzerinden taşınan sayfaları sayar. Nabız bu sayaç farklarını sayfa boyutu ve süreyle dönüştürür. Bunlar süreç ataması veya SSD üzerindeki gerçek fiziksel yazma byte sayısı değildir.
- [Apple XNU `resource.h`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/resource.h): mevcut `proc_pid_rusage` tabanlı toplayıcının kullandığı yapı ayak izi, resident/wired, page-ins ve disk I/O alanlarını sunar. Bu alanlarda süreç başına güncel swap byte payı yoktur; page-ins'i swap diye yeniden etiketlemek doğru değildir.
- [Apple XNU `task_info.h`](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/task_info.h): `task_vm_info` sıkıştırılmış bellek ve footprint gibi alanlar içerir. Bu veri modeli de doğrudan “şu süreç sistem swap'ına neden oldu” kanıtı değildir. Bu değişiklik başka süreçlerin task portlarına erişmeye veya yeni yetki almaya çalışmaz.
- [Apple Virtual Memory System, arşiv](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/ManagingMemory/Articles/AboutMemory.html): paging-in, swap arka deposundan veya dosyadan gelebilir; paging-out sistemin seçtiği etkin olmayan sayfaları taşıyabilir. Kaynak 2013 tarihlidir; güncel compressor uygulamasının ayrıntıları için değil, sayfa sahipliği ile baskıya yol açan tahsisin aynı şey olmadığını açıklayan mekanizma için kullanılır.

## Ürün çıkarımı ve karar

Bir uygulamanın belleğinin swap'a taşınması, baskıyı başlatan uygulamanın o olduğunu kanıtlamaz. Başka bir uygulamanın tahsisi sistemin öncekinin sayfalarını seçmesine yol açabilir. Büyük ayak izi de nedensellik kanıtı değildir. Bu bir mekanizma çıkarımıdır; ürün kesin süreç ataması yapmaz.

Bellek odağı mevcut uygulama listesini ayak izine göre sıralar; bellek büyümesi ve doğrulanmış düşük etkinlik ayrıca incelenebilir. Sistemde baskı veya güncel swap yazımı varsa kullanıcıya gereksiz iş/sekmesini kaydedip normal kapatma, ardından baskı ve yazma hızını karşılaştırma önerilir. Uygulamanın ayak izi kazanılacak RAM veya azalacak swap miktarı olarak sunulmaz. Kapatma, purge, swapoff veya yeniden başlatma işlemi yürütülmez.

`assessSwap` son aralıkta yazma, okuma, aktarım yok veya bilinmiyor ayrımı yapar. Yalnız iki hız da biliniyor ve sıfırsa “aktarım yok” denir. Son en fazla 120 saniyelik kesintisiz stok değişimi gözlem olarak gösterilebilir; eksik veri, zaman atlaması veya tarihsel kareden sonraki örnekler bu kanıtı uzatmaz. Değişimin hızıyla “kaç dakika sonra swap boşalır” hesaplanmaz.

Süreç değerlendirmesi grafiklerine eklenen süre alanları da aynı kanıt kuralını korur: bilinmeyen süre `nil`, uygun fakat yeni/kesilmiş gözlem `0`, doğrulanmış süre CPU için 30 ve düşük etkinlik için 600 saniyede sınırlanır. Sistem/VM/veritabanı ve sahipliği doğrulanmamış süreçler kapatma önerisi dışında kalır.
