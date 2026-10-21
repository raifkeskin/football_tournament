package com.ligmasasi.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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
        createSoundChannels()
    }

    // Bildirim sesi denemesi: her ses ayrı kanal (Android 8+ sesi kanal
    // belirler). Seçim yapılınca bu kanallar kalıcı kanallarla değişecek.
    private fun createSoundChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val sounds = listOf(
            R.raw.ses_deneme_1 to "Ses denemesi 1 · Tek uzun düdük",
            R.raw.ses_deneme_2 to "Ses denemesi 2 · Kısa düdük",
            R.raw.ses_deneme_3 to "Ses denemesi 3 · Üç düdük",
            R.raw.ses_deneme_4 to "Ses denemesi 4 · Stat patlaması",
            R.raw.ses_deneme_5 to "Ses denemesi 5 · Stat coşkusu",
            R.raw.ses_deneme_6 to "Ses denemesi 6 · Tribün uğultusu",
            R.raw.ses_deneme_7 to "Ses denemesi 7 · Kalabalık alkış",
            R.raw.ses_deneme_8 to "Ses denemesi 8 · Tezahürat",
            R.raw.ses_deneme_9 to "Ses denemesi 9 · Düdük + stat",
        )
        sounds.forEachIndexed { i, (res, name) ->
            val ch = NotificationChannel(
                "ses_deneme_${i + 1}",
                name,
                NotificationManager.IMPORTANCE_HIGH,
            )
            ch.setSound(Uri.parse("android.resource://$packageName/$res"), attrs)
            nm.createNotificationChannel(ch)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ligmasasi/instagram")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isInstalled" -> result.success(igInstalled())
                    "share" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val story = call.argument<Boolean>("story") ?: false
                        val appId = call.argument<String>("appId")
                        if (bytes == null) {
                            result.error("args", "Görsel yok", null)
                        } else {
                            result.success(shareToInstagram(bytes, story, appId))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun igInstalled(): Boolean = try {
        packageManager.getPackageInfo(IG, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    // Afişi Instagram'ın hikâye düzenleyicisinde ya da gönderi ekranında açar.
    // Paylaşım Instagram'da o an açık olan hesaptan yapılır.
    private fun shareToInstagram(bytes: ByteArray, story: Boolean, appId: String?): Boolean {
        val dir = File(cacheDir, "ig_share").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        val file = File(dir, "afis_${System.currentTimeMillis()}.png")
        file.writeBytes(bytes)
        val uri = FileProvider.getUriForFile(this, "$packageName.igshare", file)
        grantUriPermission(IG, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)

        val intent = if (story) {
            Intent("com.instagram.share.ADD_TO_STORY").apply {
                setDataAndType(uri, "image/png")
                if (!appId.isNullOrBlank()) putExtra("source_application", appId)
            }
        } else {
            Intent(Intent.ACTION_SEND).apply {
                type = "image/png"
                putExtra(Intent.EXTRA_STREAM, uri)
            }
        }
        intent.setPackage(IG)
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

        if (!story) {
            // Instagram'ın gönderi (feed) ekranı; bulunamazsa Instagram kendi
            // seçim ekranını (gönderi / hikâye / mesaj) gösterir.
            val feed = packageManager.queryIntentActivities(intent, 0).firstOrNull {
                it.activityInfo.name.endsWith(".ShareHandlerActivity")
            }
            if (feed != null) intent.setClassName(IG, feed.activityInfo.name)
        }
        return try {
            startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    companion object {
        private const val IG = "com.instagram.android"
    }
}
