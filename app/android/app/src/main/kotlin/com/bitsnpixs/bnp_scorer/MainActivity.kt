package com.bitsnpixs.bnp_scorer

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.ContactsContract.CommonDataKinds.Phone
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts Flutter, plus Android's own contact picker for adding a player by number.
 * The person taps one contact and only that contact's name and number come back:
 * the picker grants access to that one entry, so no contacts permission is asked for.
 */
class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "pickContact") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            pending?.success(null)
            pending = result
            try {
                startActivityForResult(Intent(Intent.ACTION_PICK, Phone.CONTENT_URI), PICK_CONTACT)
            } catch (e: ActivityNotFoundException) {
                pending = null
                result.error("no_picker", "No contacts app on this phone", null)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_CONTACT) return
        val result = pending ?: return
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            val picked = contentResolver.query(uri, arrayOf(Phone.DISPLAY_NAME, Phone.NUMBER), null, null, null)?.use {
                if (it.moveToFirst()) mapOf("name" to it.getString(0), "number" to it.getString(1)) else null
            }
            result.success(picked)
        } catch (e: SecurityException) {
            result.error("not_allowed", e.message, null)
        }
    }

    companion object {
        private const val CHANNEL = "com.bitsnpixs.bnp_scorer/contacts"
        private const val PICK_CONTACT = 4711
    }
}
