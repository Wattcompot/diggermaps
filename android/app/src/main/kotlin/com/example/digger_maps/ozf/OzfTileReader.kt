package com.example.digger_maps.ozf

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.util.LinkedHashMap
import java.util.zip.DataFormatException
import java.util.zip.Inflater
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.tan

internal object OzfTileReader {
    private const val FILE_HEADER_SIZE = 14
    private const val INITIAL_KEY_INDEX = 0x93
    private const val TILE_SIZE = 64
    private const val OUTPUT_TILE_SIZE = 256
    private const val ENCRYPTION_DEPTH = 16
    private const val MAX_OPEN_FILES = 4
    private const val MAX_DECODED_TILES = 256
    private const val MAX_WEB_MERCATOR_LATITUDE = 85.05112878

    private val decodeKey = byteArrayOf(
        0x2D, 0x4A, 0x43, 0xF1.toByte(), 0x27, 0x9B.toByte(), 0x69, 0x4F,
        0x36, 0x52, 0x87.toByte(), 0xEC.toByte(), 0x5F, 0x42, 0x53, 0x22,
        0x9E.toByte(), 0x8B.toByte(), 0x2D, 0x83.toByte(), 0x3D, 0xD2.toByte(),
        0x84.toByte(), 0xBA.toByte(), 0xD8.toByte(), 0x5B,
    )

