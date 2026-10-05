//
//  MorphletViewController.mm
//  Pods
//
//  Created by rit3zh CX on 10/1/26.
//

#import "MorphletViewController.h"
#import "MorphletDisplayCorners.h"
#import "MorphletPassthroughView.h"
#import "MorphletSnapshot.h"
#import "MorphletSpring.h"
#import "MorphletViewController+Gestures.h"
#import "MorphletViewController+Keyboard.h"
#import "MorphletViewController+Private.h"
#import "MorphletViewController+Stack.h"

@implementation MorphletViewController

- (instancetype)init {
  if (self = [super initWithNibName:nil bundle:nil]) {
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    _cornerRadius = 32;
    _cornerSmoothing = 0.6;
    _bottomOffset = 16;
    _backdropOpacity = 0.3;
    _dismissible = YES;
    _draggable = YES;
    _fadesOnDrag = YES;

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self
               selector:@selector(keyboardWillChangeFrame:)
                   name:UIKeyboardWillChangeFrameNotification
                 object:nil];
    [center addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
  }
  return self;
}

- (void)dealloc {
  [NSNotificationCenter.defaultCenter removeObserver:self];
  _morphedOriginView.alpha = _originAlpha;
}

#pragma mark - View

- (void)loadView {
  UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
  view.backgroundColor = UIColor.clearColor;

  _backdropView = [[UIView alloc] initWithFrame:view.bounds];
  _backdropView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  _backdropView.alpha = 0;
  _backdropTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleBackdropTap:)];
  _backdropTap.delegate = self;
  [_backdropView addGestureRecognizer:_backdropTap];

  _cardView = [[MorphletSquircleView alloc] initWithFrame:CGRectZero];
  _cardView.accessibilityViewIsModal = YES;
  _panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
  _panGesture.delegate = self;
  [_cardView addGestureRecognizer:_panGesture];

  _stackView = [[MorphletPassthroughView alloc] initWithFrame:view.bounds];
  _stackView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [_stackView addSubview:_cardView];

  [view addSubview:_backdropView];
  [view addSubview:_stackView];
  self.view = view;

  if (_contentView) {
    [_cardView addSubview:_contentView];
  }
  _coverView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8192, 8192)];
  _coverView.userInteractionEnabled = NO;
  _coverView.alpha = 0;
  [_cardView addSubview:_coverView];
  _cardView.cornerRadius = [self targetCornerRadius];
  _cardView.displayCurve = _fullScreen ? 1 : 0;
  _cardView.cornerSmoothing = _cornerSmoothing;
  [self applyColors];
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];

  CGSize size = self.view.bounds.size;
  if (!CGSizeEqualToSize(size, _lastViewSize)) {
    _lastViewSize = size;
    [self applyCardGeometryAnimated:NO];
  }
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
  [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

  __weak __typeof(self) weakSelf = self;
  [coordinator
    animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
      [weakSelf applyCardGeometryAnimated:YES];
    }
    completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
      [weakSelf.delegate morphletControllerInsetsDidChange];
    }];
}

- (void)viewSafeAreaInsetsDidChange {
  [super viewSafeAreaInsetsDidChange];
  [self.delegate morphletControllerInsetsDidChange];
}

- (void)viewDidDisappear:(BOOL)animated {
  [super viewDidDisappear:animated];

  if (_presentationState == MorphletPresentationStateDismissed || self.presentingViewController) {
    return;
  }

  BOOL wasDismissing = _presentationState == MorphletPresentationStateDismissing;
  _presentationState = MorphletPresentationStateDismissing;
  [self interruptCardAnimation];
  if (!wasDismissing) {
    [self.delegate morphletControllerWillDismiss:NO];
  }
  _presentationState = MorphletPresentationStateDismissed;
  [self resetAfterDismissal];
  [self.delegate morphletControllerDidDismiss];
}

- (BOOL)accessibilityPerformEscape {
  if (!_dismissible) {
    return NO;
  }
  [self dismissWithVelocity:0 interactive:YES animated:YES];
  return YES;
}

#pragma mark - Appearance

