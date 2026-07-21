package com.chnloon.oigo

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.CountDownTimer
import android.util.Log
import android.view.View
import android.view.Window
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView

/**
 * 全屏半透明悬浮横幅 Activity。
 *
 * 由通知的 setFullScreenIntent 触发启动，展示一个顶部横幅卡片：
 *   - 事件标题 + "点击查看详情 · 地点"
 *   - 10 秒倒计时（最后 3 秒变红）
 *   - "出发"按钮 → 直接打开地图导航
 *   - ✕ 按钮 / 点击遮罩 / 10 秒无操作 → 上滑消失
 *   - 点击横幅本身 → 打开 OiGo 主界面并跳转事件详情
 */
class NotificationBannerActivity : Activity() {

    companion object {
        private const val TAG = "OiGo_Banner"
        private const val COUNTDOWN_SECONDS = 10L
    }

    private var eventId: Int = -1
    private var title: String = ""
    private var location: String = ""
    private var latitude: Double = 0.0
    private var longitude: Double = 0.0

    private lateinit var bannerCard: View
    private lateinit var titleText: TextView
    private lateinit var contentText: TextView
    private lateinit var countdownText: TextView
    private lateinit var closeButton: ImageView
    private lateinit var navigateButton: Button

    private var countDownTimer: CountDownTimer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // ── 全屏无边框设置 ──
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_FULLSCREEN,
            WindowManager.LayoutParams.FLAG_FULLSCREEN
        )
        // 解锁屏幕 + 亮屏
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        )
        // 半透明状态栏
        window.statusBarColor = android.graphics.Color.TRANSPARENT

        setContentView(R.layout.activity_notification_banner)

        // ── 读取 Intent 参数 ──
        eventId = intent.getIntExtra("event_id", -1)
        title = intent.getStringExtra("title") ?: ""
        location = intent.getStringExtra("location") ?: ""
        latitude = intent.getDoubleExtra("latitude", 0.0)
        longitude = intent.getDoubleExtra("longitude", 0.0)

        // ── 绑定视图 ──
        bannerCard = findViewById(R.id.bannerCard)
        titleText = findViewById(R.id.titleText)
        contentText = findViewById(R.id.contentText)
        countdownText = findViewById(R.id.countdownText)
        closeButton = findViewById(R.id.closeButton)
        navigateButton = findViewById(R.id.navigateButton)

        // ── 填充数据 ──
        titleText.text = title
        val content = buildString {
            append("点击查看详情")
            if (location.isNotEmpty()) {
                append(" · $location")
            }
        }
        contentText.text = content

        // ── 隐藏导航按钮（如果没有位置信息） ──
        if (latitude == 0.0 && longitude == 0.0) {
            navigateButton.visibility = View.GONE
        }

        // ── 进入动画 ──
        overridePendingTransition(R.anim.slide_in_top, 0)

        // ── 设置点击事件 ──

        // 点击横幅卡片 → 打开详情
        bannerCard.setOnClickListener {
            Log.d(TAG, "横幅被点击，打开详情: eventId=$eventId")
            openDetail()
        }

        // 点击遮罩背景 → 直接关闭
        findViewById<FrameLayout>(android.R.id.content).setOnClickListener {
            dismissBanner()
        }

        // 阻止横幅卡片的点击穿透到遮罩
        bannerCard.setOnTouchListener { _, _ -> false }

        // 关闭按钮 ✕
        closeButton.setOnClickListener {
            dismissBanner()
        }

        // "出发"按钮 → 导航
        navigateButton.setOnClickListener {
            Log.d(TAG, "出发按钮被点击，导航到: lat=$latitude, lng=$longitude")
            openNavigation()
        }

        // ── 启动倒计时 ──
        startCountdown()
    }

    /**
     * 10 秒倒计时，每秒更新 UI。
     */
    private fun startCountdown() {
        countDownTimer = object : CountDownTimer(COUNTDOWN_SECONDS * 1000, 1000) {
            override fun onTick(millisUntilFinished: Long) {
                val secondsLeft = (millisUntilFinished / 1000).toInt()
                countdownText.text = "${secondsLeft}s"

                // 最后 3 秒变红色
                if (secondsLeft <= 3) {
                    countdownText.setTextColor(android.graphics.Color.parseColor("#FF3B30"))
                } else {
                    countdownText.setTextColor(android.graphics.Color.parseColor("#007AFF"))
                }
            }

            override fun onFinish() {
                Log.d(TAG, "倒计时结束，自动关闭横幅")
                dismissBanner()
            }
        }
        countDownTimer?.start()
    }

    /**
     * 打开地图导航。
     * 使用 geo: URI scheme，与现有 NotificationActionReceiver 逻辑一致。
     */
    private fun openNavigation() {
        try {
            val uri = if (location.isNotEmpty()) {
                // 优先使用位置名称进行搜索
                "geo:0,0?q=${Uri.encode(location)}"
            } else {
                "geo:$latitude,$longitude"
            }
            val mapIntent = Intent(Intent.ACTION_VIEW, Uri.parse(uri))
            startActivity(mapIntent)
        } catch (e: Exception) {
            Log.e(TAG, "打开地图失败: ${e.message}")
        }
        // 启动导航后也关闭横幅
        dismissBanner()
    }

    /**
     * 打开 OiGo 主界面并跳转事件详情。
     */
    private fun openDetail() {
        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra("action", "detail")
            putExtra("event_id", eventId)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(intent)
        finish()
        // 使用淡出动画（不滑出，因为要打开主界面）
        overridePendingTransition(0, android.R.anim.fade_out)
    }

    /**
     * 关闭横幅（上滑动画）。
     */
    private fun dismissBanner() {
        countDownTimer?.cancel()
        finish()
        overridePendingTransition(0, R.anim.slide_out_top)
    }

    override fun onDestroy() {
        super.onDestroy()
        countDownTimer?.cancel()
    }

    /**
     * 物理返回键等同于关闭横幅。
     */
    override fun onBackPressed() {
        dismissBanner()
    }
}
