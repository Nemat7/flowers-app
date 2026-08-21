import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/api_error.dart';
import '../auth_controller.dart';

/// Экран ввода 6-значного кода из SMS.
/// В dev-сборке бэкенд присылает dev_code — показываем его подсказкой.
class CodeScreen extends StatefulWidget {
  const CodeScreen({required this.phone, this.devCode, super.key});

  final String phone;
  final String? devCode;

  @override
  State<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends State<CodeScreen> {
  static const _codeLength = 6;
  static const _resendSeconds = 60;

  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;
  int _resendIn = _resendSeconds;
  Timer? _timer;
  String? _devCode;

  @override
  void initState() {
    super.initState();
    _devCode = widget.devCode;
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _resendIn = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendIn <= 1) {
        timer.cancel();
        setState(() => _resendIn = 0);
      } else {
        setState(() => _resendIn--);
      }
    });
  }

  bool get _isValid => _controller.text.length == _codeLength;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context
          .read<AuthController>()
          .verifyOtp(phone: widget.phone, code: _controller.text);
      // AuthGate под нами уже переключился на главную — снимаем экраны
      // логина со стека, иначе код-экран остаётся «поверх» главной.
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _error = null);
    try {
      final devCode =
          await context.read<AuthController>().requestOtp(widget.phone);
      _devCode = devCode ?? _devCode;
      _startTimer();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text(
                'Код из SMS',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Отправили на ${widget.phone}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_devCode != null) ...[
                const SizedBox(height: 8),
                Text(
                  'dev-код: $_devCode',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
              const SizedBox(height: 32),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(_codeLength),
                ],
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 8,
                ),
                decoration: const InputDecoration(hintText: '••••••'),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) {
                  if (_isValid && !_loading) _submit();
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isValid && !_loading ? _submit : null,
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Войти'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _resendIn == 0 ? _resend : null,
                child: Text(
                  _resendIn == 0
                      ? 'Отправить код ещё раз'
                      : 'Повторить через $_resendIn сек',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
