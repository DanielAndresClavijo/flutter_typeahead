import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Holds the last known size and offset of the widget
/// to which the floater is attached.
typedef FloaterInfo = ({
  Size size,
  Offset offset,
});

/// Connects a [Floater] with a [FloaterTarget].
///
/// All public members are for internal use only.
class FloaterLink extends ValueNotifier<FloaterInfo> {
  FloaterLink()
      : super(
          (size: Size.zero, offset: Offset.zero),
        );

  final LayerLink layerLink = LayerLink();

  /// Manually trigger an update of the floater.
  ///
  /// This is useful when our automatic resizing fails,
  /// however, that should not happen.
  void markNeedsBuild() => notifyListeners();
}

/// A widgt to which a [Floater] can be attached.
class FloaterTarget extends StatelessWidget {
  const FloaterTarget({
    super.key,
    required this.link,
    required this.child,
  });

  final FloaterLink link;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: link.layerLink,
      child: _FloaterTarget(
        link: link,
        child: child,
      ),
    );
  }
}

class _FloaterTarget extends SingleChildRenderObjectWidget {
  const _FloaterTarget({
    Key? key,
    Widget? child,
    required this.link,
  }) : super(key: key, child: child);

  final FloaterLink link;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderFloaterTarget(
      controller: link,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, _RenderFloaterTarget renderObject) {
    renderObject.controller = link;
  }

  @override
  void didUnmountRenderObject(_RenderFloaterTarget renderObject) {
    renderObject.controller = null;
  }
}

class _RenderFloaterTarget extends RenderProxyBox {
  _RenderFloaterTarget({
    RenderBox? child,
    required FloaterLink controller,
  })  : _controller = controller,
        super(child) {
    _controller?.addListener(_onLinkNotification);
  }

  void _onLinkNotification() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      markNeedsLayout();
    });
  }

  bool _disposed = false;

  FloaterLink? _controller;
  FloaterLink? get controller => _controller;
  set controller(FloaterLink? newController) {
    if (_controller == newController) return;
    _controller?.removeListener(_onLinkNotification);
    _controller = newController;
    _controller?.addListener(_onLinkNotification);
    _onLinkNotification();
  }

  @override
  void detach() {
    controller?.removeListener(_onLinkNotification);
    super.detach();
  }

  @override
  void dispose() {
    controller?.removeListener(_onLinkNotification);
    _disposed = true;
    super.dispose();
  }

  @override
  void performLayout() {
    super.performLayout();
    controller?.value = (
      size: size,
      offset: controller!.value.offset,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    controller?.value = (
      size: controller!.value.size,
      offset: localToGlobal(Offset.zero),
    );
  }
}

// Describes how the Floater is anchored to the space and the target.
class FloaterAnchor {
  /// Creates a new [FloaterAnchor].
  const FloaterAnchor.only({
    this.top = true,
    this.bottom = true,
    this.left = true,
    this.right = true,
  });

  factory FloaterAnchor.fromLRTB(bool left, bool right, bool top, bool bottom) {
    return FloaterAnchor.only(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
    );
  }

  factory FloaterAnchor.all(bool value) {
    return FloaterAnchor.only(
      top: value,
      bottom: value,
      left: value,
      right: value,
    );
  }

  factory FloaterAnchor.symmetric({
    bool horizontal = true,
    bool vertical = true,
  }) {
    return FloaterAnchor.only(
      top: vertical,
      bottom: vertical,
      left: horizontal,
      right: horizontal,
    );
  }

  /// Whether the floater is anchored to the top of the target.
  final bool top;

  /// Whether the floater is anchored to the bottom of the target.
  final bool bottom;

  /// Whether the floater is anchored to the left of the target.
  final bool left;

  /// Whether the floater is anchored to the right of the target.
  final bool right;

  @override
  bool operator ==(Object other) {
    return other is FloaterAnchor &&
        other.top == top &&
        other.bottom == bottom &&
        other.left == left &&
        other.right == right;
  }

  @override
  int get hashCode => Object.hash(
        top,
        bottom,
        left,
        right,
      );

  @override
  String toString() {
    return 'FloaterAnchor(top: $top, bottom: $bottom, left: $left, right: $right)';
  }

