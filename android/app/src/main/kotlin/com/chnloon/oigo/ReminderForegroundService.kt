package com.chnloon.oigo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.CountDownTimer
import android.os.IBinder
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import androidx.core.app.NotificationCompat

/**
 * 持久前台 Service — 保持进程存活 + 提醒通知处理。
 *
 * ## 为什么需要这个 Service
 *
 * 国产 ROM（MIUI / EMUI / ColorOS）会在后台杀死进程。
 * 如果应用进程被杀死：
 *   1. AlarmManager 仍然会触发 → 启动 ReminderAlarmReceiver
 *   2. 但 BroadcastReceiver 是瞬态组件 → ROM 可能阻止它启动 Activity
 *   3. 通知虽然能发，但 ROM 可能压制横幅弹出
 *
 * **这个 Service 持续运行**，让进程保持"前台"状态：
 *   - ROM 不会轻易杀死前台进程
 *   - 闹钟触发时 Receiver 唤醒 Service → Service 处理提醒
 *   - START_STICKY 确保被杀死后自动重启
 *
 * ## 提醒流程（三层保障）
 *
 * ```
 * AlarmManager → ReminderAlarmReceiver.onReceive()
 *    ├─ 醒屏（PowerManager wake lock）
 *    ├─ sendAlarm() → ReminderForegroundService
 *    │   ├─ [Path A 核心] 有 SYSTEM_ALERT_WINDOW 权限
 *    │   │   → WindowManager.addView() 绘制悬浮覆盖层
 *    │   │   → 标题 + 地点 + 10s 倒计时 + 出发按钮 + 关闭按钮
 *    │   │   → 10s 后自动移除 (CountDownTimer)
 *    │   │   → 完全不经过系统通知 API，ROM 无法拦截
 *    │   │
 *    │   ├─ [Path B 兜底] 直接 startActivity → NotificationBannerActivity
 *    │   │   → 部分 ROM 不拦截此路径
 *    │   │
 *    │   └─ [Path C 兜底] 发布 setFullScreenIntent 通知
 *    │       → 标准 Android 设备上的标准通知
 *    │
 *    └─ Service 持续运行 ← START_STICKY + 低优先级前台通知
 * ```
 *
 * ## 为什么 WindowManager 覆盖层有效
 *
 * 国产 ROM（MIUI/EMUI/ColorOS）拦截通知弹出和后台 Activity 启动，
 * 但无法阻止应用在自身前台进程中绘制悬浮覆盖层。
 * 即使系统限制后台 Activity 启动，已运行的 Service 仍可使用
 * addView() 将自定义 View 叠加在所有屏幕内容之上。
 */
class ReminderForegroundService : Service() {

    companion object {
        private const val TAG = "OiGo_FgService"
        private const val CHANNEL_ID = "foreground_service"
        private const val NOTIFICATION_ID = 1001

        /** Intent action：提醒事件触发 */
        private const val ACTION_ALARM = "com.chnloon.oigo.ACTION_ALARM"

        // ── Intent 键名 ──
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
         * 此 Service 将一直运行，不会自动停止。
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
    //  WindowManager 覆盖层
    // ═══════════════════════════════════════════════════

    private var overlayView: View? = null
    private var overlayParams: WindowManager.LayoutParams? = null
    private var overlayCountDown: CountDownTimer? = null
    private var overlayWakeLock: PowerManager.WakeLock? = null
    private var currentEventId: Int = -1

    /**
     * 检查是否拥有 SYSTEM_ALERT_WINDOW 权限。
     */
    private fun hasOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    /**
     * 显示 WindowManager 悬浮覆盖层横幅。
     *
     * 仅在拥有 SYSTEM_ALERT_WINDOW 权限时生效。
     * 覆盖层会：
     *   1. 唤醒屏幕（PowerManager wake lock）
     *   2. 在屏幕顶部绘制一个半透明横幅卡片
     *   3. 显示标题（粗体）+ 备忘内容
     *   4. 右侧"出发"按钮（有地点信息时可见）
     *   5. 10 秒后自动上滑消失
     *
     * @param eventId 事件 ID
     * @param title 事件标题
     * @param description 备忘内容
     * @param location 事件地点
     * @param latitude 纬度
     * @param longitude 经度
     */
    private fun showOverlay(eventId: Int, title: String, description: String,
                            location: String, latitude: Double, longitude: Double) {
        try {
            // 如果已有覆盖层，先移除
            removeOverlay()

            currentEventId = eventId

            // ── 醒屏 ──
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!powerManager.isInteractive) {
                overlayWakeLock = powerManager.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                            PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "OiGo:OverlayWakeLock"
                )
                overlayWakeLock?.acquire(8000) // 8 秒后自动释放
                Log.d(TAG, "已请求醒屏")
            }

            // ── 创建覆盖层 View ──
            val inflater = getSystemService(Context.LAYOUT_INFLATER_SERVICE) as LayoutInflater
            val rootView = inflater.inflate(
                R.layout.overlay_notification_banner, null
            ) as FrameLayout
            overlayView = rootView

            val titleText = rootView.findViewById<TextView>(R.id.overlayTitleText)
            val contentText = rootView.findViewById<TextView>(R.id.overlayContentText)
            val navigateButton = rootView.findViewById<Button>(R.id.overlayNavigateButton)
            val bannerCard = rootView.findViewById<View>(R.id.bannerCard)

            // 填充数据
            titleText.text = title
            contentText.text = description.ifEmpty { "无备忘内容" }

            // 显示导航按钮（如果有位置信息）
            if (latitude != 0.0 || longitude != 0.0 || location.isNotEmpty()) {
                navigateButton.visibility = View.VISIBLE
            }

            // ── 设置 WindowManager 参数 ──
            val wm = getSystemService(WINDOW_SERVICE) as WindowManager

            val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }

