import 'package:flutter/material.dart';

import '../screens/admin_panel_screen.dart';

class BackupAdminPanelScreenFromLogin extends StatelessWidget {
  const BackupAdminPanelScreenFromLogin({super.key, required this.onLogout});

  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        centerTitle: true,
      ),
      body: AdminPanelWidget(
        onLogout: () async {
          await onLogout();
          if (!context.mounted) return;
          Navigator.of(context).pop();
        },
      ),
    );
  }
}

class BackupAdminPanelScreenFromProfile extends StatelessWidget {
  const BackupAdminPanelScreenFromProfile({super.key, required this.onLogout});

  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        centerTitle: true,
      ),
      body: AdminPanelWidget(
        onLogout: () async {
          await onLogout();
          if (!context.mounted) return;
          Navigator.of(context).pop();
        },
      ),
    );
  }
}
