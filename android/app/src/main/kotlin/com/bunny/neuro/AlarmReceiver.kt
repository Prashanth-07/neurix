package com.bunny.neuro

import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.util.Log

/**
 * BroadcastReceiver that handles alarm wake-up functionality.
 * This is called when the Flutter side sends a broadcast to wake up the device.
 */
class AlarmReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "AlarmReceiver"
        const val ACTION_WAKE_UP = "com.bunny.neuro.WAKE_UP_ALARM"
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Received broadcast: ${intent.action}")

        if (intent.action == ACTION_WAKE_UP) {
            wakeUpDevice(context)
            launchApp(context)
        }
    }

    private fun wakeUpDevice(context: Context) {
        try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager

            if (!powerManager.isInteractive) {
                Log.d(TAG, "Screen is off, waking up...")

                @Suppress("DEPRECATION")
                val wakeLock = powerManager.newWakeLock(
                    PowerManager.FULL_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    PowerManager.ON_AFTER_RELEASE,
                    "neurix:alarm_receiver_wake_lock"
                )
                wakeLock.acquire(10000L) // 10 seconds
                wakeLock.release()
                Log.d(TAG, "Wake lock acquired and released")
            } else {
                Log.d(TAG, "Screen is already on")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error waking up device: ${e.message}")
        }
    }

    private fun launchApp(context: Context) {
        try {
            Log.d(TAG, "Launching MainActivity...")

            val intent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra("from_alarm", true)
            }
            context.startActivity(intent)

            Log.d(TAG, "MainActivity launch intent sent")
        } catch (e: Exception) {
            Log.e(TAG, "Error launching app: ${e.message}")
        }
    }
}
