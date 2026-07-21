package com.chnloon.oigo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * 开机自启广播接收器。
 *
 * 当设备重启完成后，自动遍历数据库中的所有未过期日程，
 * 重新注册 AlarmManager 闹钟（因为重启后所有闹钟丢失）。
 *
 * 需要配合 AndroidManifest.xml 中的 RECEIVE_BOOT_COMPLETED 权限。
 *
 * 兼容性说明（Android 8+）：
 * 隐式广播接收器在应用至少被用户手动启动过一次后才生效。
 * 对于日程提醒 App 这是合理的 —— 用户需要用过后才有提醒需要。
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "OiGo_BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_LOCKED_BOOT_COMPLETED
        ) {
            return
        }

        Log.d(TAG, "收到开机广播: ${intent.action}")

        // Android 8+ 在锁屏状态下只能使用 direct boot aware 组件
        // 对于普通应用，ACTION_LOCKED_BOOT_COMPLETED 无法直接访问文件
        if (intent.action == Intent.ACTION_LOCKED_BOOT_COMPLETED) {
            Log.d(TAG, "跳过 LOCKED_BOOT_COMPLETED，等待完整启动")
            return
        }

        try {
            // 1. 从数据库读取并重建所有未过期提醒的 AlarmManager 闹钟
            MainActivity.rescheduleAllFromNative(context)

            // 2. 启动持久前台 Service（如尚未运行）
            //    开机后让 Service 持续运行，确保后续触发的提醒
            //    能通过 WindowManager 覆盖层立即弹出
            ReminderForegroundService.start(context)
            Log.d(TAG, "开机后已启动持久前台 Service")
        } catch (e: Exception) {
            Log.e(TAG, "开机重建失败: ${e.message}")
        }
    }
}
