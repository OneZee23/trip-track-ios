import Foundation
import Compression

extension Data {
    /// Returns a gzip-encoded copy of this Data, or nil if compression fails.
    ///
    /// Wraps Compression.framework's raw DEFLATE output (`COMPRESSION_ZLIB`
    /// emits raw deflate, despite the name) with the standard gzip header
    /// (RFC 1952) and CRC-32 trailer so backend HTTP servers can decompress
    /// via the standard `Content-Encoding: gzip` path.
    ///
    /// Why this exists: Russian ISPs (Tele2, Beeline, MTS) DPI-throttle TLS
    /// streams larger than 16KB to certain DC ranges (DigitalOcean, Cloudflare).
    /// Trip uploads with hundreds of trackPoints are 30-80KB JSON. Gzipping
    /// brings them under the 16KB threshold (trackPoints are highly repetitive
    /// floats — gzip compresses them ~80%).
    func gzipped() -> Data? {
        let srcSize = count
        // Worst case for deflate is roughly source + 64 bytes; +1KB buffer
        // headroom is plenty for our trip JSON sizes.
        let dstCapacity = srcSize + 1024
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: dstCapacity)
        defer { dst.deallocate() }

        let compressedSize = withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
            guard let srcPtr = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(dst, dstCapacity, srcPtr, srcSize, nil, COMPRESSION_ZLIB)
        }
        guard compressedSize > 0 else { return nil }

        var out = Data(capacity: compressedSize + 18)
        // gzip header: magic(2) + method=8 (deflate) + flags=0 + mtime(4)=0
        //            + xfl=0 + os=255 (unknown). 10 bytes.
        out.append(contentsOf: [0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff])
        out.append(dst, count: compressedSize)

        var crc = crc32().littleEndian
        var isize = UInt32(srcSize & 0xffffffff).littleEndian
        Swift.withUnsafeBytes(of: &crc) { out.append(contentsOf: $0) }
        Swift.withUnsafeBytes(of: &isize) { out.append(contentsOf: $0) }
        return out
    }

    /// CRC-32 per RFC 1952. Per-byte loop is fine for our typical body
    /// sizes (~50KB) — runs in microseconds and avoids pulling in a
    /// table-based crate.
    private func crc32() -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in self {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                let mask: UInt32 = (crc & 1) == 1 ? 0xEDB88320 : 0
                crc = (crc >> 1) ^ mask
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}
