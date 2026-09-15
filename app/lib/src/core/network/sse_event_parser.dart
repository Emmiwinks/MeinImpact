class SseEvent {
  const SseEvent({
    required this.event,
    required this.data,
    this.id,
    this.retryMilliseconds,
  });

  final String event;
  final String data;
  final String? id;
  final int? retryMilliseconds;
}

class SseEventParser {
  String _buffer = '';

  List<SseEvent> addChunk(String chunk) {
    _buffer += chunk;
    final events = <SseEvent>[];
    var boundary = _buffer.indexOf('\n\n');
    while (boundary != -1) {
      final rawEvent = _buffer.substring(0, boundary);
      _buffer = _buffer.substring(boundary + 2);
      final event = parseMessage(rawEvent);
      if (event != null) {
        events.add(event);
      }
      boundary = _buffer.indexOf('\n\n');
    }
    return events;
  }

  List<SseEvent> close() {
    if (_buffer.trim().isEmpty) {
      _buffer = '';
      return const [];
    }
    final event = parseMessage(_buffer);
    _buffer = '';
    return event == null ? const [] : [event];
  }

  static SseEvent? parseMessage(String message) {
    String? id;
    var eventName = 'message';
    int? retryMilliseconds;
    final dataLines = <String>[];

    for (final line in message.split('\n')) {
      if (line.isEmpty || line.startsWith(':')) {
        continue;
      }
      final separator = line.indexOf(':');
      final field = separator == -1 ? line : line.substring(0, separator);
      // Per the SSE spec, at most one leading space after the colon is a
      // field-value delimiter and gets stripped — NOT all leading
      // whitespace. A streamed token whose content legitimately starts
      // with a space (e.g. a fresh word after punctuation) would otherwise
      // lose that space here, running words together in the rendered text.
      var value = separator == -1 ? '' : line.substring(separator + 1);
      if (value.startsWith(' ')) {
        value = value.substring(1);
      }
      switch (field) {
        case 'id':
          id = value;
          break;
        case 'event':
          eventName = value;
          break;
        case 'retry':
          retryMilliseconds = int.tryParse(value);
          break;
        case 'data':
          dataLines.add(value);
          break;
      }
    }

    if (dataLines.isEmpty) {
      return null;
    }
    return SseEvent(
      id: id,
      event: eventName,
      data: dataLines.join('\n'),
      retryMilliseconds: retryMilliseconds,
    );
  }
}
