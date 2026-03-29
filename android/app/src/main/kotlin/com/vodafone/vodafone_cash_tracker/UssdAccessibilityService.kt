package com.vodafone.vodafone_cash_tracker

import android.accessibilityservice.AccessibilityService
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import io.flutter.plugin.common.EventChannel
import kotlin.math.abs
import java.io.File
import java.io.FileOutputStream

class UssdAccessibilityService : AccessibilityService() {

    companion object {
        var eventSink: EventChannel.EventSink? = null
        var activePin: String? = null
        /** Matches Flutter [sessionId] for this dial; every event is tagged so late screenshots cannot attach to the wrong request. */
        var activeSessionId: String? = null

        private val mainHandler = Handler(Looper.getMainLooper())
        private var pinDelayRunnable: Runnable? = null
        private var pinDelayScheduled = false
        private var lastEmittedFeePreview: Double? = null

        private const val PIN_DELAY_MS = 8000L
        /** After PIN is sent, wait for the success dialog to fully render before screenshot. */
        private const val POST_PIN_SUCCESS_DELAY_MS = 3500L

        private var successConfirmRunnable: Runnable? = null

        /** Call before each USSD dial so PIN delay / fee preview state resets. */
        fun prepareNewUssdSession(pin: String?, sessionId: String?) {
            pinDelayRunnable?.let { mainHandler.removeCallbacks(it) }
            pinDelayRunnable = null
            pinDelayScheduled = false
            lastEmittedFeePreview = null
            successConfirmRunnable?.let { mainHandler.removeCallbacks(it) }
            successConfirmRunnable = null
            activePin = pin
            activeSessionId = sessionId?.trim()?.takeIf { it.isNotEmpty() }
        }
    }

    private var lastResultText = ""

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        
        // Clear result cache when a new operation starts
        if (activePin != null && lastResultText.isNotEmpty()) {
            lastResultText = ""
        }

        if (activePin == null) {
            // Check for results if no active PIN operation is pending
            val rootNode = rootInActiveWindow ?: return
            handleCaptureResult(rootNode)
            return
        }

        // 1. PIN Handling Automation Loop
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED || event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {
            val roots = mutableListOf<AccessibilityNodeInfo>()
            rootInActiveWindow?.let { roots.add(it) }
            
            // On some devices, the USSD dialog is not the 'active' window but an interactive one
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                try {
                    windows?.forEach { window ->
                        if (window != null) {
                            window.root?.let { if (!roots.contains(it)) roots.add(it) }
                        }
                    }
                } catch (e: Exception) {
                    Log.e("USSD", "Error fetching windows: ${e.message}")
                }
            }

            for (root in roots) {
                if (root == null) continue
                tryEmitFeePreview(root)
            }