+ (UIColor *)defaultCardColor {
  return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
    return traits.userInterfaceStyle == UIUserInterfaceStyleDark
      ? [UIColor colorWithRed:28 / 255.0 green:28 / 255.0 blue:30 / 255.0 alpha:1]
      : UIColor.whiteColor;
  }];
}

- (UIColor *)resolvedCardColor {
  return _cardColor ?: [MorphletViewController defaultCardColor];
}

- (void)applyColors {
  if (!self.isViewLoaded) {
    return;
  }

  if (!_isMorphing) {
    _cardView.backgroundColor = [self resolvedCardColor];
  }
  _backdropView.backgroundColor = _backdropColor ?: UIColor.blackColor;

  if (_presentationState == MorphletPresentationStatePresented && _dragOffset == 0 && !_cardAnimator &&
      _stackDepth == 0) {
    _backdropView.alpha = _backdropOpacity;
  }
}

- (void)setCardColor:(UIColor *)cardColor {
  if ([_cardColor isEqual:cardColor]) {
    return;
  }
  _cardColor = cardColor;
  [self applyColors];
}

- (void)setBackdropColor:(UIColor *)backdropColor {
  if ([_backdropColor isEqual:backdropColor]) {
    return;
  }
  _backdropColor = backdropColor;
  [self applyColors];
}

- (void)setBackdropOpacity:(CGFloat)backdropOpacity {
  if (_backdropOpacity == backdropOpacity) {
    return;
  }
  _backdropOpacity = backdropOpacity;
  [self applyColors];
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
  if (_cornerRadius == cornerRadius) {
    return;
  }
  _cornerRadius = cornerRadius;
  if (self.isViewLoaded && !_isMorphing) {
    _cardView.cornerRadius = [self targetCornerRadius];
    _cardView.displayCurve = _fullScreen ? 1 : 0;
  }
}

- (void)setCornerSmoothing:(CGFloat)cornerSmoothing {
  if (_cornerSmoothing == cornerSmoothing) {
    return;
  }
  _cornerSmoothing = cornerSmoothing;
  if (self.isViewLoaded) {
    _cardView.cornerSmoothing = cornerSmoothing;
  }
}

- (void)setBottomOffset:(CGFloat)bottomOffset {
  if (_bottomOffset == bottomOffset) {
    return;
  }
  _bottomOffset = bottomOffset;
  [self applyCardGeometryAnimated:NO];
}

- (void)setFullScreen:(BOOL)fullScreen {
  _fullScreen = fullScreen;
}

- (CGFloat)targetCornerRadius {
  if (!_fullScreen) {
    return _cornerRadius;
  }
  return [MorphletDisplayCorners radiusForWindow:self.viewIfLoaded.window ?: _referenceWindow];
}

#pragma mark - Springs

- (MorphletSpringConfig *)presentSpring {
  return _presentSpring ?: [MorphletSpringConfig springWithResponse:0.4 dampingFraction:0.75];
}

- (MorphletSpringConfig *)dismissSpring {
  return _dismissSpring ?: [MorphletSpringConfig springWithResponse:0.35 dampingFraction:1];
}

- (MorphletSpringConfig *)morphSpring {
  return _morphSpring ?: [MorphletSpringConfig springWithResponse:0.5 dampingFraction:0.86];
}

- (MorphletSpringConfig *)snapSpring {
  return _snapSpring ?: [MorphletSpringConfig springWithResponse:0.3 dampingFraction:0.7];
}

#pragma mark - Content

- (void)setContentView:(UIView *)contentView {
  if (_contentView == contentView) {
    return;
  }

  if (_contentView.superview == _cardView) {
    [_contentView removeFromSuperview];
  }

  _contentView = contentView;

  if (contentView && self.isViewLoaded) {
    [_cardView insertSubview:contentView atIndex:0];
    [self applyCardGeometryAnimated:NO];
  }
}

- (void)contentSizeDidChangeAnimated:(BOOL)animated {
  [self applyCardGeometryAnimated:animated];
}

- (void)applyCardGeometryAnimated:(BOOL)animated {
  if (!self.isViewLoaded || _isMorphing || _presentationState == MorphletPresentationStateDismissing) {
    return;
  }

  [self layoutCard];
  _cardView.cornerRadius = [self targetCornerRadius];
  _cardView.displayCurve = _fullScreen ? 1 : 0;
}

