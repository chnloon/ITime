package com.chnloon.oigo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import androidx.core.app.NotificationCompat

/**
 * 持久前台 Service — 保持进程存活 + 显示悬浮窗横幅提醒。
 *
 * 国产 ROM（MIUI / EMUI / ColorOS）会在后台杀死进程并压制通知横幅。
 * 此 Service 持续运行：
 *   - START_STICKY 确保被杀死后自动重启
 *   - 闹钟触发时通过 WindowManager 添加悬浮窗 View（绕过系统通知压制）
 *
 * 系统通知仍作为兜底发布（由 ReminderAlarmReceiver 负责）。
 */
class ReminderForegroundService : Service() {

    companion object {
        private const val TAG = "OiGo_FgService"
        private const val CHANNEL_ID = "foreground_service"
        private const val NOTIFICATION_ID = 1001

        /** Intent action：提醒事件触发 */
        private const val ACTION_ALARM = "com.chnloon.oigo.ACTION_ALARM"

        private const val EXTRA_EVENT_ID = "event_id"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_DESCRIPTION = "description"
        private const val EXTRA_LOCATION = "location"
        private const val EXTRA_LATITUDE = "latitude"
        private const val EXTRA_LONGITUDE = "longitude"
        private const val EXTRA_EVENT_TIME = "event_time"
        private const val EXTRA_RINGTONE_URI = "ringtone_uri"

        /**
         * 启动持久前台 Service（应用启动时调用）。
         */
        fun start(context: Context) {
            val intent = Intent(context, ReminderForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            Log.d(TAG, "持久前台 Service 启动请求已发送")
        }

        /**
         * 发送提醒事件给已在运行的前台 Service。
         * 由 ReminderAlarmReceiver 在闹钟触发时调用。
         */
        fun sendAlarm(context: Context, eventId: Int, title: String,
                       description: String, location: String, latitude: Double,
                       longitude: Double, eventTime: String,
                       ringtoneUri: String = "") {
            val intent = Intent(context, ReminderForegroundService::class.java).apply {
                action = ACTION_ALARM
                putExtra(EXTRA_EVENT_ID, eventId)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_DESCRIPTION, description)
                putExtra(EXTRA_LOCATION, location)
                putExtra(EXTRA_LATITUDE, latitude)
                putExtra(EXTRA_LONGITUDE, longitude)
                putExtra(EXTRA_EVENT_TIME, eventTime)
                putExtra(EXTRA_RINGTONE_URI, ringtoneUri)
            }
            context.startService(intent)
            Log.d(TAG, "提醒事件已发送给 Service: eventId=$eventId, title=$title")
        }
    }

    // ═══════════════════════════════════════════════════
    //  Service 生命周期
    // ═══════════════════════════════════════════════════

    private var overlayView: View? = null
    private var overlayParams: WindowManager.LayoutParams? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var dismissRunnable: Runnable? = null

    override fun onCreate() {
        super.onCreate()
        createPersistentChannel()

        val notification = buildPersistentNotification()
        startForeground(NOTIFICATION_ID, notification)

        Log.d(TAG, "持久前台 Service 已创建并开始运行")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent != null && ACTION_ALARM == intent.action) {
            handleAlarm(intent)
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        removeOverlay()
        super.onDestroy()
        Log.d(TAG, "持久前台 Service 被销毁（START_STICKY 会导致系统重启它）")
    }

    // ═══════════════════════════════════════════════════
    //  提醒事件处理 — 核心：显示悬浮窗横幅
    // ═══════════════════════════════════════════════════

    /**
     * 处理提醒事件。
     * 如果已授予悬浮窗权限，则通过 WindowManager 显示自定义悬浮横幅；
     * 否则仅记录日志（通知兜底由 ReminderAlarmReceiver 负责）。
     */
    private fun handleAlarm(intent: Intent) {
        val eventId = intent.getIntExtra(EXTRA_EVENT_ID, -1)
        val title = intent.getStringExtra(EXTRA_TITLE) ?: ""
        val description = intent.getStringExtra(EXTRA_DESCRIPTION) ?: ""
        val location = intent.getStringExtra(EXTRA_LOCATION) ?: ""
        val ringtoneUri = intent.getStringExtra(EXTRA_RINGTONE_URI) ?: ""

        if (eventId == -1) return

        Log.d(TAG, "Service 收到提醒信号: eventId=$eventId, title=$title")

        // 在主线程上显示悬浮窗
        mainHandler.post {
            showFloatingBanner(eventId, title, description, location, ringtoneUri)
        }
    }

