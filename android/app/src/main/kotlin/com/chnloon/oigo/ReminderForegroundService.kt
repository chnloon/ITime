package com.chnloon.oigo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.ViewAnimationUtils
import android.view.WindowManager
import android.view.animation.Animation
import android.view.animation.AnimationUtils
import android.widget.TextView
import androidx.core.app.NotificationCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 持久前台 Service — 保持进程存活 + 显示悬浮窗横幅提醒。
 *
 * 国产 ROM（MIUI / EMUI / ColorOS）会在后台杀死进程并压制通知横幅。
 * 此 Service 持续运行：
 *   - START_STICKY 确保被杀死后自动重启
 *   - 闹钟触发时通过 WindowManager 添加悬浮窗 View（绕过系统通知压制）
 *   - 播放提醒铃声 + 震动
 *   - 带滑动进入/退出动画
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

        /** 悬浮窗显示时长（毫秒） */
        private const val BANNER_DURATION_MS = 8000L

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
    private var mediaPlayer: MediaPlayer? = null
    private var isPlayingRingtone = false

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
        stopRingtone()
        super.onDestroy()
        Log.d(TAG, "持久前台 Service 被销毁（START_STICKY 会导致系统重启它）")
    }

    // ═══════════════════════════════════════════════════
    //  提醒事件处理 — 核心：播放铃声 + 显示悬浮窗横幅
    // ═══════════════════════════════════════════════════

    /**
     * 处理提醒事件。
     * 在主线程上播放铃声 + 震动，然后显示悬浮窗横幅。
     */
    private fun handleAlarm(intent: Intent) {
        val eventId = intent.getIntExtra(EXTRA_EVENT_ID, -1)
        val title = intent.getStringExtra(EXTRA_TITLE) ?: ""
        val description = intent.getStringExtra(EXTRA_DESCRIPTION) ?: ""
        val location = intent.getStringExtra(EXTRA_LOCATION) ?: ""
        val eventTime = intent.getStringExtra(EXTRA_EVENT_TIME) ?: ""
        val ringtoneUri = intent.getStringExtra(EXTRA_RINGTONE_URI) ?: ""

        if (eventId == -1) return

        Log.d(TAG, "Service 收到提醒信号: eventId=$eventId, title=$title")

        // 在主线程上执行
        mainHandler.post {
            // 1. 播放铃声
            playReminderSound(ringtoneUri)

            // 2. 震动
            triggerVibration()

            // 3. 显示悬浮窗
            showFloatingBanner(eventId, title, description, location, eventTime, ringtoneUri)
        }
    }

    /**
     * 播放提醒铃声。
     * 使用 MediaPlayer 循环播放，在横幅消失时停止。
     */
    private fun playReminderSound(ringtoneUri: String) {
        try {
            stopRingtone()

            val uri = if (ringtoneUri.isNotEmpty()) {
                Uri.parse(ringtoneUri)
            } else {
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            }

            if (uri == null) {
                Log.w(TAG, "无可用铃声 URI")
                return
            }

            mediaPlayer = MediaPlayer().apply {
                setDataSource(this@ReminderForegroundService, uri)
                setAudioAttributes(
                    android.media.AudioAttributes.Builder()
                        .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION_EVENT)
                        .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                isLooping = true
                setOnPreparedListener { mp ->
                    mp.start()
                    isPlayingRingtone = true
                    Log.d(TAG, "铃声开始播放")
                }
                setOnErrorListener { _, what, extra ->
                    Log.e(TAG, "播放铃声出错: what=$what, extra=$extra")
                    isPlayingRingtone = false
                    true
                }
                prepareAsync()
            }
        } catch (e: Exception) {
            Log.e(TAG, "播放铃声失败: ${e.message}")
            isPlayingRingtone = false
        }
    }

    /**
     * 触发震动提醒。
     */
    private fun triggerVibration() {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vm.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(VIBRATOR_SERVICE) as Vibrator
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val pattern = VibrationEffect.createWaveform(
                    longArrayOf(0, 300, 200, 300, 200, 500),
                    -1
                )
                vibrator.vibrate(pattern)
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(longArrayOf(0, 300, 200, 300, 200, 500), -1)
            }
        } catch (e: Exception) {
            Log.w(TAG, "震动失败: ${e.message}")
        }
    }

    /**
     * 停止播放铃声。
     */
    private fun stopRingtone() {
        try {
            mediaPlayer?.apply {
                if (isPlaying) {
                    stop()
                }
                release()
            }
            mediaPlayer = null
            isPlayingRingtone = false
        } catch (e: Exception) {
            Log.w(TAG, "停止铃声异常: ${e.message}")
            mediaPlayer = null
            isPlayingRingtone = false
        }
    }

    /**
     * 显示悬浮窗横幅提醒。
     * 只有已授予 SYSTEM_ALERT_WINDOW 权限时才生效。
     * 使用滑动进入动画，5 秒后滑动退出。
     */
    private fun showFloatingBanner(
        eventId: Int,
        title: String,
        description: String,
        location: String,
        eventTime: String,
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

            // ── 绑定数据 ──
            bannerView.findViewById<TextView>(R.id.tv_title).text = title

            val contentText = if (description.isNotEmpty()) description else "点击查看详情"
            bannerView.findViewById<TextView>(R.id.tv_content).text = contentText

            // 地点
            val tvLocation = bannerView.findViewById<TextView>(R.id.tv_location)
            if (location.isNotEmpty()) {
                tvLocation.text = "📍 $location"
                tvLocation.visibility = View.VISIBLE
            } else {
                tvLocation.visibility = View.GONE
            }

            // 事件时间
            val tvEventTime = bannerView.findViewById<TextView>(R.id.tv_event_time)
            val formattedTime = formatEventTime(eventTime)
            if (formattedTime.isNotEmpty()) {
                tvEventTime.text = "🕐 $formattedTime"
                tvEventTime.visibility = View.VISIBLE
            } else {
                tvEventTime.visibility = View.GONE
            }

            // 关闭按钮
            bannerView.findViewById<View>(R.id.btn_close).setOnClickListener {
                // 点击关闭时立即移除并停止铃声
                stopRingtone()
                removeOverlay()
            }

            // 点击横幅 → 打开 App 详情页 + 停止铃声
            bannerView.setOnClickListener {
                stopRingtone()
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

            // ── 构建 WindowManager 参数 ──
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

            // ── 播放滑动进入动画 ──
            try {
                val slideIn = AnimationUtils.loadAnimation(this, R.anim.slide_in_top)
                bannerView.startAnimation(slideIn)
            } catch (e: Exception) {
                Log.w(TAG, "启动动画失败: ${e.message}")
            }

            Log.d(TAG, "悬浮窗横幅已显示: eventId=$eventId, title=$title")

            // ── 定时自动移除（BANNER_DURATION_MS 后） ──
            dismissRunnable = Runnable {
                stopRingtone()
                removeOverlay()
            }
            mainHandler.postDelayed(dismissRunnable!!, BANNER_DURATION_MS)

        } catch (e: Exception) {
            Log.e(TAG, "显示悬浮窗失败: ${e.message}")
        }
    }

    /**
     * 移除悬浮窗横幅，带滑动退出动画。
     */
    private fun removeOverlay() {
        try {
            dismissRunnable?.let { mainHandler.removeCallbacks(it) }
            dismissRunnable = null

            overlayView?.let { view ->
                // 先播放退出动画，动画结束后再移除 View
                try {
                    val slideOut = AnimationUtils.loadAnimation(this, R.anim.slide_out_top)
                    slideOut.setAnimationListener(object : Animation.AnimationListener {
                        override fun onAnimationStart(animation: Animation) {}
                        override fun onAnimationRepeat(animation: Animation) {}
                        override fun onAnimationEnd(animation: Animation) {
                            // 动画结束后真正移除 View
                            try {
                                if (view.isAttachedToWindow || Build.VERSION.SDK_INT < Build.VERSION_CODES.KITKAT) {
                                    val wm = getSystemService(WINDOW_SERVICE) as WindowManager
                                    wm.removeView(view)
                                }
                            } catch (e: Exception) {
                                Log.w(TAG, "动画后移除 View 异常: ${e.message}")
                            }
                        }
                    })
                    view.startAnimation(slideOut)
                } catch (e: Exception) {
                    // 动画不可用时直接移除
                    if (view.isAttachedToWindow || Build.VERSION.SDK_INT < Build.VERSION_CODES.KITKAT) {
                        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
                        wm.removeView(view)
                    }
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

    /**
     * 格式化事件时间显示。
     * 输入格式: "yyyy-MM-dd'T'HH:mm:ss"
     * 输出格式: "MM/dd HH:mm" 或 "今天 HH:mm" / "明天 HH:mm"
     */
    private fun formatEventTime(eventTime: String): String {
        if (eventTime.isEmpty()) return ""
        return try {
            val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
            val date = sdf.parse(eventTime) ?: return ""
            val timeStr = SimpleDateFormat("HH:mm", Locale.getDefault()).format(date)

            val now = System.currentTimeMillis()
            val diffDays = ((date.time - now) / (1000 * 60 * 60 * 24)).toInt()

            when {
                diffDays < 0 -> SimpleDateFormat("MM/dd", Locale.getDefault()).format(date) + " $timeStr"
                diffDays == 0 -> "今天 $timeStr"
                diffDays == 1 -> "明天 $timeStr"
                diffDays <= 7 -> "${diffDays}天后 $timeStr"
                else -> SimpleDateFormat("MM/dd", Locale.getDefault()).format(date) + " $timeStr"
            }
        } catch (e: Exception) {
            ""
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
