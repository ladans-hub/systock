class SyncEnvelope {
  const SyncEnvelope({
    required this.operationId,
    required this.deviceId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.version,
    required this.payloadJson,
    required this.checksum,
    required this.createdAt,
  });
  final String operationId,
      deviceId,
      entityType,
      entityId,
      operation,
      payloadJson,
      checksum;
  final int version;
  final DateTime createdAt;
}

abstract interface class SyncTransport {
  Future<void> upload(List<SyncEnvelope> operations);
  Future<List<SyncEnvelope>> download({
    required Set<String> excludingOperationIds,
  });
}

class InMemorySyncTransport implements SyncTransport {
  final Map<String, SyncEnvelope> _items = {};
  @override
  Future<void> upload(List<SyncEnvelope> operations) async {
    for (final operation in operations) {
      _items.putIfAbsent(operation.operationId, () => operation);
    }
  }

  @override
  Future<List<SyncEnvelope>> download({
    required Set<String> excludingOperationIds,
  }) async =>
      _items.values
          .where((o) => !excludingOperationIds.contains(o.operationId))
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
}
