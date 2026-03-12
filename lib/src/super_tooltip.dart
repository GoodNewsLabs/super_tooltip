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
typedef TouchThroughAreaBuilder = Rect? Function(Rect childArea);

/// A powerful and customizable tooltip widget for Flutter.
///
/// `SuperTooltip` provides a flexible and feature-rich way to display tooltips
/// in your Flutter applications with extensive customization options.
class SuperTooltip extends StatefulWidget {
  const SuperTooltip({
    Key? key,
    required this.content,
    this.controller,
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
    this.useRootOverlay = true,
    this.mouseCursor,
    this.onLongPress,
    this.onShow,
    this.onHide,
  }) : super(key: key);

  /// The widget to be displayed inside the tooltip.
  final Widget content;

  /// Controller to manage the tooltip's visibility and state.
  final SuperTooltipController? controller;

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

  /// Builder for the rectangular area that allows touch events to pass through
  /// the barrier. The input is the child's area in overlay coordinates.
  final TouchThroughAreaBuilder? touchThroughAreaBuilder;

  /// Shape of the touch-through area.
  final ClipAreaShape touchThroughAreaShape;

  /// Corner radius of the touch-through area.
  final double touchThroughAreaCornerRadius;

  /// EdgeInsetsGeometry for the overlay.
  final EdgeInsetsGeometry overlayDimensions;

  /// Determines whether the tooltip is mounted into the root [Overlay] or the
  /// current widget tree.
  final bool useRootOverlay;

  /// Mouse cursor when hovering over the child.
  final MouseCursor? mouseCursor;

  /// Callback when the user long presses the target widget.
  final VoidCallback? onLongPress;

  /// Callback when the tooltip is shown.
  final VoidCallback? onShow;

  /// Callback when the tooltip is hidden.
  final VoidCallback? onHide;

  /// Key used to identify the inside close button.
  static const Key insideCloseButtonKey = Key('InsideCloseButtonKey');

  /// Key used to identify the outside close button.
  static const Key outsideCloseButtonKey = Key('OutsideCloseButtonKey');

  /// Key used to identify the barrier.
  static const Key barrierKey = Key('barrierKey');

  /// Key used to identify the bubble.
  static const Key bubbleKey = Key('bubbleKey');

  @override
  State<SuperTooltip> createState() => _SuperTooltipState();
}

