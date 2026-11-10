import 'package:flutter/material.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/widgets/error_retry_view.dart';
import 'package:travibe/core/widgets/travibe_loading_indicator.dart';
import 'package:travibe/features/onboarding/data/models/app_locale.dart';
import 'package:travibe/features/onboarding/data/onboarding_repo.dart';

class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key, this.repo, this.onChanged});
  final OnboardingRepo? repo;
  final VoidCallback? onChanged;

  Future<void> _open(BuildContext context) async {
    final preferences = PreferencesManager();
    final source = repo ?? OnboardingRepo.shared;
    var request = source.locales(preferences.getLanguage());
    var saving = false;
    final selected = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SizedBox(
            height: 280,
            child: FutureBuilder<LocaleCatalog>(
              future: request,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: TravibeLoadingIndicator());
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return ErrorRetryView(
                    message: preferences.getLanguage() == 'ar'
                        ? 'تعذر تحميل اللغات.'
                        : 'Unable to load languages.',
                    onRetry: () => update(
                      () => request = source.locales(preferences.getLanguage()),
                    ),
                  );
                }
                return ListView(
                  children: [
                    for (final locale in snapshot.data!.locales)
                      ListTile(
                        enabled: !saving && locale.supported,
                        title: Directionality(
                          textDirection: locale.rtl
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          child: Text(locale.name),
                        ),
                        trailing: preferences.getLanguage() == locale.code
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () async {
                          if (saving || !locale.supported) return;
                          update(() => saving = true);
                          try {
                            await preferences.saveLanguage(locale.code);
                            if (context.mounted) {
                              Navigator.of(context).pop(true);
                            }
                          } catch (_) {
                            if (context.mounted) {
                              update(() => saving = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Unable to save language. Please retry.',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    if (selected == true && context.mounted) onChanged?.call();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: PreferencesManager().getLanguage() == 'ar' ? 'اللغة' : 'Language',
    child: InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => _open(context),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF151515),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF303030)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            ValueListenableBuilder<String>(
              valueListenable: PreferencesManager().language,
              builder: (_, code, _) => Text(
                code.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down,
              color: Colors.white,
              size: 20,
            ),
          ],
        ),
      ),
    ),
  );
}
