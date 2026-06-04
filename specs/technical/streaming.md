# Streaming

## Purpose
Defines the SSE implementation for letter and question draft generation:
server configuration, client handling, error recovery, and UI behaviour.

---

## Decisions

- **HTTP SSE, not WebSocket.** One-way token stream from server to client
  is sufficient. SSE is simpler, stateless, and natively supported.

- **Stream is not resumable.** If the connection drops mid-stream, the
  client starts a new request. Partial drafts are discarded.
  Resumability would require server-side token buffering which adds
  complexity without meaningful benefit (generation is fast, ~5s).

- **Backend never buffers the full response.** Tokens are forwarded
  from Mistral to the client as they arrive. No server-side assembly.

- **`[DONE]` and `[ERROR]` are sentinel tokens.** The client
  terminates the stream on either. `[ERROR]` triggers the fallback state.

---

## Server Implementation (FastAPI)

```python
from fastapi import FastAPI
from fastapi.responses import StreamingResponse
from anthropic import AsyncMistral  # Mistral async client

@app.post("/api/v1/letters/stream")
async def stream_letter(
    request: LetterRequest,
    token: str = Depends(validate_token),
):
    # Rate limit + budget checks (see rate-limiting.md)
    await check_limits(token, 'letter')

    action = await db.fetch_action(request.action_id)
    prompt = build_prompt(request, action)

    async def generate():
        try:
            stream = await mistral_client.chat.stream_async(
                model="mistral-medium-latest",
                messages=[{"role": "user", "content": prompt}],
                max_tokens=300,
            )
            async for chunk in stream:
                delta = chunk.data.choices[0].delta.content
                if delta:
                    # Escape newlines for SSE format
                    escaped = delta.replace('\n', '\\n')
                    yield f"data: {escaped}\n\n"
            yield "data: [DONE]\n\n"

        except Exception as e:
            sentry.capture_exception(e)
            yield "data: [ERROR]\n\n"

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",  // Disable nginx buffering
        },
    )
```

**`X-Accel-Buffering: no`** is critical on Fly.io (nginx proxy) to
prevent token batching. Without it, tokens arrive in large chunks
instead of one by one.

---

## Client Implementation (Flutter)

```dart
class StreamingService {
  StreamController<StreamEvent>? _controller;

  Stream<StreamEvent> streamLetter(LetterRequest request) {
    _controller = StreamController<StreamEvent>();
    _startStream(request);
    return _controller!.stream;
  }

  Future<void> _startStream(LetterRequest request) async {
    final client = http.Client();

    try {
      final req = http.Request(
        'POST',
        Uri.parse('${ApiConfig.base}/letters/stream'),
      )
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        })
        ..body = jsonEncode(request.toJson());

      final response = await client.send(req);

      // Handle HTTP error codes before streaming
      if (response.statusCode == 429) {
        _controller!.addError(RateLimitException());
        return;
      }
      if (response.statusCode == 503) {
        _controller!.addError(AIUnavailableException());
        return;
      }
      if (response.statusCode != 200) {
        _controller!.addError(ApiException(response.statusCode));
        return;
      }

      // Process SSE stream
      final buffer = StringBuffer();

      await response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
        if (!line.startsWith('data: ')) return;

        final token = line.substring(6);

        if (token == '[DONE]') {
          _controller!.add(StreamEvent.done());
          return;
        }
        if (token == '[ERROR]') {
          _controller!.addError(AIUnavailableException());
          return;
        }

        // Unescape newlines
        final unescaped = token.replaceAll('\\n', '\n');
        buffer.write(unescaped);
        _controller!.add(StreamEvent.token(unescaped));
      });

    } catch (e) {
      _controller!.addError(e);
    } finally {
      client.close();
      await _controller!.close();
    }
  }

  void cancel() {
    _controller?.close();
  }
}

// Event types
sealed class StreamEvent {
  const StreamEvent();
  factory StreamEvent.token(String text) = TokenEvent;
  factory StreamEvent.done() = DoneEvent;
}
class TokenEvent extends StreamEvent {
  final String text;
  const TokenEvent(this.text);
}
class DoneEvent extends StreamEvent {
  const DoneEvent();
}
```

---

## UI: Typewriter Effect

```dart
class LetterDraftWidget extends StatefulWidget { ... }

class _LetterDraftWidgetState extends State<LetterDraftWidget> {
  final _buffer = StringBuffer();
  bool _isStreaming = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _startStreaming();
  }

  void _startStreaming() {
    widget.streamingService
        .streamLetter(widget.request)
        .listen(
      (event) {
        if (event is TokenEvent) {
          setState(() => _buffer.write(event.text));
        } else if (event is DoneEvent) {
          setState(() => _isStreaming = false);
          // Replace placeholders with chip widgets
          widget.onDraftComplete(_buffer.toString());
        }
      },
      onError: (error) {
        setState(() {
          _isStreaming = false;
          _hasError = true;
        });
        widget.onError(error);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      AnimatedTextWidget(
        text: _buffer.toString(),
        isStreaming: _isStreaming,
      ),
      if (_isStreaming) const StreamingIndicator(),
      if (_hasError) const FallbackDraftPrompt(),
    ]);
  }
}
```

**Streaming indicator:** A subtle blinking cursor appended to the
text while streaming. Disappears when `[DONE]` is received.

**Reduced motion:** If `settings.reduced_motion = true`, the text
appears all at once when streaming completes instead of token-by-token.

---

## Timeout Handling

If no token is received for 10 seconds:

```dart
.timeout(
  const Duration(seconds: 10),
  onTimeout: (sink) {
    sink.addError(TimeoutException('Generation timed out'));
  },
)
```

The timeout resets with each received token, so it only triggers on
true stalls, not normal generation pauses.

---

## Connection Loss Mid-Stream

If the device loses connectivity during streaming:
1. Stream closes with a network error
2. `_hasError = true` → fallback state shown
3. "Nochmal versuchen" button triggers a fresh request
4. Partial draft in buffer is discarded

No attempt to resume from where the stream stopped.

---

## Fly.io Proxy Configuration

Fly.io uses an internal nginx proxy that must be configured to not
buffer SSE responses:

```nginx
# fly.toml or nginx config
proxy_buffering off;
proxy_cache off;
```

This is handled via the `X-Accel-Buffering: no` response header
set by FastAPI. No additional Fly.io configuration needed.

---

## Dependencies

- Reads: `features/letter-generation.md`, `technical/api-endpoints.md`
- Referenced by: `features/action-types.md`

---

## Open Questions

- None.