  FloaterAnchor copyWith({
    bool? top,
    bool? bottom,
    bool? left,
    bool? right,
  }) {
    return FloaterAnchor.only(
      top: top ?? this.top,
      bottom: bottom ?? this.bottom,
      left: left ?? this.left,
      right: right ?? this.right,
    );
  }
}

extension EdgeInsetsPositive on EdgeInsets {
  EdgeInsets positive() => EdgeInsets.only(
        top: max(0, top),
        bottom: max(0, bottom),
        left: max(0, left),
        right: max(0, right),
      );
}

/// A widget that can float next to a [FloaterTarget], inheriting its size.
///
/// Floaters use the surrounding [Overlay] to position themselves.
class Floater extends StatefulWidget {
  const Floater({
    super.key,
    this.child,
    required this.builder,
    required this.link,
    this.direction = AxisDirection.down,
    this.anchor = const FloaterAnchor.only(bottom: false),
    this.padding = EdgeInsets.zero,
    this.autoFlip = false,
    this.autoFlipHeight = 100,
  });

  /// The widget below this widget in the tree.
  final Widget? child;

  /// Builds the content of the floater.
  final WidgetBuilder builder;

  /// The link to the [FloaterTarget] to which the floater should attach.
  final FloaterLink link;

  /// The offset of the floater in relation to the target and the space.
  ///
  /// This is layed out in relation to [direction].
  /// That means, left is cross axis start, right is cross axis end, top is main axis start, and bottom is main axis end.
  final EdgeInsets padding;

  /// Describes how the floater is anchored to the space and the target.
  ///
  /// This is layed out in relation to [direction].
  /// That means, left is cross axis start, right is cross axis end, top is main axis start, and bottom is main axis end.
  ///
  /// Is a given direction [false], the floater will take up all available space in that direction,
  /// until it reaches the edge of the space.
  /// Is it [true], the floater will stop at the limits of the target.
  final FloaterAnchor anchor;

  /// The desired direction of the floater.
  ///
  /// The floater will try to open in this direction.
  /// This also defines how much space the floater has to grow.
  final AxisDirection direction;

  /// Whether the floater should automatically flip direction if there's not enough space.
  ///
  /// The minimum height of the floater is defined by [autoFlipHeight].
  /// Defaults to false.
  final bool autoFlip;

  /// The minimum height of the floater before it attempts to flip direction.
  final double autoFlipHeight;

  /// Returns the [FloaterData] of the closest [Floater] ancestor, or null if there is no [Floater] ancestor.
  static FloaterData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FloaterProvider>()?.data;

  /// Returns the [FloaterData] of the closest [Floater] ancestor.
  static FloaterData of(BuildContext context) {
    FloaterData? data = maybeOf(context);
    if (data == null) {
      throw FlutterError.fromParts(
        [
          ErrorSummary(
            'Floater.of() called with a context '
            'that does not contain a Floater.',
          ),
          ErrorDescription(
            'No Floater ancestor could be found '
            'starting from the context that was passed to Floater.of().',
          ),
          context.describeElement('The context used was'),
        ],
      );
    }
    return data;
  }

  @override
  State<Floater> createState() => _FloaterState();
}

class _FloaterState extends State<Floater> with WidgetsBindingObserver {
  OverlayPortalController controller = OverlayPortalController();

