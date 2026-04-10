import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_panel_screen.dart';
import '../services/app_session.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.onRequestHomeTab});

  final VoidCallback onRequestHomeTab;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login(AppSessionController session) async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen kullanıcı adı ve şifre girin.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await session.signInWithUsername(username: username, password: password);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Giriş başarısız: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final session = AppSession.of(context);

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        final user = authSnapshot.data;

        return ValueListenableBuilder<AppSessionState>(
          valueListenable: session,
          builder: (context, state, _) {
            final isAdminPanelVisible =
                user != null && !state.isLoading && state.isAdmin;

            if (user != null && !state.isLoading && !state.isAdmin) {
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                await session.signOut();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Bu hesap admin yetkisine sahip değil.'),
                  ),
                );
              });
            }

            return PopScope(
              canPop: !isAdminPanelVisible,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
                if (isAdminPanelVisible) {
                  widget.onRequestHomeTab();
                }
              },
              child: Scaffold(
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                appBar: AppBar(title: const Text('Profil')),
                body: isAdminPanelVisible
                    ? AdminPanelWidget(
                        onLogout: () => FirebaseAuth.instance.signOut(),
                      )
                    : Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                            children: [
                              Card(
                                margin: EdgeInsets.zero,
                                child: Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 44,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              color: cs.primary.withValues(
                                                alpha: 0.10,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: cs.outlineVariant
                                                    .withValues(alpha: 0.4),
                                              ),
                                            ),
                                            child: Icon(
                                              Icons
                                                  .admin_panel_settings_outlined,
                                              color: cs.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              'Yönetici Girişi',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge
                                                  ?.copyWith(
                                                    fontWeight:
                                                        FontWeight.w900,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      TextField(
                                        controller: _usernameController,
                                        textInputAction: TextInputAction.next,
                                        decoration: const InputDecoration(
                                          labelText: 'Kullanıcı Adı',
                                          prefixIcon:
                                              Icon(Icons.person_outline),
                                        ),
                                        enabled: !_isLoading,
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: _passwordController,
                                        obscureText: true,
                                        onSubmitted: _isLoading
                                            ? null
                                            : (_) => _login(session),
                                        decoration: const InputDecoration(
                                          labelText: 'Şifre',
                                          prefixIcon: Icon(Icons.lock_outline),
                                        ),
                                        enabled: !_isLoading,
                                      ),
                                      const SizedBox(height: 16),
                                      SizedBox(
                                        height: 50,
                                        child: _isLoading
                                            ? const Center(
                                                child: SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                ),
                                              )
                                            : FilledButton(
                                                onPressed: () =>
                                                    _login(session),
                                                child: const Text(
                                                  'Giriş Yap',
                                                  style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                      ),
                                      if (state.isLoading && user != null) ...[
                                        const SizedBox(height: 12),
                                        Text(
                                          'Yetki kontrol ediliyor...',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: cs.onSurfaceVariant,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            );
          },
        );
      },
    );
  }
}
