package com.chnloon.oigo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log

/**
 * 通知动作按钮广播接收器。
 *
 * 处理提醒通知上的「导航」「确定」按钮点击。
 * 使用 BroadcastReceiver 而非直接启动 Activity，
 * 以兼容 Android 12+ 的通知蹦床限制（notification trampoline restriction）。
 */
class NotificationActionReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "OiGo_NotifAction"
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            "ACTION_NAVIGATE" -> {
                val latitude = intent.getDoubleExtra("latitude", 0.0)
                val longitude = intent.getDoubleExtra("longitude", 0.0)
                val location = intent.getStringExtra("location") ?: ""
                val title = intent.getStringExtra("title") ?: ""

                val geoUri = when {
                    latitude != 0.0 && longitude != 0.0 -> {
                        val encodedLabel = Uri.encode(title)
                        "geo:0,0?q=$latitude,$longitude($encodedLabel)"
                    }
                    location.isNotEmpty() -> {
                        val encodedAddress = Uri.encode(location)
                        "geo:0,0?q=$encodedAddress"
                    }
                    else -> {
                        Log.d(TAG, "导航: 未设置地点")
                        return
                    }
                }

                Log.d(TAG, "导航: $geoUri")
                val mapIntent = Intent(Intent.ACTION_VIEW, Uri.parse(geoUri)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(mapIntent)
            }

            "ACTION_DISMISS" -> {
                val eventId = intent.getIntExtra("event_id", -1)
                Log.d(TAG, "用户已确认（关闭通知）: eventId=$eventId")
                // 通知已被系统自动移除（setAutoCancel = true），无需额外操作
            }

            else -> Log.w(TAG, "未知的通知动作: ${intent.action}")
        }
    }
}