  List<Object?>? dependencies;
  EdgeInsets? insets;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.link.addListener(updateOverlay);
    maybeUpdateOverlay();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    maybeUpdateOverlay();
  }

  @override
  void dispose() {
    widget.link.removeListener(updateOverlay);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // When the keyboard is toggled, we need to update the floater,
    // since its constraints might have changed.
    OverlayState overlay = Overlay.of(context);
    MediaQueryData mediaQuery = MediaQuery.of(overlay.context);
    if (insets != mediaQuery.viewInsets) {
      insets = mediaQuery.viewInsets;
      updateOverlay();
    }
  }

  void maybeUpdateOverlay() {
    final List<Object?> newDependencies = createDependencies();
    if (!listEquals(dependencies, newDependencies)) {
      dependencies = newDependencies;
      updateOverlay();
    }
  }

  void updateOverlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
      controller.show();
    });
  }

  List<Object?> createDependencies() => [
        widget.link,
        widget.link.value,
        widget.direction,
        widget.anchor,
        widget.padding,
      ];

  ({
    Size size,
    Offset offset,
    EdgeInsets viewInsets,
    EdgeInsets viewPadding,
  }) getOverlayConstraints(OverlayState overlay) {
    final RenderBox overlayBox =
        overlay.context.findRenderObject()! as RenderBox;

    Offset overlayOffset = overlayBox.localToGlobal(Offset.zero);
    Size overlaySize = overlayBox.size;

    MediaQueryData mediaQuery = MediaQuery.of(overlay.context);
    EdgeInsets viewInsets = mediaQuery.viewInsets;
    EdgeInsets viewPadding = mediaQuery.padding;

    overlayOffset = Offset(
      overlayOffset.dx,
      overlayOffset.dy,
    );

    overlaySize = Size(
      overlaySize.width,
      overlaySize.height,
    );

    return (
      size: overlaySize,
      offset: overlayOffset,
      viewInsets: viewInsets,
      viewPadding: viewPadding,
    );
  }

  /// Applies screen boundary constraints to the calculated size.
  ///
  /// This ensures the floater doesn't extend beyond the keyboard (for down direction)
  /// or the status bar (for up direction), with a 5px margin.
  Size _applyScreenBoundaryConstraints(
    Size calculatedSize,
    AxisDirection direction,
    Offset globalOffset,
    Size targetSize,
    Size overlaySize,
    EdgeInsets viewInsets,
    EdgeInsets viewPadding,
  ) {
    if (direction == AxisDirection.down && viewInsets.bottom > 0) {
      // Calculate actual space from target bottom to keyboard top
      double targetBottom = globalOffset.dy + targetSize.height;
      double keyboardTop = overlaySize.height - viewInsets.bottom;
      // Inserted padding to ensure margin from keyboard 
      double paddingBottom = 8;
      double availableHeight = 
          max(0, keyboardTop - targetBottom - paddingBottom);

      return Size(
        calculatedSize.width,
        min(calculatedSize.height, availableHeight),
      );
    } else if (direction == AxisDirection.up) {
      // Calculate actual space from top of screen (after status bar) to target top
      double targetTop = globalOffset.dy;
      double statusBarBottom = viewPadding.top;

      // Inserted padding to ensure margin from status bar
      double paddingTop = 8;
      double availableHeight =
          max(0, targetTop - statusBarBottom - paddingTop);

      return Size(
        calculatedSize.width,
        min(calculatedSize.height, availableHeight),
      );
    }

    return calculatedSize;
  }

  Size getDirectionSize(
    AxisDirection direction,
    Size space,
    Offset offset,
    Size size,
    FloaterAnchor anchor,
    Offset globalOffset,
    Size overlaySize,
    EdgeInsets viewInsets,
    EdgeInsets viewPadding,
  ) {
    Size calculatedSize = switch (direction) {
      AxisDirection.down => Size(
          space.width,
          switch ((anchor.top, anchor.bottom)) {
            (true, true) => size.height,
            (true, false) => space.height - offset.dy.abs(),
            (false, true) => size.height * 2,
            (false, false) => space.height - offset.dy.abs(),
          }),
      AxisDirection.up => Size(
          space.width,
          switch ((anchor.top, anchor.bottom)) {
            (true, true) => size.height,
            (true, false) => offset.dy + size.height,
            (false, true) => size.height * 2,
            (false, false) => offset.dy + size.height,
          }),
      AxisDirection.left => Size(
          switch ((anchor.top, anchor.bottom)) {
            (true, true) => min(size.width, offset.dx),
            (true, false) => offset.dx,
            (false, true) => min(size.width * 2, offset.dx + size.width),
            (false, false) => offset.dx + size.width,
          },
          space.height,
        ),
      AxisDirection.right => Size(
          switch ((anchor.top, anchor.bottom)) {
            (true, true) => min(size.width, space.width - offset.dx),
            (true, false) => space.width - offset.dx,
            (false, true) =>
              min(size.width * 2, space.width - offset.dx + size.width),
            (false, false) => space.width - offset.dx + size.width,
          },
          space.height,
        ),
    };

    return _applyScreenBoundaryConstraints(
      calculatedSize,
      direction,
      globalOffset,
      size,
      overlaySize,
      viewInsets,
      viewPadding,
    );
  }

  EdgeInsets getDirectionInsets(
    AxisDirection direction,
    Size space,
    Offset offset,
    Size size,
    FloaterAnchor anchor,
  ) =>
      switch (direction) {
        AxisDirection.down => EdgeInsets.only(
            top: (anchor.top ? size.height : 0) + offset.dy,
            left: anchor.left ? offset.dx : 0,
            right: anchor.right ? space.width - offset.dx - size.width : 0,
          ),
        AxisDirection.up => EdgeInsets.only(
            bottom: (anchor.top ? size.height : 0) +
                space.height -
                offset.dy -
                size.height,
            left: anchor.left ? offset.dx : 0,
            right: anchor.right ? space.width - offset.dx - size.width : 0,
          ),
        AxisDirection.left => EdgeInsets.only(
            right: (anchor.top ? size.width : 0) +
                space.width -
                offset.dx -
                size.width,
            top: anchor.left ? offset.dy : 0,
            bottom: anchor.right ? space.height - offset.dy - size.height : 0,
          ),
        AxisDirection.right => EdgeInsets.only(
            left: (anchor.top ? size.width : 0) + offset.dx,
            top: anchor.left ? offset.dy : 0,
            bottom: anchor.right ? space.height - offset.dy - size.height : 0,
          ),
      }
          .positive();

  EdgeInsets getDirectionPadding(
    AxisDirection direction,
    EdgeInsets padding,
  ) =>
      switch (direction) {
        AxisDirection.down => padding,
        AxisDirection.up => EdgeInsets.only(
            top: padding.bottom,
            bottom: padding.top,
            left: padding.left,
            right: padding.right,
          ),
        AxisDirection.left => EdgeInsets.only(
            top: padding.left,
            bottom: padding.right,
            right: padding.top,
            left: padding.bottom,
          ),
        AxisDirection.right => EdgeInsets.only(
            top: padding.left,
            bottom: padding.right,
            right: padding.bottom,
            left: padding.top,
          ),
      };

  (Alignment, Alignment) getDirectionAnchors(
    AxisDirection direction,
  ) =>
      switch (direction) {
        AxisDirection.down => (Alignment.topCenter, Alignment.topCenter),
        AxisDirection.up => (Alignment.bottomCenter, Alignment.bottomCenter),
        AxisDirection.left => (Alignment.centerRight, Alignment.centerRight),
        AxisDirection.right => (Alignment.centerLeft, Alignment.centerLeft),
      };

  Offset getDirectionOffset(
    AxisDirection direction,
    Size space,
    Offset offset,
    Size size,
    FloaterAnchor anchor,
  ) =>
      switch (direction) {
        AxisDirection.down => Offset(
            ((space.width - offset.dx - size.width) - offset.dx) / 2,
            -offset.dy,
          ),
        AxisDirection.up => Offset(
            ((space.width - offset.dx - size.width) - offset.dx) / 2,
            space.height - offset.dy - size.height,
          ),
        AxisDirection.left => Offset(
            offset.dx,
            ((space.height - offset.dy - size.height) - offset.dy) / 2,
          ),
        AxisDirection.right => Offset(
            -offset.dx,
            ((space.height - offset.dy - size.height) - offset.dy) / 2,
          ),
      };

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: controller,
      child: widget.child,
      overlayChildBuilder: (context) => Builder(
        builder: (context) {
          final (size: size, offset: linkOffset) = widget.link.value;

          final (
            size: overlaySize,
            offset: overlayOffset,
            :viewInsets,
            :viewPadding,
          ) = getOverlayConstraints(Overlay.of(context));

          Offset targetOffset = linkOffset - overlayOffset;
          AxisDirection direction = widget.direction;

          // Calculate available space considering keyboard and target position
          // For down direction: space from bottom of target to top of keyboard
          // For up direction: space from top of target to top of screen
          Size space = Size(
            overlaySize.width,
            overlaySize.height - viewInsets.bottom - viewInsets.top,
          );

          bool isValidSpaceWidth = space.width.isFinite && space.width > 0;
          bool isValidSpaceHeight = space.height.isFinite && space.height > 0;

          // If space is invalid (too small or non-finite), hide the overlay
          if (!isValidSpaceWidth || !isValidSpaceHeight) {
            space = Size(
              !isValidSpaceWidth ? size.width : space.width,
              !isValidSpaceHeight ? widget.autoFlipHeight: space.height,
            );
          }

          Size area = getDirectionSize(
            direction,
            space,
            targetOffset,
            size,
            widget.anchor,
            linkOffset,
            overlaySize,
            viewInsets,
            viewPadding,
          );

          EdgeInsets insets;

          if (widget.autoFlip && area.height < widget.autoFlipHeight) {
            AxisDirection opposite = flipAxisDirection(widget.direction);
            Size maybeArea = getDirectionSize(
              opposite,
              space,
              targetOffset,
              size,
              widget.anchor,
              linkOffset,
              overlaySize,
              viewInsets,
              viewPadding,
            );

            if (maybeArea.height > size.height) {
              direction = opposite;
              area = maybeArea;
            }

            insets = getDirectionInsets(
              direction,
              space,
              targetOffset,
              size,
              widget.anchor,
            );
          } else {
            insets = getDirectionInsets(
              direction,
              space,
              targetOffset,
              size,
              widget.anchor,
            );
          }

          bool isValidAreaWidth = area.width.isFinite && area.width > 0;
          bool isValidAreaHeight = area.height.isFinite && area.height > 0;

          // Validate area dimensions - if invalid, hide the overlay
          if (!isValidAreaWidth || !isValidAreaHeight) {
            area = Size(
              !isValidAreaWidth ? size.width : area.width,
              !isValidAreaHeight ? widget.autoFlipHeight : area.height,
            );
          }

          final (targetAnchor, followerAnchor) = getDirectionAnchors(direction);

          final calculatedPadding = (insets +
                  getDirectionPadding(
                    direction,
                    widget.padding,
                  ))
              .positive();

          // Ensure all padding values are valid (non-negative and finite)
          final padding = EdgeInsets.only(
            top: calculatedPadding.top.isFinite && calculatedPadding.top >= 0
                ? calculatedPadding.top
                : 0,
            bottom: calculatedPadding.bottom.isFinite &&
                    calculatedPadding.bottom >= 0
                ? calculatedPadding.bottom
                : 0,
            left: calculatedPadding.left.isFinite && calculatedPadding.left >= 0
                ? calculatedPadding.left
                : 0,
            right:
                calculatedPadding.right.isFinite && calculatedPadding.right >= 0
                    ? calculatedPadding.right
                    : 0,
          );

          // Constraints for the content area
          // Note: padding is applied separately via Padding widget
          BoxConstraints constraints = BoxConstraints(
            maxWidth: area.width,
            maxHeight: area.height - 8,
          );

          // Calculate offset and ensure it's valid (finite values)
          final calculatedOffset = getDirectionOffset(
            direction,
            space,
            targetOffset,
            size,
            widget.anchor,
          );

          final offset = Offset(
            calculatedOffset.dx.isFinite ? calculatedOffset.dx : 0.0,
            calculatedOffset.dy.isFinite ? calculatedOffset.dy : 0.0,
          );

          return CompositedTransformFollower(
            showWhenUnlinked: false,
            link: widget.link.layerLink,
            targetAnchor: targetAnchor,
            followerAnchor: followerAnchor,
            offset: offset,
            child: Padding(
              padding: padding,
              child: MediaQuery.removePadding(
                context: context,
                child: Align(
                  alignment: followerAnchor,
                  child: ConstrainedBox(
                    constraints: constraints,
                    child: _FloaterProvider(
                      data: FloaterData(
                        size: area,
                        offset: targetOffset,
                        direction: widget.direction,
                        effectiveDirection: direction,
                      ),
                      child: Builder(builder: widget.builder),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Information about the current state of a [Floater].
@immutable
class FloaterData {
  const FloaterData({
    required this.size,
    required this.offset,
    required this.direction,
    required this.effectiveDirection,
  });

  /// The maximum size of the floater.
  final Size size;

  /// The global offset of the floater.
  final Offset offset;

  /// The desired direction of the floater.
  final AxisDirection direction;

  /// The effective direction of the floater.
  final AxisDirection effectiveDirection;

  @override
  bool operator ==(Object other) {
    return other is FloaterData &&
        other.size == size &&
        other.offset == offset &&
        other.direction == direction &&
        other.effectiveDirection == effectiveDirection;
  }

  @override
  int get hashCode => Object.hash(
        size,
        offset,
        direction,
        effectiveDirection,
      );
}

class _FloaterProvider extends InheritedWidget {
  const _FloaterProvider({
    required this.data,
    required Widget child,
  }) : super(child: child);

  final FloaterData data;

  @override
  bool updateShouldNotify(_FloaterProvider oldWidget) => oldWidget.data != data;
}
