# Kimlik doğrulama yalnız Latin metin tanıma modelini kullanır; ML Kit'in
# diğer dil modülleri (Çince, Japonca, Korece, Devanagari) uygulamada yok.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
