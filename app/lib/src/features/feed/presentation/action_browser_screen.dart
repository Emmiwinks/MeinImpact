import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../app/theme/mi_theme.dart';
import '../domain/opportunity.dart';
import 'widgets/done_bar.dart';

/// The action site inside the app (Android/iOS only: every action site
/// refuses to be framed, so the web build opens a new tab instead). Pops
/// with true when the user taps "Fertig", false or null otherwise.
class ActionBrowserScreen extends StatefulWidget {
  const ActionBrowserScreen({required this.opportunity, super.key});

  final Opportunity opportunity;

  /// Opens [opportunity]'s source; true when the user marked it done.
  static Future<bool> open(
    BuildContext context,
    Opportunity opportunity,
  ) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ActionBrowserScreen(opportunity: opportunity),
      ),
    );
    return done ?? false;
  }

  @override
  State<ActionBrowserScreen> createState() => _ActionBrowserScreenState();
}

class _ActionBrowserScreenState extends State<ActionBrowserScreen> {
  late final WebViewController _controller;
  late Uri _current;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _current = Uri.parse(widget.opportunity.sourceUrl);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onUrlChange: (change) {
            final uri = Uri.tryParse(change.url ?? '');
            if (uri != null && mounted) setState(() => _current = uri);
          },
          onNavigationRequest: _onNavigationRequest,
        ),
      )
      ..loadRequest(_current);
  }

  // The WebView only shows web pages. Mail, phone and app links, and files
  // the WebView cannot display, go to the system.
  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    final isWeb = uri.scheme == 'http' || uri.scheme == 'https';
    if (isWeb && !uri.path.toLowerCase().endsWith('.pdf')) {
      return NavigationDecision.navigate;
    }
    launchUrl(uri, mode: LaunchMode.externalApplication);
    return NavigationDecision.prevent;
  }

  Future<void> _onBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    } else if (mounted) {
      Navigator.of(context).pop(false);
    }
  }

  Future<void> _onMenu(_MenuItem item) async {
    switch (item) {
      case _MenuItem.openExternally:
        await launchUrl(_current, mode: LaunchMode.externalApplication);
      case _MenuItem.reload:
        await _controller.reload();
      case _MenuItem.copyLink:
        await Clipboard.setData(ClipboardData(text: _current.toString()));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link kopiert')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final canComplete = widget.opportunity.kind.completesInBrowser;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: colors.table,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Schließen',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          titleSpacing: 0,
          // The site's address, not a heading: the text face.
          title: Row(
            children: [
              if (_current.scheme == 'https') ...[
                Icon(Icons.lock_outline, size: 16, color: colors.onTableMuted),
                const SizedBox(width: MiSpace.sm - 2),
              ],
              Flexible(
                child: Text(
                  _current.host,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          actions: [
            PopupMenuButton<_MenuItem>(
              onSelected: _onMenu,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _MenuItem.openExternally,
                  child: Text('Im Browser öffnen'),
                ),
                PopupMenuItem(
                  value: _MenuItem.reload,
                  child: Text('Neu laden'),
                ),
                PopupMenuItem(
                  value: _MenuItem.copyLink,
                  child: Text('Link kopieren'),
                ),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: _progress < 100
                ? LinearProgressIndicator(
                    value: _progress / 100,
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                  )
                : Divider(height: 2, thickness: 1, color: colors.keyline),
          ),
        ),
        body: WebViewWidget(controller: _controller),
        bottomNavigationBar: canComplete
            ? DoneBar(
                hint: 'Mitgemacht? Dann tippe auf Fertig.',
                onDone: () => Navigator.of(context).pop(true),
              )
            : null,
      ),
    );
  }
}

enum _MenuItem { openExternally, reload, copyLink }
