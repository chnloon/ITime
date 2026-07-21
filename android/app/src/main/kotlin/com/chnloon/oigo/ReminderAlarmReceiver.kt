package com.chnloon.oigo

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * 闹钟广播接收器。
 *
 * ## 提醒触发流程
 *
 * 当 AlarmManager 触发的提醒时间到达时：
 *   1. ★ 直接启动 NotificationBannerActivity（兜底路径 — 部分国产 ROM 无法拦截）
 *   2. 发送提醒到前台 Service → Service 执行全部三条路径（WindowManager 覆盖层 + Activity + 通知）
 *   3. 发布通知（带 setFullScreenIntent）→ 触发 NotificationBannerActivity 弹出横幅
 *
 * ## 预热闹钟（Warmup）
 *
 * 主闹钟设置时同时设置一个提前 60 秒的预热闹钟。预热闹钟不显示提醒，
 * 仅负责唤醒前台 Service。这解决了国产 ROM 长时间后杀死前台 Service 的问题：
 * 预热闹钟在真实提醒前 60 秒启动 Service，确保 Service 在提醒时可用。
 *
 * ## 为什么需要双重触发路径
 *
 * 国产 ROM（MIUI / EMUI / ColorOS）会拦截从 BroadcastReceiver 发起的 Activity 启动。
 * 但有些 ROM 仅拦截 startActivity()，不拦截 setFullScreenIntent；另一些则相反。
 * 本接收器采用「两条路径都走」策略，提高至少一条路径生效的概率。
 *
 * ## 关于通知渠道
 *
 * 每次触发时强制重建通知渠道（删除旧渠道再创建新渠道），确保 IMPORTANCE_HIGH
 * 不因 Android 渠道锁定机制而降级。
 */
class ReminderAlarmReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "OiGo_AlarmReceiver"
        const val CHANNEL_ID = "reminder_alarm"
        const val CHANNEL_NAME = "事件提醒"
        const val CHANNEL_DESC = "日程事件的准时提醒"

        /**
         * 强制重建通知渠道（删除旧 → 新建）。
         * 每次提醒触发时调用，确保 IMPORTANCE_HIGH 不被 Android 渠道锁定降级。
         */
        fun ensureChannelHighImportance(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                nm.deleteNotificationChannel(CHANNEL_ID)
                createChannelFresh(context, nm)
                Log.d(TAG, "通知渠道已强制重建: $CHANNEL_ID (IMPORTANCE_HIGH)")
            }
        }

        private fun createChannelFresh(context: Context, nm: NotificationManager) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val channel = NotificationChannel(
                CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = CHANNEL_DESC
                enableVibration(true)
                setSound(soundUri, audioAttributes)
                vibrationPattern = longArrayOf(0, 300, 200, 300)
                enableLights(true)
                setShowBadge(true)
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(channel)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val eventId = intent.getIntExtra("event_id", -1)

        // ★ 预热闹钟处理：不显示提醒，只负责唤醒前台 Service
        //    主闹钟设置时同时设置了提前 60 秒的预热闹钟。
        //    如果国产 ROM 杀死了前台 Service，预热闹钟在此处重新启动它，
        //    确保 60 秒后的真实提醒能通过已运行的 Service 触发覆盖层。
        val isWarmup = intent.getBooleanExtra("is_warmup", false)
        if (isWarmup) {
            Log.d(TAG, "预热闹钟触发: eventId=$eventId — 启动前台 Service 以保持进程存活")
            try {
                ReminderForegroundService.start(context)
                Log.d(TAG, "预热闹钟：前台 Service 已启动/保持")
            } catch (e: Exception) {
                Log.w(TAG, "预热闹钟启动 Service 失败: ${e.message}")
            }
            return // 不显示任何提醒
        }

        val title = intent.getStringExtra("title") ?: return
        val description = intent.getStringExtra("description") ?: ""
        val location = intent.getStringExtra("location") ?: ""
        val latitude = intent.getDoubleExtra("latitude", 0.0)
        val longitude = intent.getDoubleExtra("longitude", 0.0)
        val eventTime = intent.getStringExtra("event_time") ?: ""
        val ringtoneUri = intent.getStringExtra("ringtone_uri") ?: ""

        Log.d(TAG, "提醒触发: eventId=$eventId, title=$title")

        try {
            // 1. 强制重建通知渠道（确保 IMPORTANCE_HIGH）
            ensureChannelHighImportance(context)

            // 2. ★ 路径 A：直接启动 NotificationBannerActivity（不依赖通知系统）
            //    某些国产 ROM 不拦截 BroadcastReceiver 的 startActivity()
            try {
                val directIntent = Intent(context, NotificationBannerActivity::class.java).apply {
                    putExtra("event_id", eventId)
                    putExtra("title", title)
                    putExtra("location", location)
                    putExtra("latitude", latitude)
                    putExtra("longitude", longitude)
                    putExtra("event_time", eventTime)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                context.startActivity(directIntent)
                Log.d(TAG, "路径 A（直接启动Activity）已触发: eventId=$eventId")
            } catch (e: Exception) {
                Log.w(TAG, "路径 A 失败（国产 ROM 可能拦截了背景启动）: ${e.message}")
            }

            // 3. 唤醒持久前台 Service（保持进程存活用于后续闹钟）
            ReminderForegroundService.sendAlarm(
                context, eventId, title, description, location, latitude, longitude, eventTime, ringtoneUri
            )

            // 4. ★ 路径 B：通过 setFullScreenIntent 发布通知触发横幅
            val contentText = buildString {
                append("点击查看详情")
                if (location.isNotEmpty()) {
                    append(" · $location")
                }
            }

            val tapIntent = Intent(context, MainActivity::class.java).apply {
                putExtra("action", "detail")
                putExtra("event_id", eventId)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            val tapPendingIntent = PendingIntent.getActivity(
                context, eventId, tapIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val fullScreenIntent = Intent(context, NotificationBannerActivity::class.java).apply {
                putExtra("event_id", eventId)
                putExtra("title", title)
                putExtra("location", location)
                putExtra("latitude", latitude)
                putExtra("longitude", longitude)
                putExtra("event_time", eventTime)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            val fullScreenPendingIntent = PendingIntent.getActivity(
                context, eventId * 1000, fullScreenIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // 铃声 URI：如果有自定义铃声则使用
            val notificationSoundUri = if (ringtoneUri.isNotEmpty()) {
                Uri.parse(ringtoneUri)
            } else {
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            }

            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_bell_outline)
                .setContentTitle(title)
                .setContentText(contentText)
                .setTicker("提醒: $title")
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setSound(notificationSoundUri)
                .setVibrate(longArrayOf(0, 300, 200, 300))
                .setAutoCancel(true)
                .setContentIntent(tapPendingIntent)
                .setFullScreenIntent(fullScreenPendingIntent, true)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .build()

            val notificationManager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(eventId, notification)

            Log.d(TAG, "路径 B（setFullScreenIntent 通知）已发布: eventId=$eventId")
        } catch (e: Exception) {
            Log.e(TAG, "处理提醒事件失败: ${e.message}")
        }
    }
}
