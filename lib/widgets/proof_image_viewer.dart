import 'package:flutter/material.dart';

/// Opens a full-screen, zoomable view of a network image (assignment proof / USSD screenshot).
void showProofImageFullscreen(BuildContext context, String imageUrl) {
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'proof',
    barrierColor: Colors.black.withValues(alpha: 0.92),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, __) {
      return SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Padding(
                        padding: EdgeInsets.all(48),
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    },
                    errorBuilder: (_, __, ___) => const Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image_outlined, color: Colors.white54, size: 56),
                          SizedBox(height: 12),
                          Text(
                            'Could not load image',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white24,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Thumbnail that opens [showProofImageFullscreen] on tap.
class ProofImageThumbnail extends StatelessWidget {
  final String imageUrl;
  final double height;
  final double? width;
  final BoxFit fit;

  const ProofImageThumbnail({
    super.key,
    required this.imageUrl,
    this.height = 120,
    this.width,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showProofImageFullscreen(context, imageUrl),
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: height,
          width: width ?? double.infinity,
          child: Stack(
            alignment: Alignment.bottomRight,
            fit: StackFit.expand,
            children: [
              Image.network(
                imageUrl,
                fit: fit,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey.withValues(alpha: 0.2),
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.zoom_in, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
