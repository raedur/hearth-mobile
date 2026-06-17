import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';

const _prefBotNumber = 'hearth_bot_number';

class LoginScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;

  const LoginScreen({super.key, required this.onAuthenticated});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthService();
  final _botNumberController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBotNumber();
    _auth.listenForAuthDeepLink(
      onSuccess: (_, _) => widget.onAuthenticated(),
      onError: (err) => setState(() => _error = err),
    );
  }

  Future<void> _loadBotNumber() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefBotNumber);
    if (saved != null) _botNumberController.text = saved;
  }

  Future<void> _startLogin() async {
    final botNumber = _botNumberController.text.trim().replaceAll(RegExp(r'\s+'), '');
    if (botNumber.isEmpty) {
      setState(() => _error = 'Enter the Hearth bot number');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefBotNumber, botNumber);

    final nonce = await _auth.generateNonce();
    final whatsappUrl = 'https://wa.me/$botNumber?text=${Uri.encodeComponent('HEARTH-AUTH:$nonce')}';
    final uri = Uri.parse(whatsappUrl);

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      setState(() {
        _loading = false;
        _error = 'Could not open WhatsApp. Is it installed?';
      });
      return;
    }

    // Waiting for deep link — auth_service listener handles success
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.home_filled, size: 64, color: Colors.deepOrange),
              const SizedBox(height: 24),
              Text(
                'Hearth',
                style: Theme.of(context).textTheme.headlineLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Your family wiki',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              TextField(
                controller: _botNumberController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Hearth bot number',
                  hintText: '+61412345678',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              FilledButton.icon(
                onPressed: _loading ? null : _startLogin,
                icon: const Icon(Icons.message),
                label: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Connect with WhatsApp'),
              ),
              const SizedBox(height: 24),
              Text(
                'Hearth will send you a verification code via WhatsApp.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _botNumberController.dispose();
    super.dispose();
  }
}
