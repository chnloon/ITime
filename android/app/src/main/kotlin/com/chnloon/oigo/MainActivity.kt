package com.chnloon.oigo

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.sqlite.SQLiteDatabase
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Android 14 (API 34) 的编译时常量（防止低版本 SDK 编译报错）
private const val API_34 = 34

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.chnloon.oigo/reminder"
        private const val TAG = "OiGo_MainActivity"
        const val NOTIFICATION_CHANNEL_ID = "reminder_alarm"
        private const val PERMISSION_REQUEST_NOTIFICATION = 1001
        private const val PERMISSION_REQUEST_EXACT_ALARM = 1002

        /**
         * 从原生侧重新注册所有提醒（供 BootReceiver 调用）。
         */
        fun rescheduleAllFromNative(context: Context) {
            try {
                val dbPath = context.getDatabasePath("oigo.db").absolutePath
                if (!java.io.File(dbPath).exists()) {
                    Log.d(TAG, "数据库不存在，跳过开机重建闹钟")
                    return
                }
                val db = SQLiteDatabase.openDatabase(dbPath, null, 0)
                val cursor = db.rawQuery(
                    "SELECT * FROM schedules WHERE is_deleted = 0 ORDER BY event_time ASC",
                    null
                )
                var count = 0
                while (cursor.moveToNext()) {
                    val eventId = cursor.getInt(cursor.getColumnIndexOrThrow("id"))
                    val title = cursor.getString(cursor.getColumnIndexOrThrow("title"))
                    val location = cursor.getString(cursor.getColumnIndexOrThrow("location")) ?: ""
                    val eventTimeStr = cursor.getString(cursor.getColumnIndexOrThrow("event_time"))
                    val latitude = cursor.getDouble(cursor.getColumnIndexOrThrow("latitude"))
                    val longitude = cursor.getDouble(cursor.getColumnIndexOrThrow("longitude"))
                    val reminderMinutes = cursor.getInt(cursor.getColumnIndexOrThrow("reminder_minutes"))
                    val ringtoneUri = cursor.getString(cursor.getColumnIndexOrThrow("ringtone_uri")) ?: ""

                    if (reminderMinutes <= 0) continue

                    val eventTime = try {
                        java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.US).parse(eventTimeStr)
                    } catch (e: Exception) {
                        null
                    }
                    if (eventTime == null) continue

                    val alarmTime = eventTime.time - reminderMinutes * 60_000L
                    if (alarmTime < System.currentTimeMillis()) continue

            val description = cursor.getString(cursor.getColumnIndexOrThrow("description")) ?: ""
            val args = mapOf(
                "eventId" to eventId,
                "title" to title,
                "description" to description,
                "location" to location,
                "latitude" to latitude,
                "longitude" to longitude,
                "eventTime" to eventTimeStr,
                "alarmTimeMillis" to alarmTime,
                "ringtoneUri" to ringtoneUri
            )
            setReminderAlarm(context, args)
            count++
        }
        cursor.close()
        db.close()
        Log.d(TAG, "开机后重建 $count 个提醒闹钟")
    } catch (e: Exception) {
        Log.e(TAG, "开机重建闹钟失败: ${e.message}")
    }
}

/**
 * 设置提醒闹钟（静态方法，供 BootReceiver 调用）。
 * 自动降级：如果精确闹钟受限，使用非精确闹钟。
 */
