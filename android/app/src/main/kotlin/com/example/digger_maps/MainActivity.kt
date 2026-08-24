package com.example.digger_maps

import android.app.Activity
import android.content.Intent
import android.speech.RecognizerIntent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import com.example.digger_maps.ozf.OzfTileReader
import com.example.digger_maps.ozf.RasterTileReader
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val speechRequestCode = 4317
    private var speechResult: MethodChannel.Result? = null

    private val ozfChannel = "com.diggermaps/ozf_decoder"
    private val ozfTileExecutor = Executors.newFixedThreadPool(2)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "digger_maps/share")
            .setMethodCallHandler { call, result ->
                if (call.method != "shareText") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val text = call.argument<String>("text").orEmpty()
                val intent = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, text)
                }
                startActivity(Intent.createChooser(intent, "Поделиться координатами"))
                result.success(null)
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "digger_maps/speech")
            .setMethodCallHandler { call, result ->
                if (call.method != "recognize") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (speechResult != null) {
                    result.error("busy", "Voice recognition is already active", null)
                    return@setMethodCallHandler
                }
                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
                    putExtra(RecognizerIntent.EXTRA_PROMPT, "Название точки")
                }
                if (intent.resolveActivity(packageManager) == null) {
                    result.error("unavailable", "Voice recognition is unavailable", null)
                    return@setMethodCallHandler
                }
                speechResult = result
                startActivityForResult(intent, speechRequestCode)
            }

        configureOzfTileReader(flutterEngine)
    }

    private fun configureOzfTileReader(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ozfChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getTile" -> {
                        val ozfPath = call.argument<String>("ozfPath")
                        val zoom = call.argument<Int>("zoom")
                        val x = call.argument<Int>("x")
                        val y = call.argument<Int>("y")
                        val minLatitude = call.argument<Double>("minLatitude")
                        val maxLatitude = call.argument<Double>("maxLatitude")
                        val minLongitude = call.argument<Double>("minLongitude")
                        val maxLongitude = call.argument<Double>("maxLongitude")
                        if (
                            ozfPath.isNullOrBlank() ||
                            zoom == null ||
                            x == null ||
                            y == null ||
                            minLatitude == null ||
                            maxLatitude == null ||
                            minLongitude == null ||
                            maxLongitude == null
                        ) {
                            result.error(
                                "INVALID_ARGS",
                                "Не переданы путь OZF, координаты тайла или границы карты",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        ozfTileExecutor.execute {
                            try {
                                val tile = OzfTileReader.getTile(
                                    path = ozfPath,
                                    zoom = zoom,
                                    x = x,
                                    y = y,
                                    minLatitude = minLatitude,
                                    maxLatitude = maxLatitude,
                                    minLongitude = minLongitude,
                                    maxLongitude = maxLongitude,
                                )
                                runOnUiThread { result.success(tile) }
                            } catch (error: Throwable) {
                                runOnUiThread {
                                    result.error(
                                        "OZF_TILE_ERROR",
                                        error.message ?: "Не удалось прочитать тайл OZF",
                                        error.javaClass.simpleName,
                                    )
                                }
                            }
                        }
                    }

                    "getRasterTile" -> {
                        val imagePath = call.argument<String>("imagePath")
                        val zoom = call.argument<Int>("zoom")
                        val x = call.argument<Int>("x")
                        val y = call.argument<Int>("y")
                        val minLatitude = call.argument<Double>("minLatitude")
                        val maxLatitude = call.argument<Double>("maxLatitude")
                        val minLongitude = call.argument<Double>("minLongitude")
                        val maxLongitude = call.argument<Double>("maxLongitude")
                        if (
                            imagePath.isNullOrBlank() || zoom == null || x == null || y == null ||
                            minLatitude == null || maxLatitude == null ||
                            minLongitude == null || maxLongitude == null
                        ) {
                            result.error("INVALID_ARGS", "Не переданы путь растра, координаты тайла или границы", null)
                            return@setMethodCallHandler
                        }
                        ozfTileExecutor.execute {
                            try {
                                val tile = RasterTileReader.getTile(
                                    path = imagePath,
                                    zoom = zoom,
                                    x = x,
                                    y = y,
                                    minLatitude = minLatitude,
                                    maxLatitude = maxLatitude,
                                    minLongitude = minLongitude,
                                    maxLongitude = maxLongitude,
                                )
                                runOnUiThread { result.success(tile) }
                            } catch (error: Throwable) {
                                runOnUiThread {
                                    result.error(
                                        "RASTER_TILE_ERROR",
                                        error.message ?: "Не удалось прочитать тайл растра",
                                        error.javaClass.simpleName,
                                    )
                                }
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != speechRequestCode) return
        val pending = speechResult ?: return
        speechResult = null
        if (resultCode == Activity.RESULT_OK) {
            val matches = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
            pending.success(matches?.firstOrNull())
        } else {
            pending.success(null)
        }
    }

    override fun onDestroy() {
        ozfTileExecutor.shutdownNow()
        OzfTileReader.closeAll()
        RasterTileReader.closeAll()
        super.onDestroy()
    }
}
