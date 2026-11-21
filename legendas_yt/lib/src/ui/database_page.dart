import 'package:material_ui/material_ui.dart';

import '../app/services.dart';

/// Dados de acesso ao PostgreSQL (o painel do botão do banco de dados do app.py).
/// Testar conecta sem gravar nada; Salvar grava no .env do app e passa a usar
/// esse banco na hora.
class DatabasePage extends StatefulWidget {
  const DatabasePage({super.key, required this.services});

  final AppServices services;

  @override
  State<DatabasePage> createState() => _DatabasePageState();
}

class _DatabasePageState extends State<DatabasePage> {
  late final Map<String, Object> _initial = widget.services.dbConfig();
  late final TextEditingController _host = TextEditingController(text: _initial['host']! as String);
  late final TextEditingController _port = TextEditingController(text: _initial['port']! as String);
  late final TextEditingController _dbname = TextEditingController(text: _initial['dbname']! as String);
  late final TextEditingController _user = TextEditingController(text: _initial['user']! as String);
  final TextEditingController _password = TextEditingController();
  late String _sslmode = _initial['sslmode']! as String;
  late bool _hasPassword = _initial['hasPassword']! as bool;
  bool _hidePassword = true;
  bool _busy = false;

  /// Situação do banco agora (conectado e o que tem guardado, ou o problema).
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
    for (final c in [_host, _port, _dbname, _user, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    final banco = widget.services.banco;
    if (!banco.configured) {
      setState(() {
        _status = 'Não configurado: o app guarda os recentes, as preferências e as legendas só neste aparelho.';
        _statusOk = null;
      });
      return;
    }
    setState(() {
      _status = 'Conectando a ${banco.describe()}…';
      _statusOk = null;
    });
    final (ok, message) = await banco.check();
    if (!mounted) return;
    setState(() {
      _status = ok ? 'Conectado: $message.' : message;
      _statusOk = ok;
    });
  }

  Map<String, Object?> get _form => {
        'host': _host.text,
        'port': _port.text,
        'dbname': _dbname.text,
        'user': _user.text,
        'password': _password.text,
        'sslmode': _sslmode,
      };

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _message = 'Testando…';
      _messageOk = true;
    });
    final (ok, message) = await widget.services.testDb(_form);
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
    final (saved, ok, message) = await widget.services.saveDb(_form);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
      _messageOk = ok;
      if (saved) {
        _hasPassword = widget.services.banco.config['DB_PASSWORD']?.isNotEmpty ?? false;
        _password.clear();
      }
    });
    if (saved) await _refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final modes = {
      '': 'Padrão',
      'require': 'Exigir',
      'disable': 'Desligada',
      if (!const ['', 'require', 'disable'].contains(_sslmode)) _sslmode: _sslmode, // escrito à mão no .env
    };

    InputDecoration field(String label, {String? hint, Widget? suffix}) => InputDecoration(
          labelText: label,
          hintText: hint,
          suffixIcon: suffix,
          border: const OutlineInputBorder(),
          isDense: true,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Banco de dados')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Banner(
              text: _status,
              ok: _statusOk,
              onRefresh: widget.services.banco.configured && !_busy ? _refreshStatus : null,
            ),
            const SizedBox(height: 20),
            Text('PostgreSQL', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _host,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.url,
                    decoration: field('Servidor', hint: 'localhost'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    decoration: field('Porta', hint: '5432'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dbname,
              autocorrect: false,
              enableSuggestions: false,
              decoration: field('Banco', hint: 'legendas_yt'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              autocorrect: false,
              enableSuggestions: false,
              decoration: field('Usuário', hint: 'postgres'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _hidePassword,
              autocorrect: false,
              enableSuggestions: false,
              decoration: field(
                'Senha',
                hint: _hasPassword ? 'Em branco: mantém a senha salva' : null,
                suffix: IconButton(
                  tooltip: _hidePassword ? 'Mostrar a senha' : 'Esconder a senha',
                  onPressed: () => setState(() => _hidePassword = !_hidePassword),
                  icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Conexão segura (SSL)', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final MapEntry(key: value, value: label) in modes.entries)
                    ButtonSegment(value: value, label: Text(label)),
                ],
                selected: {_sslmode},
                onSelectionChanged: (s) => setState(() => _sslmode = s.first),
              ),
            ),
            const SizedBox(height: 6),
            Text('"Exigir" para servidor na nuvem; "Padrão" tenta com SSL e, se o servidor não tiver, sem.',
                style: small),
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
              'Guarda os recentes (com onde cada vídeo parou), as preferências, as legendas com a '
              'tradução de cada fala e as palavras de cada fala — o mesmo banco do Legendas YT do '
              'computador (legendas-yt), se os dois usarem os mesmos dados de acesso. Sem banco, ou com '
              'ele fora do ar, o app continua funcionando e guarda tudo neste aparelho.',
              style: small,
            ),
            const SizedBox(height: 8),
            Text(
              'Os dados de acesso ficam num arquivo .env na pasta privada do app, neste aparelho. '
              'No celular, use o endereço (IP) do computador onde está o PostgreSQL, não "localhost"; '
              'o servidor precisa aceitar conexões da rede (listen_addresses e pg_hba.conf).',
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

  /// true: conectado; false: problema; null: não configurado ou conectando.
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
                null => Icons.storage_outlined,
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
