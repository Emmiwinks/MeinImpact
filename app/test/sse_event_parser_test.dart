import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/core/network/sse_event_parser.dart';

void main() {
  test('parses one SSE message', () {
    final event = SseEventParser.parseMessage(
      'id: 42\nevent: draft.delta\ndata: hello\ndata: world',
    );

    expect(event, isNotNull);
    expect(event!.id, '42');
    expect(event.event, 'draft.delta');
    expect(event.data, 'hello\nworld');
  });

  test('parses retry and default event messages', () {
    final event = SseEventParser.parseMessage('retry: 3000\ndata: ping');

    expect(event, isNotNull);
    expect(event!.event, 'message');
    expect(event.retryMilliseconds, 3000);
    expect(event.data, 'ping');
  });

  test('parses valueless fields as empty values', () {
    final event = SseEventParser.parseMessage('event\ndata');

    expect(event, isNotNull);
    expect(event!.event, '');
    expect(event.data, '');
  });

  test('buffers chunked messages', () {
    final parser = SseEventParser();
    expect(parser.addChunk('event: draft.delta\ndata: hel'), isEmpty);
    final events = parser.addChunk('lo\n\n');

    expect(events, hasLength(1));
    expect(events.single.event, 'draft.delta');
    expect(events.single.data, 'hello');
  });

  test('flushes a final buffered event on close', () {
    final parser = SseEventParser();
    expect(parser.addChunk('event: draft.delta\ndata: hello'), isEmpty);
    final events = parser.close();

    expect(events, hasLength(1));
    expect(events.single.event, 'draft.delta');
    expect(events.single.data, 'hello');
    expect(parser.close(), isEmpty);
  });

  test('parses multiple messages from one chunk', () {
    final parser = SseEventParser();
    final events = parser.addChunk('data: one\n\ndata: two\n\n');

    expect(events.map((event) => event.data), ['one', 'two']);
  });

  test('ignores comments and empty messages', () {
    expect(SseEventParser.parseMessage(': keep-alive'), isNull);
  });
}
