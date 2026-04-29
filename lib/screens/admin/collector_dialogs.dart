part of 'collectors_screen.dart';


class _Dialog extends StatelessWidget {
  final String title;
  final List<Widget> fields;
  final Future<bool> Function() onConfirm;

  const _Dialog({required this.title, required this.fields, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surfaceColor(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 18),
            ...fields,
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('cancel'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context))),
                ),
                const SizedBox(width: 8),
                AsyncButton(
                  onPressed: () async {
                    final shouldClose = await onConfirm();
                    if (shouldClose && context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.isDark(context) ? AppTheme.accent : const Color(0xFF8C6239),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('save'.tr(), style: const TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