- (CGRect)targetCardFrame {
  CGRect bounds = self.view.bounds;
  CGSize size = _contentView ? _contentView.bounds.size : CGSizeZero;
  if (size.width <= 0) {
    size.width = MAX(0, bounds.size.width - 32);
  }

  CGFloat inset = _fullScreen ? 0 : _bottomOffset;
  CGFloat bottom = CGRectGetMaxY(bounds) - inset - _keyboardHeight;
  return CGRectMake(CGRectGetMidX(bounds) - size.width / 2, bottom - size.height, size.width, size.height);
}

- (void)layoutCard {
  [self setCardFrame:[self targetCardFrame]];
}

- (void)setCardFrame:(CGRect)frame {
  _cardView.bounds = CGRectMake(0, 0, frame.size.width, frame.size.height);
  _cardView.center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
}

- (void)layoutMorphForCardSize:(CGSize)cardSize {
  CGSize contentSize = _contentView.bounds.size;
  _contentView.transform =
    CGAffineTransformMakeTranslation((cardSize.width - contentSize.width) / 2, cardSize.height - contentSize.height);

  CGFloat snapshotHeight = CGRectGetHeight(_originSnapshot.frame);
  _originSnapshot.center = CGPointMake(cardSize.width / 2, cardSize.height - snapshotHeight / 2);
}

- (void)fitOriginSnapshotToSize:(CGSize)size {
  CGSize drawn = _originSnapshot.bounds.size;
  if (drawn.width <= 0 || drawn.height <= 0) {
    return;
  }
  _originSnapshot.transform = CGAffineTransformMakeScale(size.width / drawn.width, size.height / drawn.height);
}

- (CGFloat)offscreenOffset {
  CGFloat top = _cardView.center.y - _cardView.bounds.size.height / 2;
  return MAX(0, CGRectGetMaxY(self.view.bounds) - top) + 8;
}

#pragma mark - Presentation

- (nullable UIView *)morphableOriginView {
  UIView *origin = _originView;
  if (!origin || !origin.window || CGRectIsEmpty(origin.bounds)) {
    return nil;
  }
  return origin;
}

- (CGRect)frameOfOriginView:(UIView *)origin {
  return [self cardRectFromWindowRect:[origin convertRect:origin.bounds toView:nil]];
}

- (CGRect)restingFrameOfOriginView:(UIView *)origin {
  CGSize size = origin.bounds.size;
  CGPoint center = origin.center;
  CGRect inParent = CGRectMake(center.x - size.width / 2, center.y - size.height / 2, size.width, size.height);
  UIView *parent = origin.superview;
  return [self cardRectFromWindowRect:parent ? [parent convertRect:inParent toView:nil] : inParent];
}

- (CGRect)cardRectFromWindowRect:(CGRect)rect {
  return self.view.window ? [_stackView convertRect:rect fromView:nil] : rect;
}

- (CGFloat)cornerRadiusOfOriginView:(UIView *)origin inFrame:(CGRect)frame {
  CGFloat width = origin.bounds.size.width;
  CGFloat scale = width > 0 ? frame.size.width / width : 1;
  CGFloat radius = MorphletCornerRadius(origin) * scale;
  return MIN(radius, MIN(frame.size.width, frame.size.height) / 2);
}

- (void)presentFromViewController:(UIViewController *)presenter {
  if (_presentationState != MorphletPresentationStateDismissed) {
    return;
  }
  _presentationState = MorphletPresentationStatePresenting;

  [self loadViewIfNeeded];
  _referenceWindow = presenter.view.window;
  UIView *host = presenter.view.window ?: presenter.view;
  [host endEditing:YES];
  self.view.frame = host.bounds;
  self.view.userInteractionEnabled = YES;
  [self.view layoutIfNeeded];

  _dragOffset = 0;
  _keyboardHeight = 0;
  _backdropView.alpha = 0;
  _cardView.alpha = 1;
  _cardView.transform = CGAffineTransformIdentity;
  _cardView.cornerRadius = [self targetCornerRadius];
  _cardView.displayCurve = _fullScreen ? 1 : 0;
  [self layoutCard];

  UIView *origin = [self morphableOriginView];
  if (origin) {
    [self prepareMorphFromOrigin:origin];
  } else {
    _cardView.transform = CGAffineTransformMakeTranslation(0, [self offscreenOffset]);
  }

  [self.delegate morphletControllerWillPresent];

  if (_stacked) {
    [self pushPresenterStack:presenter spring:origin ? self.morphSpring : self.presentSpring];
  }

  __weak __typeof(self) weakSelf = self;
  [presenter presentViewController:self
                          animated:NO
                        completion:^{
                          [weakSelf animateIn];
                        }];
}

