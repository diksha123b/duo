import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'buddies.dart';
import 'sticker.dart';

/// Renders an [AsyncValue] with consistent loading, error-with-retry and
/// empty states, so no screen forgets one of them.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.data,
    required this.onRetry,
    this.isEmpty,
    this.empty,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback onRetry;
  final bool Function(T data)? isEmpty;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    // Keep showing data during a background refresh instead of flashing a spinner.
    if (value.hasValue && !value.hasError) {
      final v = value.requireValue;
      if (isEmpty?.call(v) ?? false) return empty ?? const EmptyView(message: 'Nothing here yet');
      return data(v);
    }
    if (value.hasError) return ErrorView(error: value.error!, onRetry: onRetry);
    return const LoadingView();
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[const SizedBox(height: 16), Text(message!)],
        ],
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Buddies(size: 72, mood: BuddyMood.sleepy),
            const SizedBox(height: 12),
            Text('well, that didn’t work.', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(error.toString(), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Buddies(size: 72, mood: BuddyMood.waiting),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// The app's primary action button (a [StickerButton]), kept under this name
/// so screens don't care how it's drawn.
class BusyButton extends StatelessWidget {
  const BusyButton({super.key, required this.label, required this.onPressed});

  final String label;
  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) => StickerButton(label: label, onPressed: onPressed);
}

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(error.toString()), behavior: SnackBarBehavior.floating));
}
