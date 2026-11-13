package pt.projardim.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createDefaultNotificationChannel()
    }

    // Canal dos pushes do FCM, com o id que o AndroidManifest declara em
    // default_notification_channel_id. Sem ele os pushes caíam no canal
    // genérico "fcm_fallback_notification_channel" (F5 dos testes de 13/11).
    private fun createDefaultNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            DEFAULT_CHANNEL_ID,
            "Pedidos e trabalhos",
            NotificationManager.IMPORTANCE_HIGH,
        )
        channel.description = "Novos pedidos, propostas e avisos dos teus trabalhos"
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val DEFAULT_CHANNEL_ID = "projardim_default"
    }
}
