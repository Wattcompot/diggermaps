package com.example.digger_maps.ozf

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.File
import java.io.IOException
import java.util.LinkedHashMap
import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.tan

internal object RasterTileReader {
    private const val OUTPUT_TILE_SIZE = 256
    private const val MAX_OPEN_FILES = 4
    private const val MAX_WEB_MERCATOR_LATITUDE = 85.05112878

    private val openFiles = object : LinkedHashMap<String, RasterFile>(
        MAX_OPEN_FILES,
        0.75f,
        true,
    ) {
        override fun removeEldestEntry(
            eldest: MutableMap.MutableEntry<String, RasterFile>?,
        ): Boolean {
            val remove = size > MAX_OPEN_FILES
            if (remove) eldest?.value?.close()
            return remove
        }
    }

    fun getTile(
        path: String,
        zoom: Int,
        x: Int,
        y: Int,
        minLatitude: Double,
        maxLatitude: Double,
        minLongitude: Double,
        maxLongitude: Double,
    ): ByteArray? = getFile(path).renderTile(
        zoom = zoom,
        tileX = x,
        tileY = y,
        minLatitude = minLatitude,
        maxLatitude = maxLatitude,
        minLongitude = minLongitude,
        maxLongitude = maxLongitude,
    )

    fun closeAll() {
        synchronized(openFiles) {
            openFiles.values.forEach(RasterFile::close)
            openFiles.clear()
        }
    }

    private fun getFile(path: String): RasterFile {
        val canonicalPath = File(path).canonicalPath
        synchronized(openFiles) {
            return openFiles[canonicalPath] ?: RasterFile(canonicalPath).also {
                openFiles[canonicalPath] = it
            }
        }
    }

    @Suppress("DEPRECATION")
    private class RasterFile(path: String) : Closeable {
        private val decoder = BitmapRegionDecoder.newInstance(path, false)
            ?: throw IOException("Не удалось открыть растровую карту")
        private val width = decoder.width
        private val height = decoder.height

        @Synchronized
        fun renderTile(
            zoom: Int,
            tileX: Int,
            tileY: Int,
            minLatitude: Double,
            maxLatitude: Double,
            minLongitude: Double,
            maxLongitude: Double,
        ): ByteArray? {
            if (zoom !in 0..30 || minLatitude >= maxLatitude) return null
            val worldSize = OUTPUT_TILE_SIZE * 2.0.pow(zoom)
            val westPixel = longitudeToWorldPixelX(minLongitude, zoom)
            val eastLongitude = minLongitude + longitudeSpan(minLongitude, maxLongitude)
            val eastPixel = longitudeToWorldPixelX(eastLongitude, zoom)
            val northPixel = latitudeToWorldPixelY(maxLatitude, zoom)
            val southPixel = latitudeToWorldPixelY(minLatitude, zoom)
            if (eastPixel <= westPixel || southPixel <= northPixel) return null

            var worldLeft = tileX * OUTPUT_TILE_SIZE.toDouble()
            if (eastPixel > worldSize && worldLeft + OUTPUT_TILE_SIZE <= westPixel) {
                worldLeft += worldSize
            }
            val worldTop = tileY * OUTPUT_TILE_SIZE.toDouble()
            val worldRight = worldLeft + OUTPUT_TILE_SIZE
            val worldBottom = worldTop + OUTPUT_TILE_SIZE
            if (
                worldRight <= westPixel || worldLeft >= eastPixel ||
                worldBottom <= northPixel || worldTop >= southPixel
            ) return null

            val scaleX = (eastPixel - westPixel) / width
            val scaleY = (southPixel - northPixel) / height
            val sourceLeft = floor((max(worldLeft, westPixel) - westPixel) / scaleX)
                .toInt().coerceIn(0, width)
            val sourceTop = floor((max(worldTop, northPixel) - northPixel) / scaleY)
                .toInt().coerceIn(0, height)
            val sourceRight = ceil((min(worldRight, eastPixel) - westPixel) / scaleX)
                .toInt().coerceIn(0, width)
            val sourceBottom = ceil((min(worldBottom, southPixel) - northPixel) / scaleY)
                .toInt().coerceIn(0, height)
            if (sourceLeft >= sourceRight || sourceTop >= sourceBottom) return null

            val sourceRect = Rect(sourceLeft, sourceTop, sourceRight, sourceBottom)
            val sampleScale = max(
                sourceRect.width() / OUTPUT_TILE_SIZE.toDouble(),
                sourceRect.height() / OUTPUT_TILE_SIZE.toDouble(),
            )
            var sampleSize = 1
            while (sampleSize * 2 <= sampleScale) sampleSize *= 2
            val region = decoder.decodeRegion(
                sourceRect,
                BitmapFactory.Options().apply {
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                    inSampleSize = sampleSize
                },
            ) ?: return null
            val output = Bitmap.createBitmap(
                OUTPUT_TILE_SIZE,
                OUTPUT_TILE_SIZE,
                Bitmap.Config.ARGB_8888,
            )
            try {
                output.eraseColor(Color.TRANSPARENT)
                val destination = RectF(
                    (max(worldLeft, westPixel) - worldLeft).toFloat(),
                    (max(worldTop, northPixel) - worldTop).toFloat(),
                    (min(worldRight, eastPixel) - worldLeft).toFloat(),
                    (min(worldBottom, southPixel) - worldTop).toFloat(),
                )
                Canvas(output).drawBitmap(
                    region,
                    null,
                    destination,
                    Paint(Paint.FILTER_BITMAP_FLAG),
                )
                return ByteArrayOutputStream(48 * 1024).use { bytes ->
                    if (!output.compress(Bitmap.CompressFormat.PNG, 100, bytes)) {
                        throw IOException("Не удалось закодировать тайл растра")
                    }
                    bytes.toByteArray()
                }
            } finally {
                region.recycle()
                output.recycle()
            }
        }

        override fun close() = decoder.recycle()
    }

    private fun longitudeSpan(west: Double, east: Double): Double =
        if (east >= west) east - west else east + 360.0 - west

    private fun longitudeToWorldPixelX(longitude: Double, zoom: Int): Double =
        (longitude + 180.0) / 360.0 * OUTPUT_TILE_SIZE * 2.0.pow(zoom)

    private fun latitudeToWorldPixelY(latitude: Double, zoom: Int): Double {
        val radians = latitude.coerceIn(
            -MAX_WEB_MERCATOR_LATITUDE,
            MAX_WEB_MERCATOR_LATITUDE,
        ) * PI / 180.0
        return (1.0 - ln(tan(radians) + 1.0 / cos(radians)) / PI) / 2.0 *
            OUTPUT_TILE_SIZE * 2.0.pow(zoom)
    }
}
