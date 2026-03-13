import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bubble_shape.dart';
import 'enums.dart';
import 'shape_overlay.dart';
import 'super_tooltip_configuration.dart';
import 'super_tooltip_controller.dart';
import 'super_tooltip_position_delegate.dart';
import 'super_tooltip_style.dart';
import 'utils.dart';

typedef DecorationBuilder = Decoration Function(Offset target);
typedef TouchThroughAreaBuilder = Rect? Function(Rect area);

/// A powerful and customizable tooltip widget for Flutter.
///
/// `SuperTooltip` provides a flexible and feature-rich way to display tooltips
/// in your Flutter applications with extensive customization options.
///
/// Example:
/// ```dart
/// final _controller = SuperTooltipController();
///
/// GestureDetector(
///   onTap: () => _controller.showTooltip(),
///   child: SuperTooltip(
///     controller: _controller,
///     content: const Text('This is a tooltip!'),
///     child: const Icon(Icons.info),
///   ),
/// )
/// `

class SuperTooltip extends StatefulWidget {
  const SuperTooltip({
    Key? key,
    required this.content,
    this.controller,
    this.useRootOverlay = true,
    this.child,
    this.style = const TooltipStyle(),
    this.arrowConfig = const ArrowConfiguration(),
    this.closeButtonConfig = const CloseButtonConfiguration(),
    this.barrierConfig = const BarrierConfiguration(),
    this.positionConfig = const PositionConfiguration(),
    this.interactionConfig = const InteractionConfiguration(),
    this.animationConfig = const AnimationConfiguration(),
    this.constraints = const BoxConstraints(
      minHeight: 0.0,
      maxHeight: double.infinity,
      minWidth: 0.0,
      maxWidth: double.infinity,
    ),
    this.decorationBuilder,
    this.touchThroughAreaBuilder,
    this.touchThroughAreaShape = ClipAreaShape.oval,
    this.touchThroughAreaCornerRadius = 5.0,
    this.overlayDimensions = const EdgeInsets.all(10),
    this.mouseCursor,
    this.onLongPress,
    this.onShow,
    this.onHide,
  }) : super(key: key);

  /// The widget to be displayed inside the tooltip.
  final Widget content;

  /// Controller to manage the tooltip's visibility and state.
  final SuperTooltipController? controller;

  /// Whether to insert tooltip entries into the root [Overlay].
  ///
  /// When true, the tooltip is shown in the app's root overlay instead of the
  /// nearest local overlay.
  final bool useRootOverlay;

  /// The target widget to which the tooltip is attached.
  final Widget? child;

  /// Styling configuration for the tooltip.
  final TooltipStyle style;

  /// Arrow configuration.
  final ArrowConfiguration arrowConfig;

  /// Close button configuration.
  final CloseButtonConfiguration closeButtonConfig;

  /// Barrier configuration.
  final BarrierConfiguration barrierConfig;

  /// Positioning configuration.
  final PositionConfiguration positionConfig;

  /// Interaction behavior configuration.
  final InteractionConfiguration interactionConfig;

  /// Animation timing configuration.
  final AnimationConfiguration animationConfig;

  /// Box constraints for the tooltip's size.
  final BoxConstraints constraints;

  /// Custom decoration builder for advanced styling.
  final DecorationBuilder? decorationBuilder;

  /// Builder that receives the target child's global rect and returns the
  /// touch-through area for the barrier.
  final TouchThroughAreaBuilder? touchThroughAreaBuilder;

  /// Shape of the touch-through area.
  final ClipAreaShape touchThroughAreaShape;

  /// Corner radius of the touch-through area.
  final double touchThroughAreaCornerRadius;

  /// EdgeInsetsGeometry for the overlay.
  final EdgeInsetsGeometry overlayDimensions;

  /// Mouse cursor when hovering over the child.
  final MouseCursor? mouseCursor;

  /// Callback when the user long presses the target widget.
  final VoidCallback? onLongPress;

  /// Callback when the tooltip is shown.
  final VoidCallback? onShow;