    private val openFiles = object : LinkedHashMap<String, OzfFile>(
        MAX_OPEN_FILES,
        0.75f,
        true,
    ) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, OzfFile>?): Boolean {
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
    ): ByteArray? {
        val file = getFile(path)
        return file.renderTile(
            zoom = zoom,
            tileX = x,
            tileY = y,
            minLatitude = minLatitude,
            maxLatitude = maxLatitude,
            minLongitude = minLongitude,
            maxLongitude = maxLongitude,
        )
    }

    fun closeAll() {
        synchronized(openFiles) {
            openFiles.values.forEach(OzfFile::close)
            openFiles.clear()
        }
    }

    private fun getFile(path: String): OzfFile {
        val canonicalPath = File(path).canonicalPath
        synchronized(openFiles) {
            return openFiles[canonicalPath] ?: OzfFile(canonicalPath).also {
                openFiles[canonicalPath] = it
            }
        }
    }

    private data class ZoomLevel(
        val index: Int,
        val width: Int,
        val height: Int,
        val xTiles: Int,
        val yTiles: Int,
        val palette: IntArray,
        val tileOffsets: LongArray,
    )

    private data class NativeTileKey(val level: Int, val x: Int, val y: Int)

    private class OzfFile(path: String) : Closeable {
        private val input = RandomAccessFile(path, "r")
        private val encrypted: Boolean
        private val encryptionKey: Byte
        private val levels: List<ZoomLevel>
        private val decodedTiles = object : LinkedHashMap<NativeTileKey, IntArray>(
            MAX_DECODED_TILES,
            0.75f,
            true,
        ) {
            override fun removeEldestEntry(
                eldest: MutableMap.MutableEntry<NativeTileKey, IntArray>?,
            ): Boolean = size > MAX_DECODED_TILES
        }

        init {
            val header = readAndValidateHeader(input)
            encrypted = header.first
            encryptionKey = header.second
            levels = readLevels(input, encrypted, encryptionKey)
            if (levels.isEmpty()) throw IOException("В OZF не найдено уровней изображения")
        }

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

            var tileWorldLeft = tileX * OUTPUT_TILE_SIZE.toDouble()
            if (eastPixel > worldSize && tileWorldLeft + OUTPUT_TILE_SIZE <= westPixel) {
                tileWorldLeft += worldSize
            }
            val tileWorldTop = tileY * OUTPUT_TILE_SIZE.toDouble()
            val tileWorldRight = tileWorldLeft + OUTPUT_TILE_SIZE
            val tileWorldBottom = tileWorldTop + OUTPUT_TILE_SIZE
            if (
                tileWorldRight <= westPixel ||
                tileWorldLeft >= eastPixel ||
                tileWorldBottom <= northPixel ||
                tileWorldTop >= southPixel
            ) {
                return null
            }

            val level = chooseLevel(
                westPixel = westPixel,
                eastPixel = eastPixel,
                northPixel = northPixel,
                southPixel = southPixel,
            )
            val scaleX = (eastPixel - westPixel) / level.width
            val scaleY = (southPixel - northPixel) / level.height
            if (!scaleX.isFinite() || !scaleY.isFinite() || scaleX <= 0 || scaleY <= 0) {
                return null
            }

            val sourceLeft = floor((max(tileWorldLeft, westPixel) - westPixel) / scaleX)
                .toInt().coerceIn(0, level.width)
            val sourceTop = floor((max(tileWorldTop, northPixel) - northPixel) / scaleY)
                .toInt().coerceIn(0, level.height)
            val sourceRight = ceil((min(tileWorldRight, eastPixel) - westPixel) / scaleX)
                .toInt().coerceIn(0, level.width)
            val sourceBottom = ceil((min(tileWorldBottom, southPixel) - northPixel) / scaleY)
                .toInt().coerceIn(0, level.height)
            if (sourceLeft >= sourceRight || sourceTop >= sourceBottom) return null

            val output = Bitmap.createBitmap(
                OUTPUT_TILE_SIZE,
                OUTPUT_TILE_SIZE,
                Bitmap.Config.ARGB_8888,
            )
            val nativeTile = Bitmap.createBitmap(TILE_SIZE, TILE_SIZE, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(output)
            val paint = Paint(Paint.FILTER_BITMAP_FLAG)
            var drewTile = false
            try {
                output.eraseColor(Color.TRANSPARENT)
                val firstTileX = sourceLeft / TILE_SIZE
                val lastTileX = (sourceRight - 1) / TILE_SIZE
                val firstTileY = sourceTop / TILE_SIZE
                val lastTileY = (sourceBottom - 1) / TILE_SIZE
                for (ozfY in firstTileY..lastTileY) {
                    for (ozfX in firstTileX..lastTileX) {
                        if (ozfX !in 0 until level.xTiles || ozfY !in 0 until level.yTiles) {
                            continue
                        }
                        val pixels = readNativeTile(level, ozfX, ozfY) ?: continue
                        nativeTile.setPixels(pixels, 0, TILE_SIZE, 0, 0, TILE_SIZE, TILE_SIZE)
                        val imageLeft = ozfX * TILE_SIZE
                        val imageTop = ozfY * TILE_SIZE
                        val validWidth = min(TILE_SIZE, level.width - imageLeft)
                        val validHeight = min(TILE_SIZE, level.height - imageTop)
                        if (validWidth <= 0 || validHeight <= 0) continue
                        val destination = RectF(
                            (westPixel + imageLeft * scaleX - tileWorldLeft).toFloat(),
                            (northPixel + imageTop * scaleY - tileWorldTop).toFloat(),
                            (westPixel + (imageLeft + validWidth) * scaleX - tileWorldLeft).toFloat(),
                            (northPixel + (imageTop + validHeight) * scaleY - tileWorldTop).toFloat(),
                        )
                        canvas.drawBitmap(
                            nativeTile,
                            Rect(0, 0, validWidth, validHeight),
                            destination,
                            paint,
                        )
                        drewTile = true
                    }
                }
                if (!drewTile) return null
                return ByteArrayOutputStream(48 * 1024).use { bytes ->
                    if (!output.compress(Bitmap.CompressFormat.PNG, 100, bytes)) {
                        throw IOException("Не удалось закодировать тайл OZF")
                    }
                    bytes.toByteArray()
                }
            } finally {
                nativeTile.recycle()
                output.recycle()
            }
        }

        private fun chooseLevel(
            westPixel: Double,
            eastPixel: Double,
            northPixel: Double,
            southPixel: Double,
        ): ZoomLevel {
            return levels.minByOrNull { level ->
                val scaleX = (eastPixel - westPixel) / level.width
                val scaleY = (southPixel - northPixel) / level.height
                abs(ln(max(scaleX, scaleY).coerceAtLeast(1e-9)))
            } ?: levels.last()
        }

        private fun readNativeTile(level: ZoomLevel, tileX: Int, tileY: Int): IntArray? {
            val key = NativeTileKey(level.index, tileX, tileY)
            decodedTiles[key]?.let { return it }
            val index = tileY * level.xTiles + tileX
            if (index < 0 || index + 1 >= level.tileOffsets.size) return null
            val start = level.tileOffsets[index]
            val end = level.tileOffsets[index + 1]
            val compressedSize = end - start
            if (compressedSize <= 0 || compressedSize > Int.MAX_VALUE) return null

            val compressed = ByteArray(compressedSize.toInt())
            input.seek(start)
            input.readFully(compressed)
            if (encrypted) {
                decode(compressed, min(ENCRYPTION_DEPTH, compressed.size), encryptionKey)
            }

            val indices = ByteArray(TILE_SIZE * TILE_SIZE)
            val inflater = Inflater()
            try {
                inflater.setInput(compressed)
                var offset = 0
                while (offset < indices.size) {
                    val count = inflater.inflate(indices, offset, indices.size - offset)
                    if (count > 0) {
                        offset += count
                    } else if (inflater.finished() || inflater.needsInput() || inflater.needsDictionary()) {
                        break
                    } else {
                        throw IOException("Не удалось распаковать тайл OZF")
                    }
                }
                if (offset != indices.size) return null
            } catch (error: DataFormatException) {
                throw IOException("Повреждены данные тайла OZF", error)
            } finally {
                inflater.end()
            }

            val pixels = IntArray(TILE_SIZE * TILE_SIZE)
            for (destinationY in 0 until TILE_SIZE) {
                val sourceY = TILE_SIZE - 1 - destinationY
                val sourceOffset = sourceY * TILE_SIZE
                val destinationOffset = destinationY * TILE_SIZE
                for (column in 0 until TILE_SIZE) {
                    pixels[destinationOffset + column] =
                        level.palette[indices[sourceOffset + column].toInt() and 0xFF]
                }
            }
            decodedTiles[key] = pixels
            return pixels
        }

        override fun close() {
            decodedTiles.clear()
            input.close()
        }
    }

    private fun readAndValidateHeader(input: RandomAccessFile): Pair<Boolean, Byte> {
        val header = ByteArray(FILE_HEADER_SIZE)
        input.seek(0)
        input.readFully(header)
        val encrypted = header[0] == 0x80.toByte() && header[1] == 0x77.toByte()
        var encryptionKey: Byte = 0
        if (encrypted) {
            input.seek(FILE_HEADER_SIZE.toLong())
            val keyTableSize = input.readUnsignedByte()
            if (keyTableSize <= INITIAL_KEY_INDEX) {
                throw IOException("Повреждённый заголовок OZF3/OZFX3")
            }
            val keyTable = ByteArray(keyTableSize)
            input.readFully(keyTable)
            val initialKey = keyTable[INITIAL_KEY_INDEX]
            encryptionKey = ((initialKey.toInt() and 0xFF) + 0x8A).toByte()
            decode(header, header.size, initialKey)
        } else if (!(header[0] == 0x78.toByte() && header[1] == 0x77.toByte())) {
            throw IOException("Неподдерживаемая сигнатура OZF")
        }
        if (!(header[6] == 0x40.toByte() &&
                header[7] == 0x00.toByte() &&
                header[8] == 0x01.toByte() &&
                header[9] == 0x00.toByte() &&
                header[10] == 0x36.toByte() &&
                header[11] == 0x04.toByte() &&
                header[12] == 0x00.toByte() &&
                header[13] == 0x00.toByte()
            )
        ) {
            throw IOException("Некорректный заголовок OZF")
        }
        return encrypted to encryptionKey
    }

    private fun readLevels(
        input: RandomAccessFile,
        encrypted: Boolean,
        encryptionKey: Byte,
    ): List<ZoomLevel> {
        val numericBuffer = ByteArray(4)
        val fileLength = input.length()
        require(fileLength >= FILE_HEADER_SIZE + 4L) { "OZF-файл слишком короткий" }
        input.seek(fileLength - 4)
        val tableOffset = readLittleEndianInt(
            input,
            encrypted,
            encryptionKey,
            numericBuffer,
        ).toLong() and 0xFFFFFFFFL
        val tableBytes = fileLength - tableOffset - 4
        if (tableOffset <= 0 || tableBytes < 4 || tableBytes % 4L != 0L) {
            throw IOException("Повреждена таблица уровней OZF")
        }
        val imageCount = (tableBytes / 4L).toInt()
        input.seek(tableOffset)
        val imageOffsets = LongArray(imageCount) {
            readLittleEndianInt(input, encrypted, encryptionKey, numericBuffer)
                .toLong() and 0xFFFFFFFFL
        }

        val levels = mutableListOf<ZoomLevel>()
        for ((levelIndex, imageOffset) in imageOffsets.withIndex()) {
            if (imageOffset <= 0 || imageOffset >= fileLength) continue
            input.seek(imageOffset)
            val width = readLittleEndianInt(input, encrypted, encryptionKey, numericBuffer)
            val height = readLittleEndianInt(input, encrypted, encryptionKey, numericBuffer)
            val xTiles = readLittleEndianShort(input, encrypted, encryptionKey, numericBuffer)
            val yTiles = readLittleEndianShort(input, encrypted, encryptionKey, numericBuffer)
            if (width <= 0 || height <= 0 || xTiles <= 0 || yTiles <= 0) continue
            val paletteBytes = readBytes(input, 1024, encrypted, encryptionKey)
            val palette = IntArray(256) { index ->
                val offset = index * 4
                val blue = paletteBytes[offset].toInt() and 0xFF
                val green = paletteBytes[offset + 1].toInt() and 0xFF
                val red = paletteBytes[offset + 2].toInt() and 0xFF
                (0xFF shl 24) or (red shl 16) or (green shl 8) or blue
            }
            val tileCount = xTiles.toLong() * yTiles + 1L
            if (tileCount > Int.MAX_VALUE) throw IOException("Слишком много тайлов OZF")
            val offsets = LongArray(tileCount.toInt()) {
                readLittleEndianInt(input, encrypted, encryptionKey, numericBuffer)
                    .toLong() and 0xFFFFFFFFL
            }
            var valid = true
            for (index in 0 until offsets.lastIndex) {
                if (offsets[index] < 0 || offsets[index] > offsets[index + 1] || offsets[index + 1] > fileLength) {
                    valid = false
                    break
                }
            }
            if (!valid || max(width, height) == 300 || max(width, height) == 130) continue
            levels.add(
                ZoomLevel(
                    index = levelIndex,
                    width = width,
                    height = height,
                    xTiles = xTiles,
                    yTiles = yTiles,
                    palette = palette,
                    tileOffsets = offsets,
                ),
            )
        }
        return levels.sortedBy { it.width.toLong() * it.height }
    }

    private fun readLittleEndianInt(
        input: RandomAccessFile,
        encrypted: Boolean,
        encryptionKey: Byte,
        buffer: ByteArray,
    ): Int {
        readIntoBuffer(input, buffer, 4, encrypted, encryptionKey)
        return (buffer[0].toInt() and 0xFF) or
            ((buffer[1].toInt() and 0xFF) shl 8) or
            ((buffer[2].toInt() and 0xFF) shl 16) or
            ((buffer[3].toInt() and 0xFF) shl 24)
    }

    private fun readLittleEndianShort(
        input: RandomAccessFile,
        encrypted: Boolean,
        encryptionKey: Byte,
        buffer: ByteArray,
    ): Int {
        readIntoBuffer(input, buffer, 2, encrypted, encryptionKey)
        return (buffer[0].toInt() and 0xFF) or ((buffer[1].toInt() and 0xFF) shl 8)
    }

    private fun readIntoBuffer(
        input: RandomAccessFile,
        buffer: ByteArray,
        size: Int,
        encrypted: Boolean,
        encryptionKey: Byte,
    ) {
        input.readFully(buffer, 0, size)
        if (encrypted) decode(buffer, size, encryptionKey)
    }

    private fun readBytes(
        input: RandomAccessFile,
        size: Int,
        encrypted: Boolean,
        encryptionKey: Byte,
    ): ByteArray {
        val bytes = ByteArray(size)
        input.readFully(bytes)
        if (encrypted) decode(bytes, bytes.size, encryptionKey)
        return bytes
    }

    private fun decode(bytes: ByteArray, length: Int, key: Byte) {
        val unsignedKey = key.toInt() and 0xFF
        for (index in 0 until length) {
            val mask = (decodeKey[index % decodeKey.size].toInt() + unsignedKey) and 0xFF
            bytes[index] = ((bytes[index].toInt() and 0xFF) xor mask).toByte()
        }
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
        val normalized = (1.0 - ln(tan(radians) + 1.0 / cos(radians)) / PI) / 2.0
        return normalized * OUTPUT_TILE_SIZE * 2.0.pow(zoom)
    }
}
