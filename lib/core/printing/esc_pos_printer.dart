import 'dart:io';
import 'dart:typed_data';
import 'package:systock/core/printing/esc_pos_encoder.dart';
import 'package:systock/core/printing/receipt.dart';

abstract interface class PrinterByteTransport {
  Future<void> send(Uint8List bytes);
}

class EscPosReceiptPrinter implements ReceiptPrinter {
  const EscPosReceiptPrinter(
    this.transport, {
    this.encoder = const EscPosEncoder(),
  });
  final PrinterByteTransport transport;
  final EscPosEncoder encoder;
  @override
  Future<PrintResult> print(Receipt receipt) async {
    try {
      await transport.send(encoder.encode(receipt));
      return const PrintSuccess();
    } catch (error) {
      return PrintFailure(
        'Não foi possível comunicar com a impressora.',
        error,
      );
    }
  }
}

class NetworkPrinterTransport implements PrinterByteTransport {
  const NetworkPrinterTransport(
    this.host, {
    this.port = 9100,
    this.timeout = const Duration(seconds: 5),
  });
  final String host;
  final int port;
  final Duration timeout;
  @override
  Future<void> send(Uint8List bytes) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    try {
      socket.add(bytes);
      await socket.flush();
    } finally {
      await socket.close();
    }
  }
}

abstract interface class PlatformPrinterChannel {
  Future<void> write(Uint8List bytes);
}

class BluetoothPrinterTransport implements PrinterByteTransport {
  const BluetoothPrinterTransport(this.channel);
  final PlatformPrinterChannel channel;
  @override
  Future<void> send(Uint8List bytes) => channel.write(bytes);
}

class UsbPrinterTransport implements PrinterByteTransport {
  const UsbPrinterTransport(this.channel);
  final PlatformPrinterChannel channel;
  @override
  Future<void> send(Uint8List bytes) => channel.write(bytes);
}
