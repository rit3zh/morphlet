//
//  MorphletSnapshot.mm
//  Pods
//
//  Created by rit3zh CX on 10/1/26.
//

#import "MorphletSnapshot.h"

static UIImageView *_Nullable MorphletImageViewRendering(UIView *view, void (^render)(CGContextRef context)) {
  CGRect bounds = view.bounds;
  if (CGRectIsEmpty(bounds)) {
    return nil;
  }

  UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
  format.opaque = NO;
  UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:bounds format:format];
  UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
    render(context.CGContext);
  }];

  UIImageView *snapshot = [[UIImageView alloc] initWithImage:image];
  snapshot.userInteractionEnabled = NO;
  snapshot.bounds = CGRectMake(0, 0, bounds.size.width, bounds.size.height);
  return snapshot;
}

UIView *_Nullable MorphletSnapshotView(UIView *view) {
  if (CGRectIsEmpty(view.bounds)) {
    return nil;
  }
  UIView *snapshot = [view snapshotViewAfterScreenUpdates:NO];
  if (snapshot) {
    snapshot.userInteractionEnabled = NO;
    snapshot.bounds = CGRectMake(0, 0, view.bounds.size.width, view.bounds.size.height);
    return snapshot;
  }
  return MorphletSnapshotImageView(view);
}

UIImageView *_Nullable MorphletSnapshotImageView(UIView *view) {
  return MorphletImageViewRendering(view, ^(CGContextRef context) {
    if (![view drawViewHierarchyInRect:view.bounds afterScreenUpdates:NO]) {
      [view.layer renderInContext:context];
    }
  });
}

static void MorphletCollectEffectViews(UIView *view, NSMutableArray<UIVisualEffectView *> *effects) {
  for (UIView *child in view.subviews) {
    if (child.hidden) {
      continue;
    }
    if ([child isKindOfClass:UIVisualEffectView.class]) {
      [effects addObject:(UIVisualEffectView *)child];
      MorphletCollectEffectViews(((UIVisualEffectView *)child).contentView, effects);
    } else {
      MorphletCollectEffectViews(child, effects);
    }
  }
}

static void MorphletDisplayIfNeeded(CALayer *layer) {
  [layer displayIfNeeded];
  for (CALayer *sublayer in layer.sublayers) {
    MorphletDisplayIfNeeded(sublayer);
  }
}

UIImageView *_Nullable MorphletContentSnapshotImageView(UIView *view) {
  [view layoutIfNeeded];
  MorphletDisplayIfNeeded(view.layer);

  NSMutableArray<CALayer *> *fills = [NSMutableArray array];
  NSMutableArray *colors = [NSMutableArray array];
  for (UIView *surface in MorphletSurfaceChain(view)) {
    CALayer *layer = MorphletBackgroundLayer(surface);
    if (layer && ![fills containsObject:layer]) {
      [fills addObject:layer];
      [colors addObject:(__bridge id)layer.backgroundColor];
    }
  }

  NSMutableArray<UIVisualEffectView *> *effects = [NSMutableArray array];
  MorphletCollectEffectViews(view, effects);

  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  for (CALayer *layer in fills) {
    layer.backgroundColor = nil;
  }
  for (UIVisualEffectView *effect in effects) {
    effect.layer.hidden = YES;
  }
  UIImageView *snapshot = MorphletImageViewRendering(view, ^(CGContextRef context) {
    [view.layer renderInContext:context];
    for (UIVisualEffectView *effect in effects) {
      UIView *content = effect.contentView;
      CGPoint origin = [content convertPoint:CGPointZero toView:view];
      CGContextSaveGState(context);
      CGContextTranslateCTM(context, origin.x, origin.y);
      [content.layer renderInContext:context];
      CGContextRestoreGState(context);
    }
  });
  for (UIVisualEffectView *effect in effects) {
    effect.layer.hidden = NO;
  }
  for (NSUInteger index = 0; index < fills.count; index++) {
    fills[index].backgroundColor = (__bridge CGColorRef)colors[index];
  }
  [CATransaction commit];

  return snapshot;
}

CALayer *_Nullable MorphletBackgroundLayer(UIView *view) {
  if (view.layer.backgroundColor && CGColorGetAlpha(view.layer.backgroundColor) > 0) {
    return view.layer;
  }
  for (CALayer *layer in view.layer.sublayers) {
    if (layer.backgroundColor && CGColorGetAlpha(layer.backgroundColor) > 0 &&
        CGRectEqualToRect(layer.frame, view.layer.bounds)) {
      return layer;
    }
  }
  return nil;
}

static const CGFloat kSurfaceTolerance = 2;
static const NSInteger kSurfaceMaxDepth = 6;