  /// Callback when the tooltip is hidden.
  final VoidCallback? onHide;

  /// Key used to identify the inside close button.
  static const Key insideCloseButtonKey = Key("InsideCloseButtonKey");

  /// Key used to identify the outside close button.
  static const Key outsideCloseButtonKey = Key("OutsideCloseButtonKey");

  /// Key used to identify the barrier.
  static const Key barrierKey = Key("barrierKey");

  /// Key used to identify the bubble.
  static const Key bubbleKey = Key("bubbleKey");

  @override
  State<SuperTooltip> createState() => _SuperTooltipState();
}

class _SuperTooltipState extends State<SuperTooltip>
    with SingleTickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();
  final OverlayPortalController _portalController = OverlayPortalController();
  late AnimationController _animationController;
  late SuperTooltipController _controller;
  bool _ownsController = false;

  OverlayEntry? _tooltipEntry;
  OverlayEntry? _barrierEntry;
  OverlayEntry? _blurEntry;

  Timer? _showTimer;
  Timer? _hideTimer;
  Timer? _showDurationTimer;

  // Computed properties
  bool get _isNativeMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  bool get _shouldShowBarrier {
    if (_isNativeMobile) {
      return widget.barrierConfig.show;
    }
    return widget.interactionConfig.hideOnHoverExit
        ? false
        : widget.barrierConfig.show;
  }

  Color get _effectiveBarrierColor =>
      widget.barrierConfig.color ?? Colors.black54;

  Color get _effectiveCloseButtonColor =>
      widget.closeButtonConfig.color ?? Colors.black;

  double get _effectiveCloseButtonSize => widget.closeButtonConfig.size ?? 30.0;

  Color get _effectiveShadowColor => widget.style.shadowColor ?? Colors.black54;

  double get _effectiveShadowBlurRadius =>
      widget.style.shadowBlurRadius ?? 10.0;

  double get _effectiveShadowSpreadRadius =>
      widget.style.shadowSpreadRadius ?? 5.0;

  Offset get _effectiveShadowOffset => widget.style.shadowOffset ?? Offset.zero;

  @override
  void initState() {
    super.initState();
    _initializeController();
    _initializeAnimationController();
  }

  void _initializeController() {
    if (widget.controller == null) {
      _controller = SuperTooltipController();
      _ownsController = true;
    } else {
      _controller = widget.controller!;
      _ownsController = false;
    }
    _controller.addListener(_onControllerChanged);
  }

  void _initializeAnimationController() {
    _animationController = AnimationController(
      duration: widget.animationConfig.fadeInDuration,
      reverseDuration: widget.animationConfig.fadeOutDuration,
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(SuperTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _handleControllerUpdate(oldWidget);
    _handleAnimationUpdate(oldWidget);
  }

  void _handleControllerUpdate(SuperTooltip oldWidget) {
    if (_controller != widget.controller) {
      _controller.removeListener(_onControllerChanged);
      if (_ownsController) {
        _controller.dispose();
      }
      _initializeController();
    }
  }

  void _handleAnimationUpdate(SuperTooltip oldWidget) {
    if (widget.animationConfig.fadeInDuration !=
            oldWidget.animationConfig.fadeInDuration ||
        widget.animationConfig.fadeOutDuration !=
            oldWidget.animationConfig.fadeOutDuration) {
      _animationController.duration = widget.animationConfig.fadeInDuration;
      _animationController.reverseDuration =
          widget.animationConfig.fadeOutDuration;
    }
  }

  @override
  void dispose() {
    _cancelAllTimers();
    _removeAllTooltipPresentations();
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    _animationController.dispose();
    super.dispose();
  }

  void _cancelAllTimers() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _showDurationTimer?.cancel();
  }

  void _removeAllTooltipPresentations() {
    if (_tooltipEntry != null) {
      _removeEntries();
    }
  }

  @override
  Widget build(BuildContext context) {
    final anchoredChild = MouseRegion(
      cursor: widget.mouseCursor ?? SystemMouseCursors.basic,
      hitTestBehavior: HitTestBehavior.translucent,
      onEnter: _handleMouseEnter,
      onExit: _handleMouseExit,
      child: CompositedTransformTarget(
        link: _layerLink,
        child: GestureDetector(
          onTap: _handleTap,
          onLongPress: widget.onLongPress,
          child: widget.child,
        ),
      ),
    );

    if (widget.useRootOverlay) {
      return anchoredChild;
    }

    return OverlayPortal(
      controller: _portalController,
      overlayChildBuilder: _buildPortalOverlayChild,
      child: anchoredChild,
    );
  }

  void _handleMouseEnter(PointerEnterEvent event) {
    if (!widget.interactionConfig.showOnHover) return;

    _hideTimer?.cancel();
    _showTimer?.cancel();
    _showTimer = Timer(widget.animationConfig.waitDuration, () {
      if (!_controller.isVisible) {
        _controller.showTooltip();
      }
    });
  }

  void _handleMouseExit(PointerExitEvent event) {
    if (!widget.interactionConfig.hideOnHoverExit) return;

    _showTimer?.cancel();
    if (!_controller.isVisible) return;

    _hideTimer?.cancel();
    _hideTimer = Timer(widget.animationConfig.exitDuration, () {
      if (_controller.isVisible) {
        _controller.hideTooltip();
      }
    });
  }

  void _handleTap() {
    if (widget.interactionConfig.toggleOnTap && _controller.isVisible) {
      _controller.hideTooltip();
    } else if (widget.interactionConfig.showOnTap) {
      _controller.showTooltip();
    }
  }

  void _onControllerChanged() {
    switch (_controller.event) {
      case Event.show:
        _showTooltip();
        break;
      case Event.hide:
        _hideTooltip();
        break;
    }
  }

  Future<void> _showTooltip() async {
    widget.onShow?.call();

    if (widget.useRootOverlay) {
      if (_tooltipEntry != null) return;
    } else if (_portalController.isShowing) {
      return;
    }

    _showTimer?.cancel();
    if (widget.useRootOverlay) {
      _createOverlayEntries();
    } else {
      _portalController.show();
    }

    await _animationController.forward().whenComplete(_controller.complete);

    _showDurationTimer?.cancel();
    if (widget.animationConfig.showDuration != null) {
      _showDurationTimer = Timer(widget.animationConfig.showDuration!, () {
        if (_controller.isVisible) {
          _controller.hideTooltip();
        }
      });
    }
  }

  Future<void> _hideTooltip() async {
    widget.onHide?.call();
    _showDurationTimer?.cancel();

    await _animationController.reverse().whenComplete(_controller.complete);
    if (widget.useRootOverlay) {
      _removeEntries();
    } else if (_portalController.isShowing) {
      _portalController.hide();
    }
  }

  void _createOverlayEntries() {
    final overlayState = Overlay.of(context, rootOverlay: true);
    final presentationData = _computePresentationData(
      context,
      rootOverlay: true,
    );
    if (presentationData == null) {
      return;
    }
    final animation = _buildTooltipAnimation();

    _barrierEntry = _shouldShowBarrier
        ? _createBarrierEntry(animation, presentationData.touchThroughArea)
        : null;

    _blurEntry = widget.barrierConfig.showBlur
        ? _createBlurEntry(animation)
        : null;

    _tooltipEntry = _createTooltipEntry(
      animation: animation,
      presentationData: presentationData,
    );

    overlayState.insertAll([
      if (widget.barrierConfig.showBlur) _blurEntry!,
      if (_shouldShowBarrier) _barrierEntry!,
      _tooltipEntry!,
    ]);
  }

  OverlayEntry _createBarrierEntry(
    Animation<double> animation,
    Rect? clipRect,
  ) {
    return OverlayEntry(
      builder: (context) => _buildBarrierLayer(animation, clipRect),
    );
  }

  OverlayEntry _createBlurEntry(Animation<double> animation) {
    return OverlayEntry(builder: (context) => _buildBlurLayer(animation));
  }

  OverlayEntry _createTooltipEntry({
    required Animation<double> animation,
    required _OverlayPresentationData presentationData,
  }) {
    return OverlayEntry(
      builder: (context) =>
          _buildTooltipLayer(animation: animation, data: presentationData),
    );
  }

  Animation<double> _buildTooltipAnimation() {
    return CurvedAnimation(
      parent: _animationController,
      curve: Curves.fastOutSlowIn,
    );
  }

  Widget _buildPortalOverlayChild(BuildContext context) {
    final presentationData = _computePresentationData(
      context,
      rootOverlay: false,
    );
    if (presentationData == null) {
      return const SizedBox.shrink();
    }

    final animation = _buildTooltipAnimation();

    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.barrierConfig.showBlur) _buildBlurLayer(animation),
        if (_shouldShowBarrier)
          _buildBarrierLayer(animation, presentationData.touchThroughArea),
        _buildTooltipLayer(animation: animation, data: presentationData),
      ],
    );
  }

  _OverlayPresentationData? _computePresentationData(
    BuildContext overlayContext, {
    required bool rootOverlay,
  }) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      return null;
    }

    final overlayState = Overlay.of(overlayContext, rootOverlay: rootOverlay);
    final overlay = overlayState.context.findRenderObject() as RenderBox?;
    final size = renderBox.size;
    final childGlobalRect = _globalRectForRenderBox(renderBox);
    final centerTarget = renderBox.localToGlobal(size.center(Offset.zero));
    final backgroundColor =
        widget.style.backgroundColor ?? Theme.of(context).cardColor;
    final touchThroughArea = _resolveTouchThroughArea(
      childGlobalRect: childGlobalRect,
      overlay: overlay,
    );
    final initialPositionData = _calculatePosition(centerTarget, overlay);
    var anchorDirection = initialPositionData.direction;
    var anchorOffset = SuperUtils.tooltipAnchorPoint(
      childSize: size,
      direction: anchorDirection,
    );
    var target = renderBox.localToGlobal(anchorOffset);
    var positionData = _calculatePosition(target, overlay);

    if (positionData.direction != anchorDirection) {
      anchorDirection = positionData.direction;
      anchorOffset = SuperUtils.tooltipAnchorPoint(
        childSize: size,
        direction: anchorDirection,
      );
      target = renderBox.localToGlobal(anchorOffset);
      positionData = _calculatePosition(target, overlay);
    }

    final offsetToTarget = Offset(
      -target.dx + anchorOffset.dx,
      -target.dy + anchorOffset.dy,
    );

    return _OverlayPresentationData(
      target: target,
      offsetToTarget: offsetToTarget,
      backgroundColor: backgroundColor,
      overlay: overlay,
      positionData: positionData,
      touchThroughArea: touchThroughArea,
    );
  }

  Rect _globalRectForRenderBox(RenderBox renderBox) {
    final topLeft = renderBox.localToGlobal(Offset.zero);
    return topLeft & renderBox.size;
  }

  Rect? _resolveTouchThroughArea({
    required Rect childGlobalRect,
    required RenderBox? overlay,
  }) {
    final globalRect = widget.touchThroughAreaBuilder?.call(childGlobalRect);
    if (globalRect == null) {
      return null;
    }
    if (overlay == null) {
      return globalRect;
    }

    final overlayOrigin = overlay.localToGlobal(Offset.zero);
    return globalRect.shift(-overlayOrigin);
  }

  Widget _buildBarrierLayer(Animation<double> animation, Rect? clipRect) {
    return FadeTransition(
      opacity: animation,
      child: GestureDetector(
        onTap: widget.interactionConfig.hideOnBarrierTap
            ? _controller.hideTooltip
            : null,
        onVerticalDragUpdate: widget.interactionConfig.hideOnScroll
            ? (_) => _controller.hideTooltip()
            : null,
        onHorizontalDragUpdate: widget.interactionConfig.hideOnScroll
            ? (_) => _controller.hideTooltip()
            : null,
        child: Container(
          key: SuperTooltip.barrierKey,
          decoration: ShapeDecoration(
            shape: ShapeOverlay(
              clipAreaCornerRadius: widget.touchThroughAreaCornerRadius,
              clipAreaShape: widget.touchThroughAreaShape,
              clipRect: clipRect,
              barrierColor: _effectiveBarrierColor,
              overlayDimensions: widget.overlayDimensions,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBlurLayer(Animation<double> animation) {
    return FadeTransition(
      opacity: animation,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: widget.barrierConfig.sigmaX,
          sigmaY: widget.barrierConfig.sigmaY,
        ),
        child: Container(width: double.infinity, height: double.infinity),
      ),
    );
  }

  Widget _buildTooltipLayer({
    required Animation<double> animation,
    required _OverlayPresentationData data,
  }) {
    return IgnorePointer(
      ignoring: widget.interactionConfig.clickThrough,
      child: FadeTransition(
        opacity: animation,
        child: Center(
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: data.offsetToTarget,
            child: CustomSingleChildLayout(
              delegate: SuperToolTipPositionDelegate(
                preferredDirection: data.positionData.direction,
                constraints: data.positionData.constraints,
                top: data.positionData.top,
                bottom: data.positionData.bottom,
                left: data.positionData.left,
                right: data.positionData.right,
                target: data.target,
                overlay: data.overlay,
                margin: widget.positionConfig.minimumOutsideMargin,
                snapsFarAwayHorizontally:
                    widget.positionConfig.snapsFarAwayHorizontally,
                snapsFarAwayVertically:
                    widget.positionConfig.snapsFarAwayVertically,
              ),
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  _buildTooltipBubble(
                    target: data.target,
                    backgroundColor: data.backgroundColor,
                    positionData: data.positionData,
                    resolvedDirection: data.positionData.direction,
                  ),
                  _buildCloseButton(data.positionData.direction),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTooltipBubble({
    required Offset target,
    required Color backgroundColor,
    required _PositionData positionData,
    required TooltipDirection resolvedDirection,
  }) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.interactionConfig.hideOnTap
            ? _controller.hideTooltip
            : null,
        onVerticalDragUpdate: widget.interactionConfig.hideOnScroll
            ? (_) => _controller.hideTooltip()
            : null,
        onHorizontalDragUpdate: widget.interactionConfig.hideOnScroll
            ? (_) => _controller.hideTooltip()
            : null,
        child: Container(
          key: SuperTooltip.bubbleKey,
          margin: SuperUtils.getTooltipMargin(
            arrowLength: widget.arrowConfig.length,
            arrowTipDistance: widget.arrowConfig.tipDistance,
            closeButtonSize: _effectiveCloseButtonSize,
            preferredDirection: resolvedDirection,
            closeButtonType: widget.closeButtonConfig.type,
            showCloseButton: widget.closeButtonConfig.show,
          ),
          padding: SuperUtils.getTooltipPadding(
            closeButtonSize: _effectiveCloseButtonSize,
            closeButtonType: widget.closeButtonConfig.type,
            showCloseButton: widget.closeButtonConfig.show,
          ),
          decoration:
              widget.decorationBuilder?.call(target) ??
              _buildDefaultDecoration(
                backgroundColor: backgroundColor,
                target: target,
                positionData: positionData,
                resolvedDirection: resolvedDirection,
              ),
          child: widget.content,
        ),
      ),
    );
  }

  Decoration _buildDefaultDecoration({
    required Color backgroundColor,
    required Offset target,
    required _PositionData positionData,
    required TooltipDirection resolvedDirection,
  }) {
    return ShapeDecoration(
      gradient: widget.style.gradient,
      color: widget.style.gradient == null ? backgroundColor : null,
      shadows: widget.style.hasShadow
          ? widget.style.boxShadows ??
                [
                  BoxShadow(
                    blurRadius: _effectiveShadowBlurRadius,
                    spreadRadius: _effectiveShadowSpreadRadius,
                    color: _effectiveShadowColor,
                    offset: _effectiveShadowOffset,
                  ),
                ]
          : null,
      shape: BubbleShape(
        arrowBaseWidth: widget.arrowConfig.baseWidth,
        arrowTipDistance: widget.arrowConfig.tipDistance,
        arrowTipRadius: widget.arrowConfig.tipRadius,
        borderColor: widget.style.borderColor,
        borderRadius: widget.style.borderRadius,
        borderWidth: widget.style.borderWidth,
        bottom: positionData.bottom,
        left: positionData.left,
        preferredDirection: resolvedDirection,
        right: positionData.right,
        target: target,
        top: positionData.top,
        bubbleDimensions: widget.style.bubbleDimensions,
      ),
    );
  }

  Widget _buildCloseButton(TooltipDirection resolvedDirection) {
    if (!widget.closeButtonConfig.show) {
      return const SizedBox.shrink();
    }

    final buttonPosition = _calculateCloseButtonPosition(resolvedDirection);

    return Positioned(
      right: buttonPosition.right,
      top: buttonPosition.top,
      child: Material(
        color: Colors.transparent,
        child: IconButton(
          key: widget.closeButtonConfig.type == CloseButtonType.inside
              ? SuperTooltip.insideCloseButtonKey
              : SuperTooltip.outsideCloseButtonKey,
          icon: Icon(
            Icons.close_outlined,
            size: _effectiveCloseButtonSize,
            color: _effectiveCloseButtonColor,
          ),
          onPressed: _controller.hideTooltip,
        ),
      ),
    );
  }

  ({double right, double top}) _calculateCloseButtonPosition(
    TooltipDirection resolvedDirection,
  ) {
    final isInside = widget.closeButtonConfig.type == CloseButtonType.inside;

    switch (resolvedDirection) {
      case TooltipDirection.left:
        return (
          right:
              widget.arrowConfig.length + widget.arrowConfig.tipDistance + 3.0,
          top: isInside ? 2.0 : 0.0,
        );

      case TooltipDirection.right:
      case TooltipDirection.up:
        return (right: 5.0, top: isInside ? 2.0 : 0.0);

      case TooltipDirection.down:
        return (
          right: 2.0,
          top: isInside
              ? widget.arrowConfig.length + widget.arrowConfig.tipDistance + 2.0
              : 0.0,
        );

      case TooltipDirection.auto:
        return (right: 2.0, top: 0.0);
    }
  }

  _PositionData _calculatePosition(Offset target, RenderBox? overlay) {
    var constraints = widget.constraints;
    var preferredDirection =
        widget.positionConfig.preferredDirectionBuilder?.call() ??
        widget.positionConfig.preferredDirection;
    var left = widget.positionConfig.left;
    var right = widget.positionConfig.right;
    var top = widget.positionConfig.top;
    var bottom = widget.positionConfig.bottom;

    // Auto direction resolution
    if (preferredDirection == TooltipDirection.auto && overlay != null) {
      preferredDirection = _resolveAutoDirection(target, overlay, constraints);
    }

    // Handle snapping behavior
    if (widget.positionConfig.snapsFarAwayVertically) {
      final snapData = _handleVerticalSnapping(target, overlay);
      constraints = snapData.constraints;
      left = snapData.left;
      right = snapData.right;
      top = snapData.top;
      bottom = snapData.bottom;
      preferredDirection = snapData.direction;
    } else if (widget.positionConfig.snapsFarAwayHorizontally) {
      final snapData = _handleHorizontalSnapping(target, overlay);
      constraints = snapData.constraints;
      top = snapData.top;
      bottom = snapData.bottom;
      left = snapData.left;
      right = snapData.right;
      preferredDirection = snapData.direction;
    }

    return _PositionData(
      direction: preferredDirection,
      constraints: constraints,
      top: top,
      bottom: bottom,
      left: left,
      right: right,
    );
  }

  TooltipDirection _resolveAutoDirection(
    Offset target,
    RenderBox overlay,
    BoxConstraints constraints,
  ) {
    final estimatedSize = Size(
      constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : overlay.size.width * 0.8,
      constraints.maxHeight.isFinite
          ? constraints.maxHeight
          : overlay.size.height * 0.4,
    );

    final screen = overlay.size;
    final margin = widget.positionConfig.minimumOutsideMargin;

    final spaceAbove = target.dy - margin;
    final spaceBelow = screen.height - target.dy - margin;
    final spaceLeft = target.dx - margin;
    final spaceRight = screen.width - target.dx - margin;

    // Check if there's enough space in preferred directions
    if (spaceBelow >= estimatedSize.height) {
      return TooltipDirection.down;
    } else if (spaceAbove >= estimatedSize.height) {
      return TooltipDirection.up;
    } else if (spaceRight >= estimatedSize.width) {
      return TooltipDirection.right;
    } else if (spaceLeft >= estimatedSize.width) {
      return TooltipDirection.left;
    }

    // Find direction with most space
    final candidates = {
      TooltipDirection.down: spaceBelow,
      TooltipDirection.up: spaceAbove,
      TooltipDirection.right: spaceRight,
      TooltipDirection.left: spaceLeft,
    };

    return candidates.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  _SnapData _handleVerticalSnapping(Offset target, RenderBox? overlay) {
    final constraints = widget.constraints.copyWith(maxHeight: null);
    final left = 0.0;
    final right = 0.0;

    if (overlay != null) {
      final isUpperHalf = target.dy > overlay.size.center(Offset.zero).dy;
      return _SnapData(
        constraints: constraints,
        left: left,
        right: right,
        top: isUpperHalf ? 0.0 : null,
        bottom: isUpperHalf ? null : 0.0,
        direction: isUpperHalf ? TooltipDirection.up : TooltipDirection.down,
      );
    }

    return _SnapData(
      constraints: constraints,
      left: left,
      right: right,
      top: null,
      bottom: 0.0,
      direction: TooltipDirection.down,
    );
  }

  _SnapData _handleHorizontalSnapping(Offset target, RenderBox? overlay) {
    final constraints = widget.constraints.copyWith(maxHeight: null);
    final top = 0.0;
    final bottom = 0.0;

    if (overlay != null) {
      final isLeftHalf = target.dx < overlay.size.center(Offset.zero).dx;
      return _SnapData(
        constraints: constraints,
        top: top,
        bottom: bottom,
        left: isLeftHalf ? null : 0.0,
        right: isLeftHalf ? 0.0 : null,
        direction: isLeftHalf ? TooltipDirection.right : TooltipDirection.left,
      );
    }

    return _SnapData(
      constraints: constraints,
      top: top,
      bottom: bottom,
      left: 0.0,
      right: null,
      direction: TooltipDirection.left,
    );
  }

  void _removeEntries() {
    _tooltipEntry?.remove();
    _tooltipEntry = null;

    _barrierEntry?.remove();
    _barrierEntry = null;

    _blurEntry?.remove();
    _blurEntry = null;
  }
}

class _OverlayPresentationData {
  const _OverlayPresentationData({
    required this.target,
    required this.offsetToTarget,
    required this.backgroundColor,
    required this.overlay,
    required this.positionData,
    required this.touchThroughArea,
  });

  final Offset target;
  final Offset offsetToTarget;
  final Color backgroundColor;
  final RenderBox? overlay;
  final _PositionData positionData;
  final Rect? touchThroughArea;
}

/// Internal class to hold position calculation results
class _PositionData {
  const _PositionData({
    required this.direction,
    required this.constraints,
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
  });

  final TooltipDirection direction;
  final BoxConstraints constraints;
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;
}

/// Internal class to hold snap calculation results
class _SnapData {
  const _SnapData({
    required this.constraints,
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
    required this.direction,
  });

  final BoxConstraints constraints;
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;
  final TooltipDirection direction;
}