            val flags = (WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN)

            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                layoutType,
                flags,
                PixelFormat.TRANSLUCENT
            )
            params.gravity = Gravity.TOP or Gravity.FILL_HORIZONTAL
            overlayParams = params

            wm.addView(rootView, params)
            Log.d(TAG, "WindowManager 覆盖层已显示: eventId=$eventId, title=$title")

            // ── 点击事件 ──

            // 点击卡片 → 打开详情
            bannerCard.setOnClickListener {
                Log.d(TAG, "覆盖层卡片被点击，打开详情: eventId=$eventId")
                openDetail(eventId)
                animateAndRemoveOverlay()
            }

            // 点击背景遮罩（非卡片区域）→ 关闭
            rootView.setOnClickListener {
                animateAndRemoveOverlay()
            }

            // 阻止卡片点击穿透到遮罩
            bannerCard.setOnTouchListener { _, _ -> false }

            // "出发"按钮 → 导航
            navigateButton.setOnClickListener {
                Log.d(TAG, "覆盖层出发按钮被点击")
                openNavigation(latitude, longitude, location)
                animateAndRemoveOverlay()
            }

            // ── 10 秒后自动上滑消失 ──
            overlayCountDown = object : CountDownTimer(10_000, 10_000) {
                override fun onTick(millisUntilFinished: Long) {
                    // 不显示倒计时文字，只等待结束
                }

                override fun onFinish() {
                    Log.d(TAG, "覆盖层倒计时结束，自动上滑消失")
                    animateAndRemoveOverlay()
                }
            }
            overlayCountDown?.start()

        } catch (e: Exception) {
            Log.e(TAG, "显示 WindowManager 覆盖层失败: ${e.message}")
            removeOverlay()
        }
    }

    /**
     * 上滑动画后移除覆盖层。
     * 将 bannerCard 向上滑出屏幕并淡出，动画结束后移除 View。
     */
    private fun animateAndRemoveOverlay() {
        try {
            overlayCountDown?.cancel()
            overlayCountDown = null

            val card = overlayView?.findViewById<View>(R.id.bannerCard)
            if (card != null) {
                card.animate()
                    .translationYBy(-card.height.toFloat() - 100f)
                    .alpha(0f)
                    .setDuration(300)
                    .withEndAction {
                        removeOverlay()
                    }
                    .start()
            } else {
                removeOverlay()
            }
        } catch (e: Exception) {
            Log.w(TAG, "上滑动画失败，直接移除: ${e.message}")
            removeOverlay()
        }
    }

    /**
     * 移除 WindowManager 悬浮覆盖层（立即移除，无动画）。
     */
    private fun removeOverlay() {
        try {
            overlayCountDown?.cancel()
            overlayCountDown = null

            overlayWakeLock?.let {
                if (it.isHeld) {
                    it.release()
                }
            }
            overlayWakeLock = null

            val view = overlayView ?: return
            val params = overlayParams ?: return
            val wm = getSystemService(WINDOW_SERVICE) as WindowManager
            if (view.isAttachedToWindow || Build.VERSION.SDK_INT < Build.VERSION_CODES.KITKAT) {
                try {
                    wm.removeView(view)
                } catch (e: Exception) {
                    Log.w(TAG, "移除覆盖层时出错（可能已移除）: ${e.message}")
                }
            }
            overlayView = null
            overlayParams = null
            currentEventId = -1
            Log.d(TAG, "WindowManager 覆盖层已移除")
        } catch (e: Exception) {
            Log.e(TAG, "移除覆盖层失败: ${e.message}")
        }
    }

    /**
     * 打开 OiGo 主界面并跳转事件详情。
     */
    private fun openDetail(eventId: Int) {
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                putExtra("action", "detail")
                putExtra("event_id", eventId)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "打开详情失败: ${e.message}")
        }
    }

    /**
     * 打开地图导航。
     */
    private fun openNavigation(latitude: Double, longitude: Double, location: String) {
        try {
            val uri = if (location.isNotEmpty()) {
                "geo:0,0?q=${Uri.encode(location)}"
            } else {
                "geo:$latitude,$longitude"
            }
            val mapIntent = Intent(Intent.ACTION_VIEW, Uri.parse(uri)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(mapIntent)
        } catch (e: Exception) {
            Log.e(TAG, "打开地图失败: ${e.message}")
        }
    }

    // ═══════════════════════════════════════════════════
    //  Service 生命周期
    // ═══════════════════════════════════════════════════

    override fun onCreate() {
        super.onCreate()
        createPersistentChannel()

        // 启动前台通知（持久显示，低优先级）
        val notification = buildPersistentNotification()
        startForeground(NOTIFICATION_ID, notification)

        Log.d(TAG, "持久前台 Service 已创建并开始运行")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent != null && ACTION_ALARM == intent.action) {
            handleAlarm(intent)
        }
        // START_STICKY：如果 Service 因系统资源紧张被杀死，系统将自动重启它
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        removeOverlay()
        super.onDestroy()
        Log.d(TAG, "持久前台 Service 被销毁（START_STICKY 会导致系统重启它）")
    }

    // ═══════════════════════════════════════════════════
    //  提醒事件处理
    // ═══════════════════════════════════════════════════

    /**
     * 处理提醒事件。
     *
     * 三层保障路径：
     *   1. [Path A 核心] 有 SYSTEM_ALERT_WINDOW 权限 → WindowManager 覆盖层
     *   2. [Path B 兜底] 直接 startActivity → NotificationBannerActivity
     *   3. [Path C 兜底] 发布 setFullScreenIntent 通知
     */
    private fun handleAlarm(intent: Intent) {
        val eventId = intent.getIntExtra(EXTRA_EVENT_ID, -1)
        val title = intent.getStringExtra(EXTRA_TITLE) ?: ""
        val description = intent.getStringExtra(EXTRA_DESCRIPTION) ?: ""
        val location = intent.getStringExtra(EXTRA_LOCATION) ?: ""
        val latitude = intent.getDoubleExtra(EXTRA_LATITUDE, 0.0)
        val longitude = intent.getDoubleExtra(EXTRA_LONGITUDE, 0.0)
        val eventTime = intent.getStringExtra(EXTRA_EVENT_TIME) ?: ""
        val ringtoneUri = intent.getStringExtra(EXTRA_RINGTONE_URI) ?: ""

        if (eventId == -1) return // 无效事件

        Log.d(TAG, "Service 处理提醒事件: eventId=$eventId, title=$title")

        // ── Path A（核心）：WindowManager 悬浮覆盖层 ──
        if (hasOverlayPermission()) {
            Log.d(TAG, "[Path A] 有 SYSTEM_ALERT_WINDOW 权限，使用 WindowManager 覆盖层")
            showOverlay(eventId, title, description, location, latitude, longitude)
        } else {
            Log.w(TAG, "[Path A] 无 SYSTEM_ALERT_WINDOW 权限，跳过覆盖层")
        }

        // ── Path B（兜底）：直接 startActivity → NotificationBannerActivity ──
        try {
            val directIntent = Intent(this, NotificationBannerActivity::class.java).apply {
                putExtra(EXTRA_EVENT_ID, eventId)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_LOCATION, location)
                putExtra(EXTRA_LATITUDE, latitude)
                putExtra(EXTRA_LONGITUDE, longitude)
                putExtra(EXTRA_EVENT_TIME, eventTime)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            startActivity(directIntent)
            Log.d(TAG, "[Path B] 直接启动 Activity 已触发: eventId=$eventId")
        } catch (e: Exception) {
            Log.w(TAG, "[Path B] 直接启动 Activity 失败: ${e.message}")
        }

        // ── Path C（兜底）：setFullScreenIntent 通知 ──
        ReminderAlarmReceiver.ensureChannelHighImportance(this)
        postAlarmNotification(eventId, title, description, location, latitude, longitude, eventTime, ringtoneUri)
    }

    // ═══════════════════════════════════════════════════
    //  通知发布（核心功能）
    // ═══════════════════════════════════════════════════

    /**
     * 发布提醒通知（带 setFullScreenIntent）。
     *
     * 使用 `reminder_alarm` 渠道（IMPORTANCE_HIGH），确保：
     *   - 通知可弹出头部横幅（heads-up）
     *   - 在锁屏时也能显示
     *   - setFullScreenIntent 可启动 NotificationBannerActivity
     *
     * ⚠️ 注意：此通知使用 MainActivity.NOTIFICATION_CHANNEL_ID
     *    （"reminder_alarm"，IMPORTANCE_HIGH）而非 foreground_service 渠道。
     *    低优先级渠道无法弹出横幅。
     */
    private fun postAlarmNotification(eventId: Int, title: String, description: String, location: String,
                                       latitude: Double, longitude: Double, eventTime: String,
                                       ringtoneUri: String = "") {
        try {
            val contentText = buildString {
                append(description.ifEmpty { "点击查看详情" })
                if (location.isNotEmpty()) {
                    append(" · $location")
                }
            }

            // 点击通知 → 打开事件详情
            val tapIntent = Intent(this, MainActivity::class.java).apply {
                putExtra("action", "detail")
                putExtra(EXTRA_EVENT_ID, eventId)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            val tapPendingIntent = PendingIntent.getActivity(
                this, eventId, tapIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // ★ setFullScreenIntent — 触发 NotificationBannerActivity 弹出横幅
            val fullScreenIntent = Intent(this, NotificationBannerActivity::class.java).apply {
                putExtra(EXTRA_EVENT_ID, eventId)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_LOCATION, location)
                putExtra(EXTRA_LATITUDE, latitude)
                putExtra(EXTRA_LONGITUDE, longitude)
                putExtra(EXTRA_EVENT_TIME, eventTime)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            val fullScreenPendingIntent = PendingIntent.getActivity(
                this, eventId * 1000, fullScreenIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // 铃声 URI：如果有自定义铃声则使用
            val notificationSoundUri = if (ringtoneUri.isNotEmpty()) {
                android.net.Uri.parse(ringtoneUri)
            } else {
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            }

            // ★ 使用 IMPORTANCE_HIGH 的提醒渠道（已在 Receiver 中重建）
            val notification = NotificationCompat.Builder(this, ReminderAlarmReceiver.CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_bell_outline)
                .setContentTitle(title)
                .setContentText(contentText)
                .setTicker("提醒: $title")
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setAutoCancel(true)
                .setContentIntent(tapPendingIntent)
                .setFullScreenIntent(fullScreenPendingIntent, true)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setSound(notificationSoundUri)
                .setVibrate(longArrayOf(0, 300, 200, 300))
                .build()

            val notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(eventId, notification)

            Log.d(TAG, "Service 已发布提醒通知: eventId=$eventId")
        } catch (e: Exception) {
            Log.e(TAG, "Service 发布通知失败: ${e.message}")
        }
    }

    // ═══════════════════════════════════════════════════
    //  前台 Service 持久通知渠道
    // ═══════════════════════════════════════════════════

    private fun createPersistentChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            val existing = manager.getNotificationChannel(CHANNEL_ID)
            if (existing != null) return // 已存在，保留用户设置

            val channel = NotificationChannel(
                CHANNEL_ID,
                "提醒服务",
                NotificationManager.IMPORTANCE_LOW // 低优先级，不弹出，只出现在通知栏
            ).apply {
                description = "OiGo 前台运行服务，确保准时提醒不被系统拦截"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
            manager.createNotificationChannel(channel)
        }
    }

    /**
     * 构建持久通知（低优先级，仅在通知栏显示）。
     * 这是前台 Service 必须持续显示的 "正在运行" 通知。
     * 用户可以在系统通知设置中将此渠道静音来隐藏。
     */
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
            .setOngoing(true) // 不可滑动移除
            .setShowWhen(false)
            .build()
    }
}