- (void)prepareMorphFromOrigin:(UIView *)origin {
  _isMorphing = YES;
  _morphedOriginView = origin;
  _originAlpha = origin.alpha > 0.01 ? origin.alpha : 1;

  CGRect frame = [self frameOfOriginView:origin];
  _originColor = MorphletVisibleBackgroundColor(origin, [self resolvedCardColor]);
  _originRadius = [self cornerRadiusOfOriginView:origin inFrame:frame];

  [_originSnapshot removeFromSuperview];
  _originSnapshot = MorphletContentSnapshotImageView(origin);
  [self fitOriginSnapshotToSize:frame.size];
  [_cardView addSubview:_originSnapshot];

  [self setCardFrame:frame];
  [self layoutMorphForCardSize:frame.size];
  _cardView.cornerRadius = _originRadius;
  _cardView.displayCurve = 0;
  _cardView.backgroundColor = [self resolvedCardColor];
  _coverView.backgroundColor = _originColor;
  _coverView.alpha = 1;

  origin.alpha = 0;
}

- (void)animateIn {
  if (_presentationState != MorphletPresentationStatePresenting) {
    return;
  }

  if (_isMorphing) {
    [self morphIn];
    return;
  }

  [self layoutCard];
  _cardView.transform = CGAffineTransformMakeTranslation(0, [self offscreenOffset]);

  __weak __typeof(self) weakSelf = self;
  _cardAnimator = [MorphletSpring animateWithSpring:self.presentSpring
    velocity:0
    animations:^{
      __typeof(self) strongSelf = weakSelf;
      if (!strongSelf) {
        return;
      }
      strongSelf->_cardView.transform = CGAffineTransformIdentity;
      strongSelf->_backdropView.alpha = strongSelf->_backdropOpacity;
    }
    completion:^(BOOL finished) {
      [weakSelf finishPresentingIfNeeded];
    }];
}

- (void)morphIn {
  UIView *snapshot = _originSnapshot;
  UIView *cover = _coverView;
  UIColor *cardColor = [self resolvedCardColor];

  __weak __typeof(self) weakSelf = self;
  _cardAnimator = [MorphletSpring animateWithSpring:self.morphSpring
    velocity:0
    animations:^{
      __typeof(self) strongSelf = weakSelf;
      if (!strongSelf) {
        return;
      }
      [strongSelf layoutCard];
      [strongSelf layoutMorphForCardSize:strongSelf->_cardView.bounds.size];
      strongSelf->_backdropView.alpha = strongSelf->_backdropOpacity;
    }
    completion:^(BOOL finished) {
      __typeof(self) strongSelf = weakSelf;
      if (!strongSelf || strongSelf->_presentationState != MorphletPresentationStatePresenting) {
        return;
      }
      strongSelf->_isMorphing = NO;
      [strongSelf->_originSnapshot removeFromSuperview];
      [strongSelf settleAfterMorphIn];
      [strongSelf finishPresentingIfNeeded];
    }];
  _cardView.cornerRadius = [self targetCornerRadius];
  _cardView.displayCurve = _fullScreen ? 1 : 0;

  [MorphletSpring animateWithSpring:[MorphletSpringConfig springWithResponse:0.18 dampingFraction:1]
                           velocity:0
                         animations:^{
                           snapshot.alpha = 0;
                         }
                         completion:nil];

  UIViewPropertyAnimator *reveal =
    [MorphletSpring animatorWithSpring:[MorphletSpringConfig springWithResponse:0.32 dampingFraction:1] velocity:0];
  [reveal addAnimations:^{
    cover.backgroundColor = cardColor;
    cover.alpha = 0;
  }];
  [reveal startAnimationAfterDelay:0.04];
}

