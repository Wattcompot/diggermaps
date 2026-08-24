import 'dart:async';

import 'package:flutter/material.dart';

class MapAimingController extends ChangeNotifier {
  MapAimingController({
    required this.canStartFromLongPress,
    this.onAimingStarted,
    this.onFinishRequested,
  });

  final bool Function() canStartFromLongPress;
  final VoidCallback? onAimingStarted;
  final Future<void> Function()? onFinishRequested;

  bool _isAimingMode = false;
  Timer? _aimLongPressTimer;
  int? _aimLongPressPointer;
  Offset? _aimLongPressStartPosition;
  bool _aimingCompletionScheduled = false;

  bool get isAiming => _isAimingMode;

  void onPointerDown(PointerDownEvent event) {
    if (!canStartFromLongPress() ||
        _isAimingMode ||
        _aimLongPressPointer != null) {
      return;
    }
    _aimLongPressPointer = event.pointer;
    _aimLongPressStartPosition = event.position;
    _aimLongPressTimer = Timer(const Duration(milliseconds: 600), () {
      if (_aimLongPressPointer != event.pointer) return;
      _resetTracking();
      _isAimingMode = true;
      notifyListeners();
      onAimingStarted?.call();
    });
  }

  void onPointerMove(PointerMoveEvent event) {
    if (_aimLongPressPointer != event.pointer || _aimLongPressTimer == null) {
      return;
    }
    final start = _aimLongPressStartPosition;
    if (start != null && (event.position - start).distance > 12) {
      _resetTracking();
    }
  }

  void onPointerUp(PointerEvent event) {
    if (_aimLongPressPointer == event.pointer) _resetTracking();
  }

  void startAiming() {
    _resetTracking();
    _isAimingMode = true;
    notifyListeners();
    onAimingStarted?.call();
  }

  Future<void> finishAiming() async {
    if (_aimingCompletionScheduled || !_isAimingMode) return;
    _aimingCompletionScheduled = true;
    _resetTracking();
    _isAimingMode = false;
    notifyListeners();
    try {
      await onFinishRequested?.call();
    } finally {
      _aimingCompletionScheduled = false;
    }
  }

  void cancelAiming() {
    _resetTracking();
    _isAimingMode = false;
    notifyListeners();
  }

  void _resetTracking() {
    _aimLongPressTimer?.cancel();
    _aimLongPressTimer = null;
    _aimLongPressPointer = null;
    _aimLongPressStartPosition = null;
  }

  @override
  void dispose() {
    _resetTracking();
    super.dispose();
  }
}
