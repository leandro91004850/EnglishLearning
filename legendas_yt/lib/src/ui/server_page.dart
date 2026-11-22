import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../app/services.dart';

/// Onde está a API do Legendas YT (o servidor em Python) e a chave de acesso. Testar fala com a
/// API sem gravar nada; Salvar grava neste aparelho e passa a usar essa API na hora.
class ServerPage extends StatefulWidget {
  const ServerPage({super.key, required this.services});

  final AppServices services;

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  late final TextEditingController _url = TextEditingController(text: widget.services.settings.url);
  final TextEditingController _token = TextEditingController();
  late bool _hasToken = widget.services.settings.token.isNotEmpty;
  bool _hideToken = true;
  bool _busy = false;

  /// Situação da API agora (no ar e como está o banco dela, ou o problema).
  String _status = '';
  bool? _statusOk;

  /// Resposta do último Testar / Salvar.
  String _message = '';
  bool _messageOk = false;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    final settings = widget.services.settings;
    if (!settings.configured) {
      setState(() {
        _status = ApiClient.notConfigured;
        _statusOk = null;
      });
      return;
    }
    setState(() {
      _status = 'Conectando a ${settings.url}…';
      _statusOk = null;
    });
    final (ok, message) = await widget.services.testServer(settings.url, '');
    if (!mounted) return;
    setState(() {
      _status = message;
      _statusOk = ok;
    });
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _message = 'Testando…';
      _messageOk = true;
    });
    final (ok, message) = await widget.services.testServer(_url.text, _token.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
      _messageOk = ok;
    });
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _message = 'Gravando…';
      _messageOk = true;
    });
    final (saved, ok, message) = await widget.services.saveServer(_url.text, _token.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
      _messageOk = ok;
      if (saved) {
        _url.text = widget.services.settings.url;
        _hasToken = widget.services.settings.token.isNotEmpty;
        _token.clear();
      }
    });
    if (saved) await _refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    InputDecoration field(String label, {String? hint, Widget? suffix}) => InputDecoration(
          labelText: label,
          hintText: hint,
          suffixIcon: suffix,
          border: const OutlineInputBorder(),
          isDense: true,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Servidor')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Banner(
              text: _status,
              ok: _statusOk,
              onRefresh: widget.services.settings.configured && !_busy ? _refreshStatus : null,
            ),
            const SizedBox(height: 20),
            Text('API do Legendas YT', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              decoration: field('Endereço', hint: 'http://192.168.0.10:8000'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _token,
              obscureText: _hideToken,
              autocorrect: false,
              enableSuggestions: false,
              decoration: field(
                'Chave de acesso',
                hint: _hasToken ? 'Em branco: mantém a chave salva' : 'O API_TOKEN do .env da API (se tiver)',
                suffix: IconButton(
                  tooltip: _hideToken ? 'Mostrar a chave' : 'Esconder a chave',
                  onPressed: () => setState(() => _hideToken = !_hideToken),
                  icon: Icon(_hideToken ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ),
            ),
            if (_message.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                _message,
                style: theme.textTheme.bodyMedium?.copyWith(color: _messageOk ? scheme.primary : scheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_busy) ...[
                  const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 16),
                ],
                OutlinedButton(onPressed: _busy ? null : _test, child: const Text('Testar')),
                const SizedBox(width: 10),
                FilledButton(onPressed: _busy ? null : _save, child: const Text('Salvar')),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'A API (o servidor em Python, projeto api_english) busca as legendas do YouTube, traduz e '
              'guarda tudo no banco de dados: a lista de vídeos com onde cada um parou, as preferências, '
              'as legendas com a tradução de cada fala e as palavras de cada fala. O app só mostra o que '
              'vem dela.',
              style: small,
            ),
            const SizedBox(height: 8),
            Text(
              'No celular, use o endereço (IP) do computador onde a API roda, não "localhost". O endereço '
              'e a chave ficam na pasta privada do app, neste aparelho.',
              style: small,
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.ok, required this.onRefresh});

  final String text;

  /// true: a API respondeu; false: problema; null: não configurada ou conectando.
  final bool? ok;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = switch (ok) {
      true => scheme.primary,
      false => scheme.error,
      null => scheme.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              switch (ok) {
                true => Icons.check_circle_outline,
                false => Icons.error_outline,
                null => Icons.dns_outlined,
              },
              size: 20,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          IconButton(
            tooltip: 'Verificar de novo',
            visualDensity: VisualDensity.compact,
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
    );
  }
}