            for (root in roots) {
                if (root == null) continue
                findEditText(root)?.let { editText ->
                    if (activePin != null && (editText.text == null || editText.text.isEmpty())) {
                        if (!pinDelayScheduled) {
                            pinDelayScheduled = true
                            sendUpdate("STATUS:WAITING_PIN_MS:$PIN_DELAY_MS")
                            pinDelayRunnable = Runnable {
                                pinDelayRunnable = null
                                injectPinAndSend()
                            }
                            mainHandler.postDelayed(pinDelayRunnable!!, PIN_DELAY_MS)
                        }
                        return
                    }
                }

                handleCaptureResult(root)
            }
        }
    }

    private fun tryEmitFeePreview(root: AccessibilityNodeInfo) {
        val allText = getAllText(root)
        if (allText.isEmpty()) return
        val fee = extractFee(allText) ?: return
        if (lastEmittedFeePreview != null && abs(fee - lastEmittedFeePreview!!) < 0.001) return
        lastEmittedFeePreview = fee
        sendUpdate("FEE_DETECTED:$fee")
    }

    private fun injectPinAndSend() {
        val pin = activePin ?: return
        val roots = mutableListOf<AccessibilityNodeInfo>()
        rootInActiveWindow?.let { roots.add(it) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                windows?.forEach { window ->
                    window?.root?.let { if (!roots.contains(it)) roots.add(it) }
                }
            } catch (e: Exception) {
                Log.e("USSD", "injectPin windows: ${e.message}")
            }
        }
        for (root in roots) {
            findEditText(root)?.let { editText ->
                if (editText.text == null || editText.text.isEmpty()) {
                    editText.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
                    val arguments = Bundle()
                    arguments.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, pin)
                    val setOk = editText.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
                    if (setOk) {
                        findButton(root, "Send", "OK", "ارسال", "إرسال", "موافق", "Send")
                            ?.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                        activePin = null
                        pinDelayScheduled = false
                        sendUpdate("STATUS:PIN_ENTERED")
                        return
                    }
                }
            }
        }
        Log.w("USSD", "injectPinAndSend: empty PIN field not found after delay")
        pinDelayScheduled = false
    }

    private fun handleCaptureResult(rootNode: AccessibilityNodeInfo) {
        val allText = getAllText(rootNode)
        
        // Prevent duplicate processing of the same result
        if (allText.isEmpty() || allText == lastResultText) return

        val isSuccess = allText.contains("تم تحويل") || allText.contains("Success") || allText.contains("Transaction successful")
        val isError = allText.contains("Error") || allText.contains("خطأ") || allText.contains("تعذر") || allText.contains("Invalid")

        if (isSuccess || isError) {
            lastResultText = allText

            if (isSuccess) {
                val sidForThisShot = activeSessionId
                val snapshotText = allText
                val snapshotFee = extractFee(allText)

                successConfirmRunnable?.let { mainHandler.removeCallbacks(it) }
                sendUpdate(
                    "STATUS:WAITING_SUCCESS_MS:$POST_PIN_SUCCESS_DELAY_MS",
                    sessionForEnvelope = sidForThisShot
                )

                successConfirmRunnable = Runnable {
                    successConfirmRunnable = null
                    completeSuccessAfterPinDelay(sidForThisShot, snapshotText, snapshotFee)
                }
                mainHandler.postDelayed(successConfirmRunnable!!, POST_PIN_SUCCESS_DELAY_MS)

                activePin = null
                pinDelayScheduled = false
                pinDelayRunnable?.let { mainHandler.removeCallbacks(it) }
                pinDelayRunnable = null
                return
            }

            sendUpdate("ERROR: $allText")

            Handler(Looper.getMainLooper()).postDelayed({
                findButton(rootNode, "Cancel", "Dismiss", "OK", "إلغاء", "الغاء", "موافق", "إغلاق", "Close", "Done", "تم")
                    ?.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            }, 1000)

            activePin = null
            pinDelayScheduled = false
            pinDelayRunnable?.let { mainHandler.removeCallbacks(it) }
            pinDelayRunnable = null
        }
    }

    private fun collectAllRoots(): List<AccessibilityNodeInfo> {
        val roots = mutableListOf<AccessibilityNodeInfo>()
        rootInActiveWindow?.let { roots.add(it) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                windows?.forEach { window ->
                    window?.root?.let { r ->
                        if (!roots.contains(r)) roots.add(r)
                    }
                }
            } catch (e: Exception) {
                Log.e("USSD", "collectAllRoots: ${e.message}")
            }
        }
        return roots
    }

    private fun dismissUssdDialogFromAnyWindow() {
        val labels = arrayOf("Cancel", "Dismiss", "OK", "إلغاء", "الغاء", "موافق", "إغلاق", "Close", "Done", "تم")
        for (root in collectAllRoots()) {
            val b = findButton(root, *labels)
            if (b != null && b.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                return
            }
        }
    }

    /**
     * Re-scan UI after POST_PIN_SUCCESS_DELAY_MS so the success dialog is stable, then SUCCESS + crop + screenshot + dismiss.
     */
    private fun completeSuccessAfterPinDelay(
        sidForThisShot: String?,
        fallbackText: String,
        fallbackFee: Double?
    ) {
        val roots = collectAllRoots()
        var mergedText = ""
        var bestRoot: AccessibilityNodeInfo? = null
        for (root in roots) {
            val t = getAllText(root)
            if (t.isEmpty()) continue
            val ok = t.contains("تم تحويل") || t.contains("Success") || t.contains("Transaction successful")
            if (ok && t.length >= mergedText.length) {
                mergedText = t
                bestRoot = root
            }
        }
        if (mergedText.isEmpty()) {
            mergedText = fallbackText
            bestRoot = rootInActiveWindow
        }

        val feeValue = extractFee(mergedText) ?: fallbackFee
        val feeSuffix = if (feeValue != null) " | FEE: $feeValue" else ""
        sendUpdate("SUCCESS: $mergedText$feeSuffix", sessionForEnvelope = sidForThisShot)

        val cropRectScreen = if (bestRoot != null) {
            computeDialogCropRect(bestRoot)
        } else {
            val dm = resources.displayMetrics
            Rect(0, 0, dm.widthPixels, dm.heightPixels)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            takeScreenshot(0, mainExecutor, object : TakeScreenshotCallback {
                override fun onSuccess(screenshot: ScreenshotResult) {
                    val bitmap = Bitmap.wrapHardwareBuffer(screenshot.hardwareBuffer, screenshot.colorSpace)
                    if (bitmap != null) {
                        val cropped = cropBitmapToScreenRect(bitmap, cropRectScreen)
                        val path = saveScreenshot(cropped)
                        sendUpdate("SCREENSHOT: $path", sessionForEnvelope = sidForThisShot)
                    }
                    mainHandler.postDelayed({ dismissUssdDialogFromAnyWindow() }, 500)
                }

                override fun onFailure(errorCode: Int) {
                    Log.e("USSD", "Screenshot failed: $errorCode")
                    dismissUssdDialogFromAnyWindow()
                }
            })
        } else {
            mainHandler.postDelayed({ dismissUssdDialogFromAnyWindow() }, 500)
        }
    }

    private fun extractFee(text: String): Double? {
        val patterns = listOf(
            "بالإضافة ل\\s*([0-9.]+)\\s*ج\\s*رسوم".toRegex(),
            "بالاضافة ل\\s*([0-9.]+)\\s*ج\\.م".toRegex(),
            "([0-9.]+)\\s*ج\\.م\\s*رسوم".toRegex(),
            "رسوم\\s*[:：]?\\s*([0-9.]+)".toRegex(),
            "plus\\s*([0-9.]+)\\s*EGP\\s*fees".toRegex(RegexOption.IGNORE_CASE),
            "fee of\\s*([0-9.]+)\\s*EGP".toRegex(RegexOption.IGNORE_CASE),
            "([0-9.]+)\\s*EGP\\s*fee".toRegex(RegexOption.IGNORE_CASE)
        )
        for (pattern in patterns) {
            val match = pattern.find(text)
            if (match != null) {
                return match.groupValues[1].toDoubleOrNull()
            }
        }
        return null
    }

    private fun findEditText(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val deque = ArrayDeque<AccessibilityNodeInfo>()
        deque.add(root)
        while (deque.isNotEmpty()) {
            val node = deque.removeFirst()
            if (isInputNode(node)) return node
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { deque.add(it) }
            }
        }
        return null
    }

    private fun isInputNode(node: AccessibilityNodeInfo): Boolean {
        val className = node.className?.toString() ?: ""
        return className.contains("EditText") || node.isEditable
    }

    private fun findButton(root: AccessibilityNodeInfo, vararg labels: String): AccessibilityNodeInfo? {
        val deque = ArrayDeque<AccessibilityNodeInfo>()
        deque.add(root)
        while (deque.isNotEmpty()) {
            val node = deque.removeFirst()
            val className = node.className?.toString() ?: ""
            if (className.contains("Button")) {
                val text = node.text?.toString() ?: ""
                if (labels.any { it.equals(text, ignoreCase = true) }) return node
            }
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { deque.add(it) }
            }
        }
        return null
    }

    private fun getAllText(root: AccessibilityNodeInfo): String {
        val sb = StringBuilder()
        val deque = ArrayDeque<AccessibilityNodeInfo>()
        deque.add(root)
        while (deque.isNotEmpty()) {
            val node = deque.removeFirst()
            node.text?.let { sb.append(it).append(" ") }
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { deque.add(it) }
            }
        }
        return sb.toString().trim()
    }

    private fun sendUpdate(raw: String, sessionForEnvelope: String? = null) {
        val sid = sessionForEnvelope ?: activeSessionId
        val out = if (sid.isNullOrEmpty()) raw else "USSD2:$sid:$raw"
        Handler(Looper.getMainLooper()).post {
            eventSink?.success(out)
        }
    }

    /**
     * Finds a rect in screen coordinates that covers the USSD / success dialog (not the full display).
     */
    private fun computeDialogCropRect(rootNode: AccessibilityNodeInfo): Rect {
        val dm = resources.displayMetrics
        val sw = dm.widthPixels
        val sh = dm.heightPixels

        val textNode = findNodeWithSuccessText(rootNode)
        if (textNode != null) {
            val r = Rect()
            var node: AccessibilityNodeInfo? = textNode
            repeat(14) {
                if (node == null) return@repeat
                node!!.getBoundsInScreen(r)
                val rw = r.width()
                val rh = r.height()
                val area = rw * rh
                val looksLikeDialog =
                    rw >= (sw * 0.38f).toInt() &&
                        rw <= sw &&
                        rh >= (sh * 0.08f).toInt() &&
                        rh <= (sh * 0.90f).toInt() &&
                        area < (sw * sh * 0.90f).toInt()
                if (looksLikeDialog) {
                    expandRect(r, 32, sw, sh)
                    return Rect(r)
                }
                node = node!!.parent
            }
            textNode.getBoundsInScreen(r)
            var n: AccessibilityNodeInfo? = textNode.parent
            repeat(6) {
                if (n == null) return@repeat
                n!!.getBoundsInScreen(r)
                if (r.width() > sw / 4 && r.height() > sh / 25) {
                    expandRect(r, 48, sw, sh)
                    return Rect(r)
                }
                n = n!!.parent
            }
            textNode.getBoundsInScreen(r)
            expandRect(r, 96, sw, sh)
            return r
        }

        val root = Rect()
        rootNode.getBoundsInScreen(root)
        if (root.width() < sw * 92 / 100 && root.height() < sh * 92 / 100) {
            expandRect(root, 24, sw, sh)
            return root
        }
        return centeredUssdFallback(sw, sh)
    }

    private fun findNodeWithSuccessText(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val markers = listOf("تم تحويل", "Success", "Transaction successful")
        var found: AccessibilityNodeInfo? = null
        val deque = ArrayDeque<AccessibilityNodeInfo>()
        deque.add(root)
        while (deque.isNotEmpty()) {
            val n = deque.removeFirst()
            val tx = n.text?.toString() ?: ""
            val cd = n.contentDescription?.toString() ?: ""
            if (markers.any { m -> tx.contains(m) || cd.contains(m) }) {
                found = n
                break
            }
            for (i in 0 until n.childCount) {
                n.getChild(i)?.let { deque.add(it) }
            }
        }
        return found
    }

    private fun centeredUssdFallback(sw: Int, sh: Int): Rect {
        val w = (sw * 0.86f).toInt().coerceAtLeast(1)
        val h = (sh * 0.42f).toInt().coerceAtLeast(1)
        val left = (sw - w) / 2
        val top = (sh * 0.26f).toInt()
        return Rect(left, top, (left + w).coerceAtMost(sw), (top + h).coerceAtMost(sh))
    }

    private fun expandRect(r: Rect, pad: Int, maxW: Int, maxH: Int) {
        r.left = (r.left - pad).coerceAtLeast(0)
        r.top = (r.top - pad).coerceAtLeast(0)
        r.right = (r.right + pad).coerceAtMost(maxW)
        r.bottom = (r.bottom + pad).coerceAtMost(maxH)
    }

    /**
     * [screenRect] is in the same coordinate system as [Bitmap] from [takeScreenshot] (screen pixels).
     */
    private fun cropBitmapToScreenRect(full: Bitmap, screenRect: Rect): Bitmap {
        val bw = full.width
        val bh = full.height
        if (bw <= 0 || bh <= 0) return full

        // If display vs bitmap size differ (rare), scale rect to bitmap space.
        val dm = resources.displayMetrics
        val sx = bw.toFloat() / dm.widthPixels.toFloat()
        val sy = bh.toFloat() / dm.heightPixels.toFloat()
        val left = (screenRect.left * sx).toInt().coerceIn(0, bw - 1)
        val top = (screenRect.top * sy).toInt().coerceIn(0, bh - 1)
        val right = (screenRect.right * sx).toInt().coerceIn(left + 1, bw)
        val bottom = (screenRect.bottom * sy).toInt().coerceIn(top + 1, bh)
        if (right - left < 2 || bottom - top < 2) {
            return if (full.config == Bitmap.Config.HARDWARE) {
                full.copy(Bitmap.Config.ARGB_8888, true).also { full.recycle() }
            } else full
        }

        val src = if (full.config == Bitmap.Config.HARDWARE) {
            val copy = full.copy(Bitmap.Config.ARGB_8888, true)
            full.recycle()
            copy
        } else {
            full
        }

        val out = Bitmap.createBitmap(src, left, top, right - left, bottom - top)
        if (src !== out) src.recycle()
        return out
    }

    private fun saveScreenshot(bitmap: Bitmap): String {
        val dir = getExternalFilesDir(null) ?: File("/sdcard/Documents")
        val file = File(dir, "ussd_proof_${System.currentTimeMillis()}.jpg")
        FileOutputStream(file).use { out ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
        }
        bitmap.recycle()
        return file.absolutePath
    }

    override fun onInterrupt() {}
}