- (void)settleAfterMorphIn {
  CGRect target = [self targetCardFrame];
  CGSize size = _cardView.bounds.size;
  CGPoint center = _cardView.center;
  BOOL isSettled = CGAffineTransformIsIdentity(_contentView.transform) && CGSizeEqualToSize(size, target.size) &&
                   CGPointEqualToPoint(center, CGPointMake(CGRectGetMidX(target), CGRectGetMidY(target)));
  if (isSettled) {
    [self applyCardGeometryAnimated:NO];
    return;
  }

  __weak __typeof(self) weakSelf = self;
  [MorphletSpring animateWithSpring:self.morphSpring.withoutBounce
                           velocity:0
                         animations:^{
                           __typeof(self) strongSelf = weakSelf;
                           if (!strongSelf) {
                             return;
                           }
                           strongSelf->_contentView.transform = CGAffineTransformIdentity;
                           [strongSelf applyCardGeometryAnimated:YES];
                         }
                         completion:nil];
}

- (void)finishPresentingIfNeeded {
  if (_presentationState != MorphletPresentationStatePresenting) {
    return;
  }
  _presentationState = MorphletPresentationStatePresented;
  _cardAnimator = nil;
  [self.delegate morphletControllerDidPresent];
}

- (void)dismissAnimated:(BOOL)animated {
  [self dismissWithVelocity:0 interactive:NO animated:animated];
}

- (void)dismissWithVelocity:(CGFloat)velocity interactive:(BOOL)interactive animated:(BOOL)animated {
  if (_presentationState == MorphletPresentationStateDismissed ||
      _presentationState == MorphletPresentationStateDismissing) {
    return;
  }

  _presentationState = MorphletPresentationStateDismissing;
  [self interruptCardAnimation];
  _isMorphing = NO;
  _trackingScrollView = nil;

  [self.delegate morphletControllerWillDismiss:interactive];
  [self.view endEditing:YES];
  self.view.userInteractionEnabled = NO;

  UIView *origin = [self morphableOriginView];
  BOOL foldsIntoOrigin = animated && origin && _originSnapshot && fabs(_cardView.transform.ty) < 1;
  [self restorePresenterStackWithSpring:foldsIntoOrigin ? self.morphSpring.withoutBounce : self.dismissSpring];

  if (!animated) {
    [self finishDismissing];
    return;
  }

  if (foldsIntoOrigin) {
    [self morphOutToOrigin:origin];
    return;
  }

  CGFloat current = _cardView.transform.ty;
  CGFloat target = [self offscreenOffset];
  CGFloat distance = MAX(1, target - current);
  UIView *hiddenOrigin = _morphedOriginView;
  CGFloat originAlpha = _originAlpha;

  __weak __typeof(self) weakSelf = self;
  _cardAnimator = [MorphletSpring animateWithSpring:self.dismissSpring
    velocity:velocity / distance
    animations:^{
      __typeof(self) strongSelf = weakSelf;
      if (!strongSelf) {
        return;
      }
      strongSelf->_cardView.transform = CGAffineTransformMakeTranslation(0, target);
      strongSelf->_backdropView.alpha = 0;
      hiddenOrigin.alpha = originAlpha;
    }
    completion:^(BOOL finished) {
      [weakSelf finishDismissing];
    }];
}

