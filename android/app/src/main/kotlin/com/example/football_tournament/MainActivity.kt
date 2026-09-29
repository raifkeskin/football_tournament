package com.example.football_tournament

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Bilinen Android davranışı: uygulama kurulumdan sonra yükleyicideki
        // "Aç" ile başlatılıp arka plana alınırsa, simgeden açıldığında yeni
        // bir kopya oluşur ve uygulama baştan (açılış ekranı) başlar. Zaten
        // çalışan bir görev varsa bu yeni kopyayı kapatıp mevcut olana dön.
        if (!isTaskRoot &&
            intent?.hasCategory(Intent.CATEGORY_LAUNCHER) == true &&
            intent?.action == Intent.ACTION_MAIN
        ) {
            super.onCreate(savedInstanceState)
            finish()
            return
        }
        super.onCreate(savedInstanceState)
    }
}
