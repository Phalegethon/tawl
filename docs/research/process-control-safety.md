# Onaylı süreç kapatma — yerel güvenlik sınırı

22 Ekim 2026. Yalnız kullanıcı tarafından seçilmiş, sahipliği ve uygulaması doğrulanmış tek bir süreç için uygulanır. Toplu kapatma, süreç ağacına sinyal, `SIGKILL`, yetki yükseltme veya arka planda otomatik kapatma yoktur.

## Kimliğe bağlı işlem

Swift katmanı canlı ve taze ölçümü, sahipliği, uygulama kimliğini ve açık onayı doğrular. C katmanı hazırlık sırasında PID, işletim sistemi başlangıç zamanı, kullanıcı, üst süreç, çalıştırılabilir yol ve audit token saklar. Yolun uygulama ailesi onay ekranındaki uygulama ile yeniden eşleştirilir. Hazırlık 30 saniye geçerlidir ve tek kullanımlıktır; her gönderme girişimi onu tüketir.

Gönderim öncesinde yerel bilgiler tekrar okunur. Kimlik, sahiplik, yol veya üst süreç değişirse istek reddedilir. Son çağrı `proc_signal_with_audittoken(..., SIGTERM)` kullanır. PID sayısına gönderim yapan `kill(pid, ...)` yedeği yoktur. Audit token okunamazsa işlem kapalı kalır.

Standart macOS SDK başlıklarındaki `task_name_for_pid` ve `task_info(TASK_AUDIT_TOKEN)` ile alınan token, uygulamanın PID neslini de taşır. XNU kaynak kodunda `proc_find_audit_token` süreç referansını alırken PID neslini doğrular; böylece eski PID'nin başka bir sürece verilmesi ve aynı PID ile yeni yürütülebilir başlatılması eski onayı yeni hedefe yönlendirmez. [Apple XNU süreç kimliği](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_proc.c), [audit token okuma](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/task.c)

`proc_signal_with_audittoken` sıfırda başarı, hatada errno değeri döndürür. `proc_terminate` ve `proc_terminate_with_audittoken` kullanılmaz: işletim sistemi ani sonlandırmaya uygun gördüğü süreçler için `SIGKILL` seçebilir. Burada sinyal açıkça `SIGTERM` olarak sabittir. [Apple libproc sarmalayıcısı](https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.c), [XNU sinyal ve terminate ayrımı](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/proc_info.c)

## Korunan hedefler

PID 0/1, Nabız'ın kendisi ve üst süreç zinciri; root, başka kullanıcı veya değiştirilmiş yetkiler; işletim sistemi yolları ve sistem süreçleri; doğrulanamayan uygulama yolları kapatılmaz. Bilinen veritabanı ve sanallaştırma süreçleri hem ürün sınıflandırmasında hem yerel yol denetiminde korunur. Sınıflandırma bütün yazılımları kusursuz tanıdığı iddiasında değildir. Terminal katmanı öneri olmasa da uygun uygulama sürecinde MANUEL seçime izin verir. Öneri bulunması kapatma yetkisinin yerine geçmez; önerinin kaybolması açık seçimi iptal etmez. C API tek başına bir öneri motoru değildir.

## Sonuç ve sınırlar

Sinyalin kabul edilmesi, sürecin kapandığı anlamına gelmez. Ayrı, salt okunur kontrol aynı kimliğin hâlâ çalıştığını, çıktığını, değiştiğini veya okunamadığını bildirir. Zombie süreç çıkmış sayılır. PID aynı kalıp program değişmişse “kimlik değişti” sonucu alınır; bu uygulamanın tamamının kapandığını kanıtlamaz.

`SIGTERM`, macOS uygulama menüsündeki Çık komutu değildir; uygulamanın kaydetme sorusu göstereceği garanti edilmez. Kaydedilmemiş işler kaybolabilir. Bir yardımcı süreç kesilince sekme, pencere veya uygulamanın tamamı etkilenebilir; uygulama süreci yeniden başlatabilir. Süreç sinyali yok sayabilir. Araç zorla sonlandırmaya geçmez.

## Doğrulama

- `sh Tests/Native/test_process_control.sh`: yalnız kendisi oluşturduğu, 20 saniyelik failsafe içeren uygulama taklidi alt süreçlerde gerçek SIGTERM testi. Başlangıç/token/yol/kullanıcı değişikliği, süre aşımı, tekrar gönderim, self/üst süreç koruması, aynı PID ile exec, SIGTERM'i yok sayma ve korunan yollar kapsanır.
- Swift adaptörü de kendi derlenmiş geçici uygulama taklidi ile uygulama eşleştirmesini, iptali, tek gönderimi ve çıkış gözlemini sınar. Mevcut kullanıcı uygulamaları test hedefi değildir.
- Ayrı salt okunur kontrol üç mevcut kullanıcı uygulaması sürecinde audit token hazırlığının çalıştığını doğruladı; hiçbirine sinyal gönderilmedi.

Sistem macOS SDK 27.0 ile derlendi; paket alt sınırı macOS 15. İlave kurulum, özel SDK başlığı, özel proc_info sabiti, entitlement veya yönetici izni kullanılmadı. Diğer macOS sürümlerindeki izin farkları çalışma anında kapalı sonuç üretir.

22 Ekim manuel seçim düzeltmesi: önceki “öneri yoksa engelle” koşulu, uygulama toplamı büyük olup her yardımcı süreç 2 GiB altında kaldığında kullanıcıyı kapatma akışına hiç sokmuyordu. Öneri yetkiden ayrıldı. Yeni gerçek PTY testi kendi düşük ayak izli, önerisiz uygulamasında x → MANUEL → etki/onay → tek SIGTERM → çıkış doğrulama → karşılaştırma → dört grafikli HTML akışını çalıştırır. Kaynaklar gerçek sistem okumalarıdır; düşüş garantisi aranmaz.

## Terminal.app üst süreç denetimi

Terminal.app ile Warp farkı araştırılırken yerel hazırlığın üst süreç zincirindeki tam BSD okuma reddini tüm hedefler için `PROTECTED` saydığı bulundu. Canlı root süreçte `PROC_PIDTBSDINFO` EPERM dönerken `PROC_PIDT_SHORTBSDINFO` okunabildi; Terminal benzeri Nabız→shell→root login→Terminal→launchd zinciriyle eski kodun ilgisiz hedefi de engellediği yeniden üretildi.

Üst süreç yürüyüşü artık yalnız kısa BSD metadata ile yapılır; tam boyut, PID, geçerli ebeveyn, döngü ve derinlik sınırı kontrol edilir. Okunamayan zincir yine engeller ancak `ANCESTRY_UNAVAILABLE` olarak açıklanır. Hedefin tam BSD, kullanıcı, audit-token, uygulama yolu ve tek kullanımlık onay kontrolleri değişmedi. Swift kontrol ekranı yerel hazırlık reddini kırmızı ENGELLİ ve yeniden deneme olarak gösterir.

`Tests/Native/process_ancestry_test.c` root köprüsü, gerçek üst süreçler ve bozuk/eksik zincirleri kapsar; runner toplam 9 yerel test grubunu çalıştırır. Kısa BSD yapısı ve işlem türü Apple'ın [proc_info.h kaynağında](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/proc_info.h) tanımlıdır. Kullanıcının önceki Terminal.app zinciri canlı yakalanmadığından o oturumun kesin reddetme noktası doğrudan ölçülmüş değildir.