- (void)morphOutToOrigin:(UIView *)origin {
  _isMorphing = YES;

  CGRect frame = [self restingFrameOfOriginView:origin];
  _originRadius = [self cornerRadiusOfOriginView:origin inFrame:frame];
  // Re-capture the trigger: its contents may have changed while the tray was open. Then hide it
  // again, since a React re-render while open can have restored its opacity.
  origin.alpha = _originAlpha;
  UIImageView *fresh = MorphletContentSnapshotImageView(origin);
  origin.alpha = 0;
  if (fresh) {
    [_originSnapshot removeFromSuperview];
    _originSnapshot = fresh;
  }
  UIView *snapshot = _originSnapshot;
  UIView *cover = _coverView;
  UIColor *originColor = _originColor;
  snapshot.alpha = 0;
  [self fitOriginSnapshotToSize:frame.size];
  [_cardView addSubview:snapshot];
  [self layoutMorphForCardSize:_cardView.bounds.size];
  cover.backgroundColor = [self resolvedCardColor];

  __weak __typeof(self) weakSelf = self;
  _cardAnimator = [MorphletSpring animateWithSpring:self.morphSpring.withoutBounce
    velocity:0
    animations:^{
      __typeof(self) strongSelf = weakSelf;
      if (!strongSelf) {
        return;
      }
      strongSelf->_cardView.transform = CGAffineTransformIdentity;
      strongSelf->_cardView.alpha = 1;
      [strongSelf setCardFrame:frame];
      [strongSelf layoutMorphForCardSize:frame.size];
      strongSelf->_backdropView.alpha = 0;
    }
    completion:^(BOOL finished) {
      [weakSelf handOffToOrigin:origin];
    }];
  _cardView.cornerRadius = _originRadius;
  _cardView.displayCurve = 0;

  [MorphletSpring animateWithSpring:[MorphletSpringConfig springWithResponse:0.22 dampingFraction:1]
                           velocity:0
                         animations:^{
                           cover.alpha = 1;
                           cover.backgroundColor = originColor;
                         }
                         completion:nil];

  UIViewPropertyAnimator *reveal =
    [MorphletSpring animatorWithSpring:[MorphletSpringConfig springWithResponse:0.25 dampingFraction:1] velocity:0];
  [reveal addAnimations:^{
    snapshot.alpha = 1;
  }];
  [reveal startAnimationAfterDelay:0.1];
}

- (void)handOffToOrigin:(UIView *)origin {
  if (_presentationState != MorphletPresentationStateDismissing) {
    return;
  }
  origin.alpha = _originAlpha;

  UIView *card = _cardView;
  __weak __typeof(self) weakSelf = self;
  _cardAnimator = [MorphletSpring animateWithSpring:[MorphletSpringConfig springWithResponse:0.2 dampingFraction:1]
    velocity:0
    animations:^{
      card.alpha = 0;
    }
    completion:^(BOOL finished) {
      [weakSelf finishDismissing];
    }];
}

- (void)finishDismissing {
  if (_presentationState != MorphletPresentationStateDismissing) {
    return;
  }
  _cardAnimator = nil;

  __weak __typeof(self) weakSelf = self;
  void (^done)(void) = ^{
    __typeof(self) strongSelf = weakSelf;
    if (!strongSelf || strongSelf->_presentationState != MorphletPresentationStateDismissing) {
      return;
    }
    strongSelf->_presentationState = MorphletPresentationStateDismissed;
    [strongSelf resetAfterDismissal];
    [strongSelf.delegate morphletControllerDidDismiss];
  };

  UIViewController *presenter = self.presentingViewController;
  if (presenter) {
    [presenter dismissViewControllerAnimated:NO completion:done];
  } else {
    done();
  }
}

- (void)resetAfterDismissal {
  _isMorphing = NO;
  _dragOffset = 0;
  _keyboardHeight = 0;
  _morphedOriginView.alpha = _originAlpha;
  _morphedOriginView = nil;
  [_originSnapshot removeFromSuperview];
  _originSnapshot = nil;
  _originColor = nil;

  _cardView.transform = CGAffineTransformIdentity;
  _cardView.alpha = 1;
  _cardView.cornerRadius = [self targetCornerRadius];
  _cardView.displayCurve = _fullScreen ? 1 : 0;
  _coverView.alpha = 0;
  _contentView.transform = CGAffineTransformIdentity;
  _didPushStack = NO;
  [self applyColors];
}

- (void)interruptCardAnimation {
  UIViewPropertyAnimator *animator = _cardAnimator;
  _cardAnimator = nil;
  if (animator && animator.state == UIViewAnimatingStateActive) {
    [animator stopAnimation:NO];
    [animator finishAnimationAtPosition:UIViewAnimatingPositionCurrent];
  }
}

@end