    /**
     * 显示悬浮窗横幅提醒。
     * 只有已授予 SYSTEM_ALERT_WINDOW 权限时才生效。
     */
    private fun showFloatingBanner(
        eventId: Int,
        title: String,
        description: String,
        location: String,
        ringtoneUri: String
    ) {
        // 检查悬浮窗权限
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            Log.w(TAG, "无 SYSTEM_ALERT_WINDOW 权限，跳过悬浮窗显示")
            return
        }

        // 移除旧的悬浮窗（如果存在）
        removeOverlay()

        try {
            val wm = getSystemService(WINDOW_SERVICE) as WindowManager

            // 膨胀布局
            val bannerView = LayoutInflater.from(this).inflate(
                R.layout.view_reminder_banner, null
            )

            // 绑定数据
            bannerView.findViewById<TextView>(R.id.tv_title).text = title
            val contentText = if (description.isNotEmpty()) description else "点击查看详情"
            bannerView.findViewById<TextView>(R.id.tv_content).text = contentText

            val tvLocation = bannerView.findViewById<TextView>(R.id.tv_location)
            if (location.isNotEmpty()) {
                tvLocation.text = "📍 $location"
                tvLocation.visibility = View.VISIBLE
            } else {
                tvLocation.visibility = View.GONE
            }

            // 关闭按钮
            bannerView.findViewById<Button>(R.id.btn_close).setOnClickListener {
                removeOverlay()
            }

            // 点击横幅 → 打开 App 详情页
            bannerView.setOnClickListener {
                removeOverlay()
                val tapIntent = Intent(this, MainActivity::class.java).apply {
                    putExtra("action", "detail")
                    putExtra("event_id", eventId)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                }
                startActivity(tapIntent)
            }

            // 构建 WindowManager 参数
            val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }

            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                layoutFlag,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                        WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP
                x = 0
                y = 0
            }

            wm.addView(bannerView, params)
            overlayView = bannerView
            overlayParams = params

            Log.d(TAG, "悬浮窗横幅已显示: eventId=$eventId, title=$title")

            // 5 秒后自动移除
            dismissRunnable = Runnable {
                removeOverlay()
            }
            mainHandler.postDelayed(dismissRunnable!!, 5000)

        } catch (e: Exception) {
            Log.e(TAG, "显示悬浮窗失败: ${e.message}")
        }
    }

    /**
     * 移除悬浮窗横幅。
     * 在销毁、关闭按钮点击、超时时调用。
     */
    private fun removeOverlay() {
        try {
            dismissRunnable?.let { mainHandler.removeCallbacks(it) }
            dismissRunnable = null

            overlayView?.let { view ->
                if (view.isAttachedToWindow || Build.VERSION.SDK_INT < Build.VERSION_CODES.KITKAT) {
                    val wm = getSystemService(WINDOW_SERVICE) as WindowManager
                    wm.removeView(view)
                }
                overlayView = null
                overlayParams = null
                Log.d(TAG, "悬浮窗已移除")
            }
        } catch (e: Exception) {
            Log.w(TAG, "移除悬浮窗异常: ${e.message}")
            overlayView = null
            overlayParams = null
        }
    }

    // ═══════════════════════════════════════════════════
    //  前台 Service 持久通知渠道
    // ═══════════════════════════════════════════════════

    private fun createPersistentChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            val existing = manager.getNotificationChannel(CHANNEL_ID)
            if (existing != null) return

            val channel = NotificationChannel(
                CHANNEL_ID,
                "提醒服务",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "OiGo 前台运行服务，确保准时提醒不被系统拦截"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildPersistentNotification(): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val openPendingIntent = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).apply {
                setPriority(Notification.PRIORITY_MIN)
            }
        }

        return builder
            .setSmallIcon(R.drawable.ic_bell_outline)
            .setContentTitle("OiGo")
            .setContentText("通知服务运行中，确保准时提醒不被系统拦截")
            .setContentIntent(openPendingIntent)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }
}
