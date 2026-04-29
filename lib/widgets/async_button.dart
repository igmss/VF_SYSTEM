import 'package:flutter/material.dart';

/// A button that handles its own loading state when [onPressed] returns a [Future].
/// This prevents duplicate clicks and provides visual feedback during async operations.
class AsyncButton extends StatefulWidget {
  final Future<void> Function()? onPressed;
  final Widget child;
  final ButtonStyle? style;
  final Widget? loadingWidget;
  final bool isDisabled;

  const AsyncButton({
    Key? key,
    required this.onPressed,
    required this.child,
    this.style,
    this.loadingWidget,
    this.isDisabled = false,
  }) : super(key: key);

  /// Creates an [AsyncButton] with an icon and a label.
  factory AsyncButton.icon({
    Key? key,
    required Future<void> Function()? onPressed,
    required Widget icon,
    required Widget label,
    ButtonStyle? style,
    Widget? loadingWidget,
    bool isDisabled = false,
  }) {
    return AsyncButton(
      key: key,
      onPressed: onPressed,
      style: style,
      loadingWidget: loadingWidget,
      isDisabled: isDisabled,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 8),
          label,
        ],
      ),
    );
  }

  @override
  State<AsyncButton> createState() => _AsyncButtonState();
}

class _AsyncButtonState extends State<AsyncButton> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final bool effectivelyDisabled = widget.isDisabled || widget.onPressed == null || _isLoading;

    return ElevatedButton(
      onPressed: effectivelyDisabled
          ? null
          : () async {
              setState(() => _isLoading = true);
              try {
                await widget.onPressed!();
              } finally {
                if (mounted) {
                  setState(() => _isLoading = false);
                }
              }
            },
      style: widget.style,
      child: _isLoading
          ? (widget.loadingWidget ??
              const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ))
          : widget.child,
    );
  }
}

/// Extension to easily wrap any button logic with a loading state if needed,
/// though using [AsyncButton] is preferred for consistency.
class AsyncIconButton extends StatefulWidget {
  final Future<void> Function()? onPressed;
  final Widget icon;
  final Widget? loadingWidget;
  final String? tooltip;

  const AsyncIconButton({
    Key? key,
    required this.onPressed,
    required this.icon,
    this.loadingWidget,
    this.tooltip,
  }) : super(key: key);

  @override
  State<AsyncIconButton> createState() => _AsyncIconButtonState();
}

class _AsyncIconButtonState extends State<AsyncIconButton> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: (_isLoading || widget.onPressed == null)
          ? null
          : () async {
              setState(() => _isLoading = true);
              try {
                await widget.onPressed!();
              } finally {
                if (mounted) {
                  setState(() => _isLoading = false);
                }
              }
            },
      tooltip: widget.tooltip,
      icon: _isLoading
          ? (widget.loadingWidget ??
              const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ))
          : widget.icon,
    );
  }
}

class AsyncTextButton extends StatefulWidget {
  final Future<void> Function()? onPressed;
  final Widget child;
  final ButtonStyle? style;
  final Widget? loadingWidget;
  final bool isDisabled;

  const AsyncTextButton({
    Key? key,
    required this.onPressed,
    required this.child,
    this.style,
    this.loadingWidget,
    this.isDisabled = false,
  }) : super(key: key);

  /// Creates an [AsyncTextButton] with an icon and a label.
  factory AsyncTextButton.icon({
    Key? key,
    required Future<void> Function()? onPressed,
    required Widget icon,
    required Widget label,
    ButtonStyle? style,
    Widget? loadingWidget,
    bool isDisabled = false,
  }) {
    return AsyncTextButton(
      key: key,
      onPressed: onPressed,
      style: style,
      loadingWidget: loadingWidget,
      isDisabled: isDisabled,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 8),
          label,
        ],
      ),
    );
  }

  @override
  State<AsyncTextButton> createState() => _AsyncTextButtonState();
}

class _AsyncTextButtonState extends State<AsyncTextButton> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final bool effectivelyDisabled =
        widget.isDisabled || widget.onPressed == null || _isLoading;

    return TextButton(
      onPressed: effectivelyDisabled
          ? null
          : () async {
              setState(() => _isLoading = true);
              try {
                await widget.onPressed!();
              } finally {
                if (mounted) {
                  setState(() => _isLoading = false);
                }
              }
            },
      style: widget.style,
      child: _isLoading
          ? (widget.loadingWidget ??
              const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ))
          : widget.child,
    );
  }
}