NSArray<UIView *> *MorphletSurfaceChain(UIView *view) {
  NSMutableArray<UIView *> *chain = [NSMutableArray arrayWithObject:view];
  CGRect bounds = CGRectInset(view.bounds, kSurfaceTolerance, kSurfaceTolerance);
  if (CGRectIsEmpty(bounds)) {
    return chain;
  }

  UIView *current = view;
  for (NSInteger depth = 0; depth < kSurfaceMaxDepth; depth++) {
    UIView *filling = nil;
    for (UIView *child in current.subviews.reverseObjectEnumerator) {
      if (child.hidden || child.alpha < 0.01) {
        continue;
      }
      if (CGRectContainsRect([child convertRect:child.bounds toView:view], bounds)) {
        filling = child;
        break;
      }
    }
    if (!filling) {
      break;
    }
    [chain addObject:filling];
    current = filling;
  }
  return chain;
}

static CGFloat MorphletOwnCornerRadius(UIView *view) {
  CGFloat radius = MAX(view.layer.cornerRadius, MorphletBackgroundLayer(view).cornerRadius);
  if (@available(iOS 26.0, *)) {
    CGFloat corners = [view effectiveRadiusForCorner:UIRectCornerTopLeft] +
                      [view effectiveRadiusForCorner:UIRectCornerTopRight] +
                      [view effectiveRadiusForCorner:UIRectCornerBottomLeft] +
                      [view effectiveRadiusForCorner:UIRectCornerBottomRight];
    radius = MAX(radius, corners / 4);
  }
  return radius;
}

CGFloat MorphletCornerRadius(UIView *view) {
  for (UIView *surface in MorphletSurfaceChain(view)) {
    CGFloat radius = MorphletOwnCornerRadius(surface);
    if (radius > 0) {
      return MIN(radius, MIN(view.bounds.size.width, view.bounds.size.height) / 2);
    }
  }
  return 0;
}

static void MorphletCompositeWithOpacity(CGFloat *rgba, UIColor *below, CGFloat opacity, UITraitCollection *traits) {
  CGFloat r = 0, g = 0, b = 0, a = 0;
  [[below resolvedColorWithTraitCollection:traits] getRed:&r green:&g blue:&b alpha:&a];
  a *= opacity;
  CGFloat remaining = 1 - rgba[3];
  rgba[0] += r * a * remaining;
  rgba[1] += g * a * remaining;
  rgba[2] += b * a * remaining;
  rgba[3] += a * remaining;
}

static void MorphletComposite(CGFloat *rgba, UIColor *below, UITraitCollection *traits) {
  MorphletCompositeWithOpacity(rgba, below, 1, traits);
}

static CGFloat MorphletSurfaceOpacity(NSArray<UIView *> *chain, UIView *surface) {
  CGFloat opacity = 1;
  for (UIView *candidate in chain) {
    opacity *= candidate.alpha;
    if (candidate == surface) {
      break;
    }
  }
  return opacity;
}

static const CGFloat kSamplePixels = 24;

