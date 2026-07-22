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
 *   1. 通过 setFullScreenIntent 通知启动 NotificationBannerActivity（主弹窗）
 *   2. 同时唤醒前台 Service 播放铃声+震动（绕过国产 ROM 对通知音量的限制）
 *
 * ## 预热闹钟（Warmup）
 *
 * 主闹钟设置时同时设置一个提前 60 秒的预热闹钟。预热闹钟不显示提醒，
 * 仅负责唤醒前台 Service。这解决了国产 ROM 长时间后杀死前台 Service 的问题：
 * 预热闹钟在真实提醒前 60 秒启动 Service，确保 Service 在提醒时可用。
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
         * 创建高优先级提醒通知渠道。
         * 只在渠道不存在时创建，不删除重建，避免鸿蒙渠道校验异常。
         */
        fun createChannelFresh(context: Context, nm: NotificationManager) {
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

        /**
         * 确保高优先级通知渠道存在。
         * 如果渠道不存在或级别不足，则创建/升级。
         * 不删除重建，避免鸿蒙系统渠道校验异常。
         */
        fun ensureChannelHighImportance(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val existing = nm.getNotificationChannel(CHANNEL_ID)
                if (existing != null && existing.importance >= NotificationManager.IMPORTANCE_HIGH) {
                    Log.d(TAG, "通知渠道已存在且级别正确: $CHANNEL_ID")
                    return
                }
                createChannelFresh(context, nm)
                Log.d(TAG, "通知渠道已创建/升级: $CHANNEL_ID (IMPORTANCE_HIGH)")
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val eventId = intent.getIntExtra("event_id", -1)

        // ★ 预热闹钟处理：不显示提醒，只负责唤醒前台 Service
        val isWarmup = intent.getBooleanExtra("is_warmup", false)
        if (isWarmup) {
            Log.d(TAG, "预热闹钟触发: eventId=$eventId — 启动前台 Service 以保持进程存活")
            try {
                ReminderForegroundService.start(context)
                Log.d(TAG, "预热闹钟：前台 Service 已启动/保持")
            } catch (e: Exception) {
                Log.w(TAG, "预热闹钟启动 Service 失败: ${e.message}")
            }
            return
        }

        val title = intent.getStringExtra("title") ?: return
        val description = intent.getStringExtra("description") ?: ""
        val location = intent.getStringExtra("location") ?: ""
        val ringtoneUri = intent.getStringExtra("ringtone_uri") ?: ""

        Log.d(TAG, "提醒触发: eventId=$eventId, title=$title")

        try {
            // 1. 确保通知渠道 IMPORTANCE_HIGH
            ensureChannelHighImportance(context)

            // 2. 同时唤醒前台 Service 保持进程活跃
            ReminderForegroundService.sendAlarm(
                context, eventId, title, description, location, 0.0, 0.0, "", ringtoneUri
            )

            // 3. 发布标准通知 — 微信风格横幅提醒
            //    仅使用 IMPORTANCE_HIGH + CATEGORY_REMINDER + DEFAULT_ALL
            //    不需要 fullScreenIntent / SYSTEM_ALERT_WINDOW
            val contentText = buildString {
                append(description.ifEmpty { "点击查看详情" })
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
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setSound(notificationSoundUri)
                .setAutoCancel(true)
                .setContentIntent(tapPendingIntent)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .build()

            val notificationManager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(eventId, notification)

            Log.d(TAG, "标准通知已发布: eventId=$eventId, title=$title")
        } catch (e: Exception) {
            Log.e(TAG, "处理提醒事件失败: ${e.message}")
        }
    }
}
