//
//  MorphletHostView.mm
//  Pods
//
//  Created by rit3zh CX on 10/1/26.
//

#import "MorphletHostView.h"
#import "MorphletContainerView.h"
#import "MorphletViewController.h"
#import "MorphletViewController+Keyboard.h"

#import <react/renderer/components/MorphletSpec/ComponentDescriptors.h>
#import <react/renderer/components/MorphletSpec/EventEmitters.h>
#import <react/renderer/components/MorphletSpec/Props.h>
#import <react/renderer/components/MorphletSpec/RCTComponentViewHelpers.h>

#import <React/RCTConversions.h>
#import <React/RCTFabricComponentsPlugins.h>
#import <React/RCTSurfaceTouchHandler.h>

using namespace facebook::react;

template <typename SpringProps>
static MorphletSpringConfig *_Nullable MorphletSpringFromProps(const SpringProps &spring) {
  if (spring.stiffness <= 0) {
    return nil;
  }
  return [MorphletSpringConfig springWithMass:spring.mass > 0 ? spring.mass : 1
                                    stiffness:spring.stiffness
                                      damping:spring.damping];
}

@interface MorphletHostView () <MorphletViewControllerDelegate, MorphletContainerViewDelegate>
@end

@implementation MorphletHostView {
  MorphletViewController *_controller;
  MorphletContainerView *_containerView;
  RCTSurfaceTouchHandler *_touchHandler;
  BOOL _open;
  BOOL _wantsPresent;
  BOOL _isPresentScheduled;
  BOOL _isDismissScheduled;
  CGFloat _duration;
  MorphletSpringConfig *_layoutSpring;
  NSInteger _originTag;
  UIEdgeInsets _reportedInsets;
  CGFloat _reportedKeyboard;
  CGSize _reportedSize;
  BOOL _hasReportedInsets;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider {
  return concreteComponentDescriptorProvider<MorphletHostViewComponentDescriptor>();
}

+ (BOOL)shouldBeRecycled {
  return NO;
}

- (instancetype)initWithFrame:(CGRect)frame {
  if (self = [super initWithFrame:frame]) {
    static const auto defaultProps = std::make_shared<const MorphletHostViewProps>();
    _props = defaultProps;

    self.hidden = YES;
    _duration = 0.25;
    _controller = [[MorphletViewController alloc] init];
    _controller.delegate = self;
    _touchHandler = [[RCTSurfaceTouchHandler alloc] init];
  }
  return self;
}

- (void)dealloc {
  _controller.delegate = nil;
  if (_controller.presentationState != MorphletPresentationStateDismissed) {
    [_controller dismissAnimated:NO];
  }
}

- (void)didMoveToWindow {
  [super didMoveToWindow];

  if (self.window) {
    [self emitInsetsIfNeeded];
    if (_wantsPresent) {
      [self schedulePresent];
    }
  }
}

#pragma mark - Props

- (void)updateProps:(const Props::Shared &)props oldProps:(const Props::Shared &)oldProps {
  const auto &newProps = *std::static_pointer_cast<const MorphletHostViewProps>(props);

  _controller.cardColor = RCTUIColorFromSharedColor(newProps.cardColor);
  _controller.backdropColor = RCTUIColorFromSharedColor(newProps.backdropColor);
  _controller.cornerRadius = newProps.cornerRadius;
  _controller.cornerSmoothing = newProps.cornerSmoothing;
  _controller.bottomOffset = newProps.bottomOffset;
  _controller.backdropOpacity = newProps.backdropOpacity;
  _controller.dismissible = newProps.dismissible;
  _controller.draggable = newProps.draggable;
  _controller.fadesOnDrag = newProps.fadeOnDrag;
  _duration = newProps.duration;
  _controller.presentSpring = MorphletSpringFromProps(newProps.presentSpring);
  _controller.dismissSpring = MorphletSpringFromProps(newProps.dismissSpring);
  _controller.morphSpring = MorphletSpringFromProps(newProps.morphSpring);
  _controller.snapSpring = MorphletSpringFromProps(newProps.snapSpring);
  _layoutSpring = MorphletSpringFromProps(newProps.layoutSpring);
  _controller.fullScreen = newProps.fullScreen;
  _controller.stacked = newProps.stack;
  _originTag = newProps.originTag;

  [super updateProps:props oldProps:oldProps];
  self.hidden = YES;

  if (newProps.open != _open) {
    _open = newProps.open;
    if (_open) {
      _wantsPresent = YES;
      [self schedulePresent];
    } else {
      _wantsPresent = NO;
      [self scheduleDismiss];
    }
  }
}

#pragma mark - Children

- (void)mountChildComponentView:(UIView<RCTComponentViewProtocol> *)childComponentView index:(NSInteger)index {
  if (![childComponentView isKindOfClass:MorphletContainerView.class]) {
    [super mountChildComponentView:childComponentView index:index];
    return;
  }

  _containerView = (MorphletContainerView *)childComponentView;
  _containerView.delegate = self;
  [_touchHandler attachToView:_containerView];
  _controller.contentView = _containerView;

  if (_wantsPresent) {
    [self schedulePresent];
  }
}

- (void)unmountChildComponentView:(UIView<RCTComponentViewProtocol> *)childComponentView index:(NSInteger)index {
  if (childComponentView != _containerView) {
    [super unmountChildComponentView:childComponentView index:index];
    return;
  }

  if (_controller.presentationState != MorphletPresentationStateDismissed) {
    [_controller dismissAnimated:NO];
  }

  [_touchHandler detachFromView:_containerView];
  _containerView.delegate = nil;
  _controller.contentView = nil;
  [_containerView removeFromSuperview];
  _containerView = nil;
}

#pragma mark - Presentation

- (void)schedulePresent {
  if (_isPresentScheduled) {
    return;
  }
  _isPresentScheduled = YES;

  __weak __typeof(self) weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    __typeof(self) strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }
    strongSelf->_isPresentScheduled = NO;
    [strongSelf presentIfNeeded];
  });
}