static UIColor *_Nullable MorphletRenderedColor(UIView *view) {
  UIWindow *window = view.window;
  if (!window) {
    return nil;
  }
  CGRect rect = [view convertRect:view.bounds toView:nil];
  CGRect band = CGRectInset(rect, rect.size.width * 0.2, rect.size.height * 0.2);
  if (CGRectIsEmpty(band)) {
    return nil;
  }

  CGFloat scale = MIN(1, kSamplePixels / MAX(band.size.width, band.size.height));
  size_t width = MAX((size_t)1, (size_t)ceil(band.size.width * scale));
  size_t height = MAX((size_t)1, (size_t)ceil(band.size.height * scale));

  CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef context = CGBitmapContextCreate(
    NULL, width, height, 8, width * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
  CGColorSpaceRelease(space);
  if (!context) {
    return nil;
  }

  CGContextTranslateCTM(context, 0, height);
  CGContextScaleCTM(context, scale, -scale);
  UIGraphicsPushContext(context);
  BOOL didDraw = [window drawViewHierarchyInRect:CGRectOffset(window.bounds, -band.origin.x, -band.origin.y)
                              afterScreenUpdates:NO];
  UIGraphicsPopContext();

  const uint8_t *pixels = (const uint8_t *)CGBitmapContextGetData(context);
  size_t count = width * height;
  NSMutableArray<NSArray<NSNumber *> *> *samples = [NSMutableArray arrayWithCapacity:count];
  for (size_t index = 0; didDraw && pixels && index < count; index++) {
    const uint8_t *pixel = pixels + index * 4;
    CGFloat alpha = pixel[3] / 255.0;
    if (alpha < 0.5) {
      continue;
    }
    CGFloat r = pixel[0] / 255.0 / alpha, g = pixel[1] / 255.0 / alpha, b = pixel[2] / 255.0 / alpha;
    [samples addObject:@[ @(0.2126 * r + 0.7152 * g + 0.0722 * b), @(r), @(g), @(b) ]];
  }
  CGContextRelease(context);

  if (samples.count == 0) {
    return nil;
  }
  [samples sortUsingComparator:^NSComparisonResult(NSArray<NSNumber *> *a, NSArray<NSNumber *> *b) {
    return [a[0] compare:b[0]];
  }];

  NSUInteger first = samples.count / 4;
  NSUInteger last = MAX(first + 1, samples.count - samples.count / 4);
  CGFloat sum[3] = {0, 0, 0};
  for (NSUInteger index = first; index < last; index++) {
    for (NSUInteger channel = 0; channel < 3; channel++) {
      sum[channel] += samples[index][channel + 1].doubleValue;
    }
  }
  CGFloat total = last - first;
  return [UIColor colorWithRed:sum[0] / total green:sum[1] / total blue:sum[2] / total alpha:1];
}

static UIColor *_Nullable MorphletGlassTint(NSArray<UIView *> *chain) {
  if (@available(iOS 26.0, *)) {
    for (UIView *surface in chain) {
      if (![surface isKindOfClass:UIVisualEffectView.class]) {
        continue;
      }
      UIVisualEffect *effect = ((UIVisualEffectView *)surface).effect;
      if ([effect isKindOfClass:UIGlassEffect.class]) {
        UIColor *tint = ((UIGlassEffect *)effect).tintColor;
        if (!tint) {
          return UIColor.clearColor;
        }
        tint = [tint resolvedColorWithTraitCollection:surface.traitCollection];
        return [tint colorWithAlphaComponent:CGColorGetAlpha(tint.CGColor) * MorphletSurfaceOpacity(chain, surface)];
      }
    }
  }
  return nil;
}

UIColor *_Nullable MorphletOpaqueBackgroundColor(UIView *view) {
  NSArray<UIView *> *chain = MorphletSurfaceChain(view);
  if (MorphletGlassTint(chain)) {
    return nil;
  }
  for (UIView *surface in chain.reverseObjectEnumerator) {
    CALayer *fillLayer = MorphletBackgroundLayer(surface);
    if (fillLayer) {
      CGFloat opacity = MorphletSurfaceOpacity(chain, surface);
      return CGColorGetAlpha(fillLayer.backgroundColor) * opacity >= 0.999
               ? [UIColor colorWithCGColor:fillLayer.backgroundColor]
               : nil;
    }
  }
  return nil;
}

UIColor *MorphletVisibleBackgroundColor(UIView *view, UIColor *fallback) {
  NSArray<UIView *> *chain = MorphletSurfaceChain(view);
  UITraitCollection *traits = view.traitCollection;
  CGFloat rgba[4] = {0, 0, 0, 0};
  UIView *below = view;

  UIColor *glassTint = MorphletGlassTint(chain);
  if (glassTint) {
    MorphletComposite(rgba, glassTint, traits);
    below = view.superview;
  } else {
    for (UIView *surface in chain.reverseObjectEnumerator) {
      if (MorphletBackgroundLayer(surface)) {
        below = surface;
        break;
      }
    }
    CALayer *fillLayer = MorphletBackgroundLayer(below);
    CGFloat opacity = MorphletSurfaceOpacity(chain, below);
    if (fillLayer && CGColorGetAlpha(fillLayer.backgroundColor) * opacity >= 0.999) {
      return [UIColor colorWithCGColor:fillLayer.backgroundColor];
    }

    UIColor *rendered = MorphletRenderedColor(view);
    if (rendered) {
      return rendered;
    }
  }

  for (UIView *current = below; current && rgba[3] < 0.999; current = current.superview) {
    CALayer *backgroundLayer = MorphletBackgroundLayer(current);
    if (backgroundLayer) {
      CGFloat opacity = [chain containsObject:current] ? MorphletSurfaceOpacity(chain, current) : 1;
      MorphletCompositeWithOpacity(
        rgba, [UIColor colorWithCGColor:backgroundLayer.backgroundColor], opacity, traits);
    }
  }
  if (rgba[3] < 0.999) {
    MorphletComposite(rgba, fallback, traits);
  }

  CGFloat alpha = MAX(rgba[3], 0.001);
  return [UIColor colorWithRed:rgba[0] / alpha green:rgba[1] / alpha blue:rgba[2] / alpha alpha:1];
}
