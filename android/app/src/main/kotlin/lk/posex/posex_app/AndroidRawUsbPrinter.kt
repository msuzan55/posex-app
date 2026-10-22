package lk.posex.posex_app

import android.content.Context
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.util.Log

/**
 * Direct RAW USB bulk writes for ESC/POS / ZPL thermal printers.
 *
 * Replaces flutter_thermal_printer's Android [printText], which always claims
 * interface(0), sends the whole payload in one [UsbDeviceConnection.bulkTransfer],
 * and closes immediately — a common source of mangled receipts on OTG printers
 * (especially with raster logos). Windows already bypasses that plugin via the
 * spooler RAW path; this is the Android equivalent.
 */
object AndroidRawUsbPrinter {
    private const val TAG = "PosExUsbRaw"
    private const val TRANSFER_TIMEOUT_MS = 5_000
    /** Cap each bulk write; keep a multiple of typical maxPacketSize (64/512). */
    private const val MAX_CHUNK = 16_384
    /** Let the printer drain its buffer after large jobs before releasing USB. */
    private const val SETTLE_MS_PER_KIB = 2
    private const val SETTLE_MS_MIN = 50
    private const val SETTLE_MS_MAX = 2_000

    fun printBytes(
        context: Context,
        vendorId: String,
        productId: String,
        data: ByteArray,
    ) {
        if (data.isEmpty()) {
            throw IllegalArgumentException("print payload is empty")
        }
        val manager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val device = findDevice(manager, vendorId, productId)
            ?: throw IllegalStateException(
                "USB printer not found ($vendorId:$productId)",
            )
        if (!manager.hasPermission(device)) {
            throw IllegalStateException(
                "USB permission not granted for ${device.deviceName}",
            )
        }

        val iface = findPrinterInterface(device)
            ?: throw IllegalStateException("No USB bulk-OUT interface on printer")
        val endpoint = findBulkOutEndpoint(iface)
            ?: throw IllegalStateException("No USB bulk-OUT endpoint on printer")

        val connection = manager.openDevice(device)
            ?: throw IllegalStateException("Could not open USB device")

        try {
            if (!connection.claimInterface(iface, true)) {
                throw IllegalStateException("Could not claim USB interface ${iface.id}")
            }
            try {
                writeChunked(connection, endpoint, data)
                settleAfterWrite(data.size)
            } finally {
                try {
                    connection.releaseInterface(iface)
                } catch (e: Exception) {
                    Log.w(TAG, "releaseInterface: ${e.message}")
                }
            }
        } finally {
            connection.close()
        }
    }

    private fun findDevice(
        manager: UsbManager,
        vendorId: String,
        productId: String,
    ): UsbDevice? {
        val wantVendor = vendorId.trim()
        val wantProduct = productId.trim()
        for (device in manager.deviceList.values) {
            if (device.vendorId.toString() != wantVendor) continue
            if (wantProduct.isNotEmpty() &&
                wantProduct != "N/A" &&
                device.productId.toString() != wantProduct
            ) {
                continue
            }
            return device
        }
        return null
    }

    /**
     * Prefer USB Printer Class (0x07); otherwise first interface that has a bulk OUT.
     * flutter_thermal_printer always used interface(0), which is wrong on composite devices.
     */
    private fun findPrinterInterface(device: UsbDevice): UsbInterface? {
        var fallback: UsbInterface? = null
        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            if (findBulkOutEndpoint(iface) == null) continue
            if (iface.interfaceClass == UsbConstants.USB_CLASS_PRINTER) {
                return iface
            }
            if (fallback == null) fallback = iface
        }
        return fallback
    }

    private fun findBulkOutEndpoint(iface: UsbInterface): UsbEndpoint? {
        for (e in 0 until iface.endpointCount) {
            val ep = iface.getEndpoint(e)
            if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK &&
                ep.direction == UsbConstants.USB_DIR_OUT
            ) {
                return ep
            }
        }
        return null
    }

    private fun writeChunked(
        connection: UsbDeviceConnection,
        endpoint: UsbEndpoint,
        data: ByteArray,
    ) {
        val packet = endpoint.maxPacketSize.coerceAtLeast(1)
        // Align chunk size to packet size; never exceed MAX_CHUNK.
        var chunkSize = MAX_CHUNK / packet * packet
        if (chunkSize < packet) chunkSize = packet

        var offset = 0
        while (offset < data.size) {
            val len = minOf(chunkSize, data.size - offset)
            val written = connection.bulkTransfer(
                endpoint,
                data,
                offset,
                len,
                TRANSFER_TIMEOUT_MS,
            )
            if (written < 0) {
                throw IllegalStateException(
                    "USB bulkTransfer failed at offset $offset/$len " +
                        "(maxPacket=$packet)",
                )
            }
            if (written == 0) {
                throw IllegalStateException(
                    "USB bulkTransfer wrote 0 bytes at offset $offset",
                )
            }
            offset += written
        }
    }

    private fun settleAfterWrite(byteCount: Int) {
        val ms = (byteCount / 1024 * SETTLE_MS_PER_KIB)
            .coerceIn(SETTLE_MS_MIN, SETTLE_MS_MAX)
        try {
            Thread.sleep(ms.toLong())
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
    }
}
