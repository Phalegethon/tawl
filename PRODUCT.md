# TAWL — Terminal Activity & Workload Lens

macOS makinelerindeki yükü anlaşılır gösteren terminal aracı. Teknik süreç tablosundan önce baskıyı, kaynak tüketen uygulamayı/projeyi ve zaman içindeki değişimi gösterir. Canlı terminal, kayıt ve rapor komutları birlikte çalışır. Hazır sürümleri kullanmak için derleyici veya ek bir çalışma ortamı gerekmez.

Ölçümün zamanı, izin kapsamı ve belirsizliği ürünün temelidir. Büyük tüketim tek başına darboğaz veya bellek sızıntısı teşhisi değildir. İzleme varsayılan olarak salt okunurdur. Kullanıcının kendi doğrulanmış uygulamasına ait tek bir canlı süreç (önerilen veya elle seçilen) etki önizlemesi ve açık onay sonrası SIGTERM ile sonlandırılabilir. Sistem/altyapı süreçleri, otomatik veya toplu kapatma, zorla kapatma ve sistem ayarı değişiklikleri kapsam dışıdır.

Sunum: grafikler, kaynaklara göre renkler, hizalanmış karşılaştırmalı satırlar; dar ekranda özet/grafik, geniş ekranda seçili uygulama incelemesi. Yeni sürümler arka planda kontrol edilir; kurulum yalnız açık güncelleme komutuyla yapılır. Ölçüm verileri dışarı gönderilmez.
