import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/support_repository.dart';

/// Visible uniquement sur l'accueil. Aucune superposition au lecteur,
/// aucun son et aucune ouverture automatique ; le client garde la main.
class SupportBubble extends StatefulWidget {
  const SupportBubble({super.key, this.repository});
  final SupportRepository? repository;
  @override
  State<SupportBubble> createState() => _SupportBubbleState();
}

class _SupportBubbleState extends State<SupportBubble>
    with WidgetsBindingObserver {
  Timer? _timer;
  int _unread = 0;
  bool _busy = false;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!mounted ||
        !_foreground ||
        _busy ||
        ModalRoute.of(context)?.isCurrent != true)
      return;
    _busy = true;
    try {
      final int unread = await (widget.repository ?? SupportRepository.instance)
          .unread();
      if (mounted) setState(() => _unread = unread);
    } catch (_) {
      /* Le chat ne peut jamais bloquer l'accueil. */
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Chat privé · Assistance',
    child: Badge(
      isLabelVisible: _unread > 0,
      label: Text(_unread > 99 ? '99+' : '$_unread'),
      child: FloatingActionButton.small(
        heroTag: 'support-chat',
        backgroundColor: AppColors.surfaceHigh,
        foregroundColor: AppColors.editorialCream,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppColors.accent.withValues(alpha: .45)),
        ),
        onPressed: () async {
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: AppColors.background,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            builder: (BuildContext context) => Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SizedBox(
                height:
                    (MediaQuery.sizeOf(context).height -
                        MediaQuery.viewInsetsOf(context).bottom) *
                    .78,
                child: SupportChat(repository: widget.repository),
              ),
            ),
          );
          unawaited(_refresh());
        },
        child: Semantics(
          label: 'Ouvrir le chat privé',
          child: const _LittleFace(),
        ),
      ),
    ),
  );
}

class _LittleFace extends StatelessWidget {
  const _LittleFace();
  @override
  Widget build(BuildContext context) => Container(
    width: 27,
    height: 20,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: AppColors.editorialCream.withValues(alpha: .65),
      ),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int i = 0; i < 2; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Container(
              width: 4,
              height: 7,
              decoration: BoxDecoration(
                color: AppColors.editorialCream,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ],
    ),
  );
}

class SupportChat extends StatefulWidget {
  const SupportChat({super.key, this.repository});
  final SupportRepository? repository;
  @override
  State<SupportChat> createState() => _SupportChatState();
}

class _SupportChatState extends State<SupportChat> with WidgetsBindingObserver {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  SupportRepository get _repo =>
      widget.repository ?? SupportRepository.instance;
  Timer? _timer;
  List<SupportMessage> _items = <SupportMessage>[];
  bool _loading = false,
      _sending = false,
      _initial = true,
      _foreground = true,
      _more = false;
  int _ownerRead = 0, _ack = 0;
  String _error = '', _pendingText = '', _pendingId = '';
  bool get _bottom => !_scroll.hasClients || _scroll.offset < 40;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_bottom) unawaited(_markRead());
  }

  Future<void> _markRead() async {
    if (!mounted || !_foreground || !_bottom || _items.isEmpty) return;
    final int seq = _items.last.seq;
    if (seq <= _ack) return;
    try {
      await _repo.read(seq);
      _ack = seq;
    } catch (_) {
      /* Retenté au prochain passage. */
    }
  }

  Future<void> _load({bool older = false}) async {
    if (_loading || !_foreground || !mounted) return;
    _loading = true;
    try {
      final bool firstPage = _items.isEmpty;
      final SupportPage page = await _repo.messages(
        before: older && _items.isNotEmpty ? _items.first.seq : null,
        after: !older && _items.isNotEmpty ? _items.last.seq : null,
      );
      if (!mounted) return;
      final Map<int, SupportMessage> byId = <int, SupportMessage>{
        for (final SupportMessage m in _items) m.seq: m,
        for (final SupportMessage m in page.items) m.seq: m,
      };
      setState(() {
        _items = byId.values.toList()
          ..sort(
            (SupportMessage a, SupportMessage b) => a.seq.compareTo(b.seq),
          );
        _ownerRead = page.ownerRead;
        if (firstPage || older) _more = page.more;
        _initial = false;
        _error = '';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!older) unawaited(_markRead());
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _initial = false;
          _error = e.toString().replaceFirst('Bad state: ', '');
        });
    } finally {
      _loading = false;
    }
  }

  Future<void> _send() async {
    final String text = _text.text.trim();
    if (_sending || text.isEmpty) return;
    if (_pendingText != text) {
      _pendingText = text;
      _pendingId = SupportRepository.newMessageId();
    }
    setState(() {
      _sending = true;
      _error = '';
    });
    try {
      await _repo.send(text, _pendingId);
      if (!mounted) return;
      _text.clear();
      _pendingId = '';
      _pendingText = '';
      await _load();
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Container(
        margin: const EdgeInsets.only(top: 10),
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.textTertiary,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
        child: Row(
          children: <Widget>[
            const _LittleFace(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('7MOTION · Assistance', style: AppTextStyles.bodyLarge),
                  Text(
                    'Une conversation privée avec 7MOTION',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
      Divider(height: 1, color: AppColors.border),
      Expanded(
        child: _initial
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
            ? SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const _LittleFace(),
                      const SizedBox(height: 16),
                      Text(
                        'Comment pouvons-nous t’aider ?',
                        style: AppTextStyles.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Écris-nous ici. Tu retrouveras notre réponse dans cette conversation.',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                controller: _scroll,
                reverse: true,
                padding: const EdgeInsets.all(16),
                itemCount: _items.length + (_more ? 1 : 0),
                itemBuilder: (BuildContext context, int index) {
                  if (index == _items.length)
                    return TextButton(
                      onPressed: () => _load(older: true),
                      child: const Text('Messages précédents'),
                    );
                  final SupportMessage m = _items[_items.length - 1 - index];
                  final bool mine = m.sender == 'client';
                  final DateTime date = DateTime.fromMillisecondsSinceEpoch(
                    m.createdAt,
                  );
                  final String time = TimeOfDay.fromDateTime(date)
                      .format(context);
                  return Align(
                    alignment: mine
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * .8,
                      ),
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: mine
                            ? AppColors.accent.withValues(alpha: .15)
                            : AppColors.surfaceHigh,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(mine ? 18 : 4),
                          bottomRight: Radius.circular(mine ? 4 : 18),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          SelectableText(
                            m.body,
                            style: AppTextStyles.bodyMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$time${mine ? (_ownerRead >= m.seq ? ' · Lu' : ' · Envoyé') : ''}',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      if (_error.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text(
            _error,
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.warning),
          ),
        ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _text,
                  enabled: !_sending,
                  maxLength: 2000,
                  minLines: 1,
                  maxLines: 4,
                  style: AppTextStyles.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Ton message…',
                    counterText: '',
                    filled: true,
                    fillColor: AppColors.surfaceHigh,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Envoyer',
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_upward_rounded),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
