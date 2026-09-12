import 'dart:typed_data';

/// Distributed Display Protocol — the UDP format for streaming pixels to an
/// ESP32.
///
/// This is the way out of everything the BLE controllers imposed. Instead of
/// asking a controller to run one of its own effects, the app sends the actual
/// pixel values, sixty times a second. Per-pixel shapes, real colour and true
/// decay curves all follow from that.
///
/// Understood by WLED out of the box on port 4048, and by the sketch in
/// `firmware/StromSync_S3`.
class Ddp {
  Ddp._();

  static const int port = 4048;

  /// Header is ten bytes, then the pixel payload.
  static const int headerLength = 10;

  /// Version 1, with the push bit set so the receiver displays the frame as
  /// soon as it lands rather than waiting for more.
  static const int flagsVersion1 = 0x40;
  static const int flagsPush = 0x01;

  /// Eight bits per channel, three channels — plain RGB.
  static const int dataTypeRgb24 = 0x01;

  /// The receiver's default output.
  static const int defaultDestination = 1;

  /// Most networks will not carry a UDP datagram much past this without
  /// fragmenting it, and a fragmented frame is a dropped frame. 480 pixels of
  /// RGB fits comfortably inside a standard MTU.
  static const int maxPixelsPerPacket = 480;

  /// Builds the packets for one frame of [pixels], as packed RGB bytes.
  ///
  /// A strip longer than [maxPixelsPerPacket] is split across several packets,
  /// each carrying its own byte offset. Only the last one sets the push bit, so
  /// the receiver shows a whole frame rather than half of one.
  static List<Uint8List> framePackets(
    Uint8List rgb, {
    required int sequence,
    int destination = defaultDestination,
  }) {
    final packets = <Uint8List>[];
    const chunkBytes = maxPixelsPerPacket * 3;

    if (rgb.isEmpty) return packets;

    for (var offset = 0; offset < rgb.length; offset += chunkBytes) {
      final end = (offset + chunkBytes).clamp(0, rgb.length);
      final isLast = end >= rgb.length;
      final length = end - offset;

      final packet = Uint8List(headerLength + length);

      packet[0] = flagsVersion1 | (isLast ? flagsPush : 0);
      // Sequence runs 1-15; zero means "not sequenced", so it is skipped.
      packet[1] = (sequence % 15) + 1;
      packet[2] = dataTypeRgb24;
      packet[3] = destination;

      packet[4] = (offset >> 24) & 0xFF;
      packet[5] = (offset >> 16) & 0xFF;
      packet[6] = (offset >> 8) & 0xFF;
      packet[7] = offset & 0xFF;

      packet[8] = (length >> 8) & 0xFF;
      packet[9] = length & 0xFF;

      packet.setRange(headerLength, headerLength + length, rgb, offset);
      packets.add(packet);
    }

    return packets;
  }
}