private fun setReminderAlarm(context: Context, args: Map<*, *>) {
    val eventId = args["eventId"] as? Int ?: return
    val title = args["title"] as? String ?: return
    val description = args["description"] as? String ?: ""
    val location = args["location"] as? String ?: ""
    val latitude = args["latitude"] as? Double ?: 0.0
    val longitude = args["longitude"] as? Double ?: 0.0
    val eventTime = args["eventTime"] as? String ?: ""
    val alarmTimeMillis = args["alarmTimeMillis"] as? Long ?: return

    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    val ringtoneUri = args["ringtoneUri"] as? String ?: ""

    val intent = Intent(context, ReminderAlarmReceiver::class.java).apply {
        putExtra("event_id", eventId)
        putExtra("title", title)
        putExtra("description", description)
        putExtra("location", location)
        putExtra("latitude", latitude)
        putExtra("longitude", longitude)
        putExtra("event_time", eventTime)
        putExtra("ringtone_uri", ringtoneUri)
    }

            val pendingIntent = PendingIntent.getBroadcast(
                context,
                eventId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or
                        PendingIntent.FLAG_IMMUTABLE
            )

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    if (alarmManager.canScheduleExactAlarms()) {
                        alarmManager.setExactAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP,
                            alarmTimeMillis,
                            pendingIntent
                        )
                    } else {
                        alarmManager.setAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP,
                            alarmTimeMillis,
                            pendingIntent
                        )
                        Log.w(TAG, "无 SCHEDULE_EXACT_ALARM 权限，使用非精确闹钟")
                    }
                } else {
                    alarmManager.setExact(
                        AlarmManager.RTC_WAKEUP,
                        alarmTimeMillis,
                        pendingIntent
                    )
                }
            } catch (e: SecurityException) {
                Log.w(TAG, "精确闹钟被拒绝，降级为非精确: ${e.message}")
                try {
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        alarmTimeMillis,
                        pendingIntent
                    )
                } catch (e2: Exception) {
                    Log.e(TAG, "降级闹钟也失败: ${e2.message}")
                }
            }

            // ★ 同时设置预热闹钟：在提醒前 60 秒唤醒前台 Service
            //    如果国产 ROM 杀死了前台 Service，预热闹钟会在提醒前 60 秒
            //    触发 AlarmReceiver 来重新启动 Service，确保提醒准时触发。
            try {
                val warmupTime = alarmTimeMillis - 60_000
                if (warmupTime > System.currentTimeMillis()) {
                    val warmupIntent = Intent(context, ReminderAlarmReceiver::class.java).apply {
                        putExtra("event_id", eventId)
                        putExtra("is_warmup", true)
                    }
                    val warmupPendingIntent = PendingIntent.getBroadcast(
                        context,
                        eventId * 100 + 999, // 与主闹钟不同 requestCode
                        warmupIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        if (alarmManager.canScheduleExactAlarms()) {
                            alarmManager.setExactAndAllowWhileIdle(
                                AlarmManager.RTC_WAKEUP, warmupTime, warmupPendingIntent
                            )
                        } else {
                            alarmManager.setAndAllowWhileIdle(
                                AlarmManager.RTC_WAKEUP, warmupTime, warmupPendingIntent
                            )
                        }
                    } else {
                        alarmManager.setExact(
                            AlarmManager.RTC_WAKEUP, warmupTime, warmupPendingIntent
                        )
                    }
                    Log.d(TAG, "预热闹钟已设置: eventId=$eventId, warmupTime=${
                        java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault())
                            .format(java.util.Date(warmupTime))
                    }")
                }
            } catch (e: Exception) {
                Log.w(TAG, "设置预热闹钟失败（不影响主闹钟）: ${e.message}")
            }

            Log.d(TAG, "闹钟已设置: eventId=$eventId, title=$title, alarmTime=${
                java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault())
                    .format(java.util.Date(alarmTimeMillis))
            }")
        }
    }

    private var pendingDetailEventId: Int? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setReminder" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args != null) {
                        setReminderAlarm(this, args)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "Missing arguments", null)
                    }
                }
                "cancelReminder" -> {
                    val eventId = call.arguments as? Int
                    if (eventId != null) {
                        cancelReminderAlarm(eventId)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "Missing eventId", null)
                    }
                }
                "checkPermissions" -> {
                    result.success(mapOf(
                        "postNotifications" to hasPostNotificationsPermission(),
                        "exactAlarm" to hasExactAlarmPermission(),
                        "systemAlertWindow" to hasSystemAlertWindowPermission(),
                        "fullScreenIntent" to hasFullScreenIntentPermission(),
                    ))
                }
                "requestPostNotificationsPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        pendingPermissionResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            PERMISSION_REQUEST_NOTIFICATION
                        )
                    } else {
                        result.success(true)
                    }
                }
                "requestExactAlarmPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                            data = android.net.Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                        result.success(true)
                    } else {
                        result.success(true)
                    }
                }
                "openExactAlarmSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                            data = android.net.Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                    }
                    result.success(true)
                }
                // ★ 新增：检查悬浮窗权限
                "checkSystemAlertWindow" -> {
                    result.success(hasSystemAlertWindowPermission())
                }
                // ★ 新增：打开悬浮窗权限设置页
                "openSystemAlertWindowSettings" -> {
                    openSystemAlertWindowSettings()
                    result.success(true)
                }
                // ★ 新增：打开 App 通知设置页
                "openAppNotificationSettings" -> {
                    openAppNotificationSettings()
                    result.success(true)
                }
                // ★ Android 14+：检查全屏 Intent 权限
                //    setFullScreenIntent 需要此权限才能触发横幅 Activity
                "checkFullScreenIntent" -> {
                    result.success(hasFullScreenIntentPermission())
                }
                // ★ 测试提醒：调度真实闹钟（走完整 AlarmManager 路径）
                //   从 Flutter 侧接收 delayMs 参数，默认 10 秒
                "testNotification" -> {
                    val args = call.arguments as? Map<*, *>
                    val delayMs = args?.get("delayMs") as? Long ?: 10000L
                    Log.d(TAG, "测试提醒被触发: delay=${delayMs}ms")
                    testNotification(delayMs)
                    result.success(true)
                }
                // ★ Android 14+：打开通知设置页让用户手动启用全屏 Intent
                "openNotificationSettings" -> {
                    openAppNotificationSettings()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        checkIntentExtras(intent)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_NOTIFICATION) {
            val granted = grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
        checkIntentExtras(intent)

        // ★ 启动持久前台 Service（一直运行，不自毁）
        //    让进程保持"前台"状态，防止国产 ROM 杀死进程。
        //    闹钟触发时，已运行的 Service 可直接处理提醒事件。
        startPersistentForegroundService()
    }

    /**
     * 启动持久前台 Service。
     * Service 会持续运行（不自动停止），确保进程存活。
     */
    private fun startPersistentForegroundService() {
        try {
            ReminderForegroundService.start(this)
            Log.d(TAG, "持久前台 Service 已启动")
        } catch (e: Exception) {
            Log.w(TAG, "启动持久前台 Service 失败: ${e.message}")
        }
    }

    // ── 通知渠道 ──

    /**
     * 创建/重建提醒通知渠道（Android 8+ 必需）。
     *
     * 每次应用启动时强制重建，避免 Android 渠道锁定机制导致
     * 已存在的渠道无法将 IMPORTANCE_DEFAULT 升级为 IMPORTANCE_HIGH。
     */
    private fun createNotificationChannel() {
        // 使用 Receiver 的共享方法强制重建（删除+新建）
        ReminderAlarmReceiver.ensureChannelHighImportance(this)
    }

    // ── 测试提醒 ──

    /**
     * 测试提醒：**直接用真实闹钟路径**，跟新增事件的提醒完全一样。
     *
     * 调用 setReminderAlarm() 注册一个指定时间后的真实闹钟，
     * 走完整的 AlarmManager → ReminderAlarmReceiver → ReminderForegroundService 流程，
     * 测试结果即真实效果。
     *
     * @param delayMs 延迟毫秒数（默认 10 秒）
     */
    private fun testNotification(delayMs: Long = 10000) {
        try {
            val eventId = -2 // 用负数避免跟数据库真实事件冲突
            val title = "🔔 测试提醒"
            val location = "测试位置"
            val alarmTime = System.currentTimeMillis() + delayMs

            val args = mapOf(
                "eventId" to eventId,
                "title" to title,
                "location" to location,
                "latitude" to 0.0,
                "longitude" to 0.0,
                "eventTime" to java.text.SimpleDateFormat(
                    "yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.US
                ).format(java.util.Date(alarmTime)),
                "alarmTimeMillis" to alarmTime,
                "ringtoneUri" to ""
            )

            setReminderAlarm(this, args)

            runOnUiThread {
                android.widget.Toast.makeText(
                    this,
                    "测试提醒将在 10 秒后触发（真实闹钟路径），请切换到其他 app 观察",
                    android.widget.Toast.LENGTH_LONG
                ).show()
            }

            Log.d(TAG, "测试提醒已注册为真实闹钟，10秒后触发")
        } catch (e: Exception) {
            Log.e(TAG, "测试提醒设置失败: ${e.message}")
        }
    }

    // ── 权限检查 ──

    private fun hasPostNotificationsPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
                    PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun hasExactAlarmPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.canScheduleExactAlarms()
        } else {
            true
        }
    }

    private fun hasSystemAlertWindowPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    // ── 全屏 Intent 权限（Android 14+，setFullScreenIntent 必需） ──

    /**
     * 检查是否拥有 USE_FULL_SCREEN_INTENT 权限。
     *
     * Android 14+ 上侧载的应用默认被拒绝此权限，
     * 需要用户在 设置 → 通知 → 允许全屏通知 中手动开启。
     *
     * Android 13 及以下：只要声明了权限即自动授权。
     */
    private fun hasFullScreenIntentPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= API_34) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.canUseFullScreenIntent()
        } else {
            true
        }
    }

    private fun openSystemAlertWindowSettings() {
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:$packageName")
        )
        startActivity(intent)
    }

    private fun openAppNotificationSettings() {
        val intent = Intent()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            intent.action = Settings.ACTION_APP_NOTIFICATION_SETTINGS
            intent.putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            intent.action = Settings.ACTION_APPLICATION_DETAILS_SETTINGS
            intent.data = Uri.parse("package:$packageName")
        }
        startActivity(intent)
    }

    // ── Intent 检查 ──

    private fun checkIntentExtras(intent: Intent?) {
        if (intent == null) return
        val action = intent.getStringExtra("action") ?: return
        val eventId = intent.getIntExtra("event_id", -1)

        when (action) {
            "detail" -> {
                if (eventId > 0) {
                    Log.d(TAG, "收到 action=detail, eventId=$eventId")
                    if (flutterEngine?.dartExecutor?.binaryMessenger != null) {
                        MethodChannel(
                            flutterEngine!!.dartExecutor.binaryMessenger,
                            CHANNEL
                        ).invokeMethod("showDetail", eventId)
                    } else {
                        pendingDetailEventId = eventId
                    }
                }
            }
        }
    }

    // ── 闹钟管理（实例方法） ──

    private fun cancelReminderAlarm(eventId: Int) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager

        // 取消主闹钟
        val intent = Intent(this, ReminderAlarmReceiver::class.java).apply {
            putExtra("event_id", eventId)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            eventId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()

        // 取消预热闹钟（使用 eventId * 100 + 999 作为 requestCode）
        val warmupIntent = Intent(this, ReminderAlarmReceiver::class.java).apply {
            putExtra("event_id", eventId)
            putExtra("is_warmup", true)
        }
        val warmupPendingIntent = PendingIntent.getBroadcast(
            this,
            eventId * 100 + 999,
            warmupIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(warmupPendingIntent)
        warmupPendingIntent.cancel()

        Log.d(TAG, "闹钟已取消（含预热闹钟）: eventId=$eventId")
    }
}