- (void)scheduleDismiss {
  if (_isDismissScheduled) {
    return;
  }
  _isDismissScheduled = YES;

  __weak __typeof(self) weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    __typeof(self) strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }
    strongSelf->_isDismissScheduled = NO;
    if (strongSelf->_open) {
      return;
    }
    strongSelf->_controller.originView = [strongSelf viewForReactTag:strongSelf->_originTag];
    [strongSelf->_controller dismissAnimated:YES];
  });
}

- (void)presentIfNeeded {
  if (!_wantsPresent || !_open || !_containerView || !self.window ||
      _controller.presentationState != MorphletPresentationStateDismissed) {
    return;
  }

  UIViewController *presenter = [self findPresenter];
  if (!presenter) {
    return;
  }

  _wantsPresent = NO;
  [self emitInsetsIfNeeded];
  _controller.originView = [self viewForReactTag:_originTag];
  [_controller presentFromViewController:presenter];
}

- (nullable UIView *)viewForReactTag:(NSInteger)tag {
  if (tag <= 0 || !self.window) {
    return nil;
  }

  UIView *root = self;
  while ([root.superview isKindOfClass:RCTViewComponentView.class]) {
    root = root.superview;
  }
  UIView *view = [root viewWithTag:tag];
  return view.window ? view : nil;
}

- (nullable UIViewController *)findPresenter {
  UIViewController *controller = self.window.rootViewController;
  while (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed) {
    controller = controller.presentedViewController;
  }
  return controller == _controller ? nil : controller;
}

#pragma mark - Events

- (std::shared_ptr<const MorphletHostViewEventEmitter>)emitter {
  return std::static_pointer_cast<const MorphletHostViewEventEmitter>(_eventEmitter);
}

- (void)emitInsetsIfNeeded {
  UIWindow *window = self.window ?: _controller.viewIfLoaded.window;
  if (!window) {
    return;
  }

  UIEdgeInsets insets = window.safeAreaInsets;
  CGFloat keyboard = _controller.keyboardHeight;
  CGSize size = window.bounds.size;
  if (_hasReportedInsets && UIEdgeInsetsEqualToEdgeInsets(insets, _reportedInsets) && keyboard == _reportedKeyboard &&
      CGSizeEqualToSize(size, _reportedSize)) {
    return;
  }

  auto emitter = [self emitter];
  if (!emitter) {
    return;
  }

  _hasReportedInsets = YES;
  _reportedInsets = insets;
  _reportedKeyboard = keyboard;
  _reportedSize = size;
  emitter->onInsetsChange(
    {.top = insets.top, .bottom = insets.bottom, .keyboard = keyboard, .width = size.width, .height = size.height});
}

#pragma mark - MorphletViewControllerDelegate

- (void)morphletControllerWillPresent {
  if (auto emitter = [self emitter]) {
    emitter->onWillPresent({});
  }
}

- (void)morphletControllerDidPresent {
  if (auto emitter = [self emitter]) {
    emitter->onDidPresent({});
  }
}

- (void)morphletControllerWillDismiss:(BOOL)interactive {
  if (auto emitter = [self emitter]) {
    emitter->onWillDismiss({});
  }
}

- (void)morphletControllerDidDismiss {
  if (auto emitter = [self emitter]) {
    emitter->onDidDismiss({});
  }

  if (_wantsPresent && _open) {
    [self schedulePresent];
  }
}

- (void)morphletControllerInsetsDidChange {
  [self emitInsetsIfNeeded];
}

#pragma mark - MorphletContainerViewDelegate

- (BOOL)containerViewShouldAnimateLayout {
  MorphletPresentationState state = _controller.presentationState;
  return state == MorphletPresentationStatePresenting || state == MorphletPresentationStatePresented;
}

- (MorphletSpringConfig *)containerViewLayoutSpring {
  return _layoutSpring ?: [MorphletSpringConfig springWithResponse:_duration * 1.2 dampingFraction:0.8];
}

- (void)containerViewLayoutDidChangeAnimated:(BOOL)animated {
  [_controller contentSizeDidChangeAnimated:animated];

  MorphletViewController *controller = _controller;
  dispatch_async(dispatch_get_main_queue(), ^{
    [controller revealFirstResponder];
  });
}

@end

Class<RCTComponentViewProtocol> MorphletHostViewCls(void) {
  return MorphletHostView.class;
}
