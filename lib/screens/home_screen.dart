import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../models/user_model.dart';
import '../utils/constants.dart';
import '../services/sync_service.dart';
import 'voice_interaction_screen.dart';
import 'all_memories_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final UserModel? user = authService.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authService.signOut();
              // AuthWrapper will automatically show LoginScreen when auth state changes
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSizes.paddingLarge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Profile Card
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.borderRadius),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSizes.paddingMedium),
                  child: Row(
                    children: [
                      // User Avatar
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: AppColors.primary.withOpacity(0.1),
                        child: user?.photoUrl != null
                            ? ClipOval(
                                child: Image.network(
                                  user!.photoUrl!,
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(
                                    Icons.person_outline,
                                    size: 30,
                                    color: AppColors.primary,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.person_outline,
                                size: 30,
                                color: AppColors.primary,
                              ),
                      ),
                      const SizedBox(width: AppSizes.paddingMedium),
                      // User Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.displayName ?? 'User',
                              style: AppTextStyles.subheading,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user?.email ?? '',
                              style: AppTextStyles.caption,
                            ),
                            if (user?.isEmailVerified == false) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    size: 16,
                                    color: AppColors.error,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Email not verified',
                                    style: AppTextStyles.caption.copyWith(
                                      color: AppColors.error,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSizes.paddingLarge),

              // Sync Status
              StreamBuilder<SyncStatus>(
                stream: authService.syncService.syncStatusStream,
                builder: (context, snapshot) {
                  final status = snapshot.data ?? SyncStatus.synced;
                  return Container(
                    padding: const EdgeInsets.all(AppSizes.paddingMedium),
                    decoration: BoxDecoration(
                      color: _getSyncStatusColor(status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(AppSizes.borderRadius),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _getSyncStatusIcon(status),
                          color: _getSyncStatusColor(status),
                        ),
                        const SizedBox(width: AppSizes.paddingMedium),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getSyncStatusTitle(status),
                                style: AppTextStyles.body.copyWith(
                                  color: _getSyncStatusColor(status),
                                ),
                              ),
                              if (status == SyncStatus.error)
                                Text(
                                  'Tap to retry',
                                  style: AppTextStyles.caption.copyWith(
                                    color: _getSyncStatusColor(status),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (status == SyncStatus.error ||
                            status == SyncStatus.pending)
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            color: _getSyncStatusColor(status),
                            onPressed: () {
                              authService.syncService.forceSyncNow();
                            },
                          ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSizes.paddingLarge),

              // Quick Actions Section
              Text(
                'Quick Actions',
                style: AppTextStyles.subheading,
              ),
              const SizedBox(height: AppSizes.paddingMedium),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.borderRadius),
                ),
                child: Column(
                  children: [
                    // Voice Interaction
                    ListTile(
                      leading: const Icon(Icons.mic_outlined),
                      title: const Text('Voice Interaction'),
                      subtitle: const Text('Add memories and search using voice'),
                      trailing: const Icon(Icons.arrow_forward_ios),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const VoiceInteractionScreen(),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    // All Memories
                    ListTile(
                      leading: const Icon(Icons.memory_outlined),
                      title: const Text('All Memories'),
                      subtitle: const Text('View and manage your stored memories'),
                      trailing: const Icon(Icons.arrow_forward_ios),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AllMemoriesScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.paddingLarge),

              // Preferences Section
              Text(
                'Preferences',
                style: AppTextStyles.subheading,
              ),
              const SizedBox(height: AppSizes.paddingMedium),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.borderRadius),
                ),
                child: Column(
                  children: [
                    // Theme Preference
                    ListTile(
                      leading: const Icon(Icons.palette_outlined),
                      title: const Text('Theme'),
                      trailing: DropdownButton<String>(
                        value: user?.preferences?['theme'] ?? 'light',
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(
                            value: 'light',
                            child: Text('Light'),
                          ),
                          DropdownMenuItem(
                            value: 'dark',
                            child: Text('Dark'),
                          ),
                          DropdownMenuItem(
                            value: 'system',
                            child: Text('System'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            authService.updateUserProfile(
                              preferences: {
                                ...?user?.preferences,
                                'theme': value,
                              },
                            );
                          }
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    // Notifications Preference
                    SwitchListTile(
                      secondary: const Icon(Icons.notifications_outlined),
                      title: const Text('Notifications'),
                      value: user?.preferences?['notifications'] ?? true,
                      onChanged: (value) {
                        authService.updateUserProfile(
                          preferences: {
                            ...?user?.preferences,
                            'notifications': value,
                          },
                        );
                      },
                    ),
                    const Divider(height: 1),
                    // Language Preference
                    ListTile(
                      leading: const Icon(Icons.language_outlined),
                      title: const Text('Language'),
                      trailing: DropdownButton<String>(
                        value: user?.preferences?['language'] ?? 'en',
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(
                            value: 'en',
                            child: Text('English'),
                          ),
                          DropdownMenuItem(
                            value: 'es',
                            child: Text('Español'),
                          ),
                          DropdownMenuItem(
                            value: 'fr',
                            child: Text('Français'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            authService.updateUserProfile(
                              preferences: {
                                ...?user?.preferences,
                                'language': value,
                              },
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getSyncStatusColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return Colors.green;
      case SyncStatus.syncing:
        return Colors.blue;
      case SyncStatus.pending:
        return Colors.orange;
      case SyncStatus.error:
        return Colors.red;
    }
  }

  IconData _getSyncStatusIcon(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return Icons.check_circle_outline;
      case SyncStatus.syncing:
        return Icons.sync;
      case SyncStatus.pending:
        return Icons.pending_outlined;
      case SyncStatus.error:
        return Icons.error_outline;
    }
  }

  String _getSyncStatusTitle(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return 'All data is synced';
      case SyncStatus.syncing:
        return 'Syncing data...';
      case SyncStatus.pending:
        return 'Waiting to sync';
      case SyncStatus.error:
        return 'Sync error';
    }
  }
} 