class _SuperTooltipState extends State<SuperTooltip>
    with SingleTickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _targetKey = GlobalKey();
  final OverlayPortalController _localPortalController =
      OverlayPortalController(debugLabel: 'SuperTooltipLocalOverlay');
  late AnimationController _animationController;
  late SuperTooltipController _controller;
  bool _ownsController = false;

  OverlayEntry? _tooltipEntry;
  OverlayEntry? _barrierEntry;
  OverlayEntry? _blurEntry;

  TooltipDirection _resolvedDirection = TooltipDirection.down;

  Timer? _showTimer;
  Timer? _hideTimer;
  Timer? _showDurationTimer;

  bool get _isNativeMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  bool get _isLocalMount => !widget.useRootOverlay;

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

  Animation<double> get _tooltipAnimation => CurvedAnimation(
    parent: _animationController,
    curve: Curves.fastOutSlowIn,
  );

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
    _handleOverlayMountUpdate(oldWidget);
  }

  void _handleControllerUpdate(SuperTooltip oldWidget) {
    if (oldWidget.controller == widget.controller) return;

    _controller.removeListener(_onControllerChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    _initializeController();
  }

  void _handleOverlayMountUpdate(SuperTooltip oldWidget) {
    if (oldWidget.useRootOverlay == widget.useRootOverlay) return;

    if (_tooltipEntry != null) {
      _removeEntries();
    }

    if (_localPortalController.isShowing) {
      _localPortalController.hide();
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
    _removeAllOverlayEntries();
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

  void _removeAllOverlayEntries() {
    if (_tooltipEntry != null) {
      _removeEntries();
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = CompositedTransformTarget(
      link: _layerLink,
      child: KeyedSubtree(
        key: _targetKey,
        child: GestureDetector(
          onTap: _handleTap,
          onLongPress: widget.onLongPress,
          child: widget.child,
        ),
      ),
    );

    final content = MouseRegion(
      cursor: widget.mouseCursor ?? SystemMouseCursors.basic,
      hitTestBehavior: HitTestBehavior.translucent,
      onEnter: _handleMouseEnter,
      onExit: _handleMouseExit,
      child: target,
    );

    if (!_isLocalMount) {
      return content;
    }

    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _localPortalController,
      overlayChildBuilder: (context, info) => _buildLocalOverlayContent(info),
      child: content,
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
    _showTimer?.cancel();

    if (_isLocalMount) {
      if (_localPortalController.isShowing) return;
      _localPortalController.show();
    } else {
      if (_tooltipEntry != null) return;
      _createOverlayEntries();
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

    if (_isLocalMount) {
      _localPortalController.hide();
      return;
    }

    _removeEntries();
  }

  void _createOverlayEntries() {
    final overlayState = Overlay.of(
      context,
      rootOverlay: widget.useRootOverlay,
    );
    final targetBox =
        _targetKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = overlayState.context.findRenderObject() as RenderBox?;

    if (targetBox == null || overlay == null) {
      return;
    }

    final target = targetBox.localToGlobal(targetBox.size.center(Offset.zero));
    final childArea = Rect.fromLTWH(
      target.dx - targetBox.size.width / 2,
      target.dy - targetBox.size.height / 2,
      targetBox.size.width,
      targetBox.size.height,
    );
    final offsetToTarget = Offset(
      -target.dx + targetBox.size.width / 2,
      -target.dy + targetBox.size.height / 2,
    );
    final backgroundColor =
        widget.style.backgroundColor ?? Theme.of(context).cardColor;
    final positionData = _calculatePosition(target, overlay.size);
    _resolvedDirection = positionData.direction;

    final touchThroughArea = _resolveTouchThroughArea(childArea);

    _barrierEntry = _shouldShowBarrier
        ? _createBarrierEntry(clipRect: touchThroughArea)
        : null;
    _blurEntry = widget.barrierConfig.showBlur ? _createBlurEntry() : null;
    _tooltipEntry = _createGlobalTooltipEntry(
      offsetToTarget: offsetToTarget,
      target: target,
      backgroundColor: backgroundColor,
      overlay: overlay,
      positionData: positionData,
    );

    overlayState.insertAll([
      if (widget.barrierConfig.showBlur) _blurEntry!,
      if (_shouldShowBarrier) _barrierEntry!,
      _tooltipEntry!,
    ]);
  }

  OverlayEntry _createBarrierEntry({Rect? clipRect}) {
    return OverlayEntry(
      builder: (context) => FadeTransition(
        opacity: _tooltipAnimation,
        child: _buildBarrierLayer(clipRect: clipRect),
      ),
    );
  }

  OverlayEntry _createBlurEntry() {
    return OverlayEntry(
      builder: (context) =>
          FadeTransition(opacity: _tooltipAnimation, child: _buildBlurLayer()),
    );
  }

  OverlayEntry _createGlobalTooltipEntry({
    required Offset offsetToTarget,
    required Offset target,
    required Color backgroundColor,
    required RenderBox overlay,
    required _PositionData positionData,
  }) {
    return OverlayEntry(
      builder: (context) => IgnorePointer(
        ignoring: widget.interactionConfig.clickThrough,
        child: FadeTransition(
          opacity: _tooltipAnimation,
          child: Center(
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: offsetToTarget,
              child: _buildTooltipLayout(
                target: target,
                backgroundColor: backgroundColor,
                overlay: overlay,
                positionData: positionData,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocalOverlayContent(OverlayChildLayoutInfo info) {
    final overlayContext = Overlay.of(context).context;
    final childTopLeft = MatrixUtils.transformPoint(
      info.childPaintTransform,
      Offset.zero,
    );
    final childArea = Rect.fromLTWH(
      childTopLeft.dx,
      childTopLeft.dy,
      info.childSize.width,
      info.childSize.height,
    );
    final target = childArea.center;
    final geometry = _resolveLocalOverlayGeometry(
      overlayContext: overlayContext,
      overlaySize: info.overlaySize,
      childArea: childArea,
    );
    final clipRect = geometry.clipRect;
    final localTouchThroughArea = geometry.localTouchThroughArea;
    final localTarget = target - clipRect.topLeft;
    final positionData = _calculatePosition(localTarget, clipRect.size);
    _resolvedDirection = positionData.direction;
    final backgroundColor =
        widget.style.backgroundColor ?? Theme.of(context).cardColor;

    return Positioned(
      left: clipRect.left,
      top: clipRect.top,
      width: clipRect.width,
      height: clipRect.height,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            if (widget.barrierConfig.showBlur)
              FadeTransition(
                opacity: _tooltipAnimation,
                child: _buildBlurLayer(),
              ),
            if (_shouldShowBarrier)
              FadeTransition(
                opacity: _tooltipAnimation,
                child: _buildBarrierLayer(clipRect: localTouchThroughArea),
              ),
            IgnorePointer(
              ignoring: widget.interactionConfig.clickThrough,
              child: FadeTransition(
                opacity: _tooltipAnimation,
                child: _buildTooltipLayout(
                  target: localTarget,
                  backgroundColor: backgroundColor,
                  overlay: null,
                  positionData: positionData,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _LocalOverlayGeometry _resolveLocalOverlayGeometry({
    required BuildContext overlayContext,
    required Size overlaySize,
    required Rect childArea,
  }) {
    final clipRect = _resolveLocalClipRect(
      overlayContext: overlayContext,
      overlaySize: overlaySize,
    );
    final localBounds = Offset.zero & clipRect.size;
    final localTouchThroughArea = _resolveTouchThroughArea(
      childArea,
    )?.shift(-clipRect.topLeft).intersect(localBounds);

    return _LocalOverlayGeometry(
      clipRect: clipRect,
      localTouchThroughArea: localTouchThroughArea?.isEmpty ?? true
          ? null
          : localTouchThroughArea,
    );
  }

  Rect _resolveLocalClipRect({
    required BuildContext overlayContext,
    required Size overlaySize,
  }) {
    final overlayBox = overlayContext.findRenderObject() as RenderBox?;
    final scrollableState = Scrollable.maybeOf(context);
    final scrollableBox =
        scrollableState?.context.findRenderObject() as RenderBox?;

    if (overlayBox == null || scrollableBox == null) {
      return Offset.zero & overlaySize;
    }

    final topLeft = overlayBox.globalToLocal(
      scrollableBox.localToGlobal(Offset.zero),
    );
    return Rect.fromLTWH(
      topLeft.dx.clamp(0.0, overlaySize.width),
      topLeft.dy.clamp(0.0, overlaySize.height),
      scrollableBox.size.width.clamp(0.0, overlaySize.width - topLeft.dx),
      scrollableBox.size.height.clamp(0.0, overlaySize.height - topLeft.dy),
    );
  }

  Rect? _resolveTouchThroughArea(Rect childArea) {
    return widget.touchThroughAreaBuilder?.call(childArea);
  }

  Widget _buildBarrierLayer({Rect? clipRect}) {
    return GestureDetector(
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
    );
  }

  Widget _buildBlurLayer() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: widget.barrierConfig.sigmaX,
          sigmaY: widget.barrierConfig.sigmaY,
        ),
        child: Container(width: double.infinity, height: double.infinity),
      ),
    );
  }

  Widget _buildTooltipLayout({
    required Offset target,
    required Color backgroundColor,
    required RenderBox? overlay,
    required _PositionData positionData,
  }) {
    return CustomSingleChildLayout(
      delegate: SuperToolTipPositionDelegate(
        preferredDirection: positionData.direction,
        constraints: positionData.constraints,
        top: positionData.top,
        bottom: positionData.bottom,
        left: positionData.left,
        right: positionData.right,
        target: target,
        overlay: overlay,
        margin: widget.positionConfig.minimumOutsideMargin,
        snapsFarAwayHorizontally:
            widget.positionConfig.snapsFarAwayHorizontally,
        snapsFarAwayVertically: widget.positionConfig.snapsFarAwayVertically,
      ),
      child: Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          _buildTooltipBubble(target, backgroundColor, positionData),
          _buildCloseButton(),
        ],
      ),
    );
  }

  Widget _buildTooltipBubble(
    Offset target,
    Color backgroundColor,
    _PositionData positionData,
  ) {
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
            preferredDirection: _resolvedDirection,
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
              _buildDefaultDecoration(backgroundColor, target, positionData),
          child: widget.content,
        ),
      ),
    );
  }

  Decoration _buildDefaultDecoration(
    Color backgroundColor,
    Offset target,
    _PositionData positionData,
  ) {
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
        preferredDirection: _resolvedDirection,
        right: positionData.right,
        target: target,
        top: positionData.top,
        bubbleDimensions: widget.style.bubbleDimensions,
      ),
    );
  }

  Widget _buildCloseButton() {
    if (!widget.closeButtonConfig.show) {
      return const SizedBox.shrink();
    }

    final buttonPosition = _calculateCloseButtonPosition();

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

  ({double right, double top}) _calculateCloseButtonPosition() {
    final isInside = widget.closeButtonConfig.type == CloseButtonType.inside;

    switch (_resolvedDirection) {
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

  _PositionData _calculatePosition(Offset target, Size? overlaySize) {
    var constraints = widget.constraints;
    var preferredDirection =
        widget.positionConfig.preferredDirectionBuilder?.call() ??
        widget.positionConfig.preferredDirection;
    var left = widget.positionConfig.left;
    var right = widget.positionConfig.right;
    var top = widget.positionConfig.top;
    var bottom = widget.positionConfig.bottom;

    if (preferredDirection == TooltipDirection.auto && overlaySize != null) {
      preferredDirection = _resolveAutoDirection(
        target,
        overlaySize,
        constraints,
      );
    }

    if (widget.positionConfig.snapsFarAwayVertically) {
      final snapData = _handleVerticalSnapping(target, overlaySize);
      constraints = snapData.constraints;
      left = snapData.left;
      right = snapData.right;
      top = snapData.top;
      bottom = snapData.bottom;
      preferredDirection = snapData.direction;
    } else if (widget.positionConfig.snapsFarAwayHorizontally) {
      final snapData = _handleHorizontalSnapping(target, overlaySize);
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
    Size overlaySize,
    BoxConstraints constraints,
  ) {
    final estimatedSize = Size(
      constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : overlaySize.width * 0.8,
      constraints.maxHeight.isFinite
          ? constraints.maxHeight
          : overlaySize.height * 0.4,
    );

    final margin = widget.positionConfig.minimumOutsideMargin;

    final spaceAbove = target.dy - margin;
    final spaceBelow = overlaySize.height - target.dy - margin;
    final spaceLeft = target.dx - margin;
    final spaceRight = overlaySize.width - target.dx - margin;

    if (spaceBelow >= estimatedSize.height) {
      return TooltipDirection.down;
    } else if (spaceAbove >= estimatedSize.height) {
      return TooltipDirection.up;
    } else if (spaceRight >= estimatedSize.width) {
      return TooltipDirection.right;
    } else if (spaceLeft >= estimatedSize.width) {
      return TooltipDirection.left;
    }

    final candidates = {
      TooltipDirection.down: spaceBelow,
      TooltipDirection.up: spaceAbove,
      TooltipDirection.right: spaceRight,
      TooltipDirection.left: spaceLeft,
    };

    return candidates.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  _SnapData _handleVerticalSnapping(Offset target, Size? overlaySize) {
    final constraints = widget.constraints.copyWith(maxHeight: null);
    final left = 0.0;
    final right = 0.0;

    if (overlaySize != null) {
      final isUpperHalf = target.dy > overlaySize.center(Offset.zero).dy;
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

  _SnapData _handleHorizontalSnapping(Offset target, Size? overlaySize) {
    final constraints = widget.constraints.copyWith(maxHeight: null);
    final top = 0.0;
    final bottom = 0.0;

    if (overlaySize != null) {
      final isLeftHalf = target.dx < overlaySize.center(Offset.zero).dx;
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

class _LocalOverlayGeometry {
  const _LocalOverlayGeometry({
    required this.clipRect,
    required this.localTouchThroughArea,
  });

  final Rect clipRect;
  final Rect? localTouchThroughArea;
}

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
