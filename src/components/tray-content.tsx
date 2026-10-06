import * as React from 'react';
import { useRef, useState } from 'react';
import {
  StyleSheet,
  useWindowDimensions,
  type NativeSyntheticEvent,
  type ViewStyle,
} from 'react-native';

import {
  COMPONENT_NAMES,
  FALLBACK_TOP_INSET,
  TRAY_DEFAULTS,
} from '../constants';
import { useTrayContext } from '../hooks';
import type { ITrayContentProps, ITrayInsets } from '../interfaces';
import {
  paddingOf,
  stopResponderNegotiation,
  stopTouchPropagation,
} from '../utils';
import {
  MorphletContainerView,
  MorphletHostView,
  type TInsetsChangeEvent,
} from '../views';

const TrayContent: React.FC<ITrayContentProps> = ({
  children,
  style,
  backgroundColor,
  cornerRadius,
  cornerSmoothing = TRAY_DEFAULTS.CORNER_SMOOTHING,
  horizontalInset = TRAY_DEFAULTS.HORIZONTAL_INSET,
  bottomOffset = TRAY_DEFAULTS.BOTTOM_OFFSET,
  topInset = TRAY_DEFAULTS.TOP_INSET,
  maxWidth = TRAY_DEFAULTS.MAX_WIDTH,
  backdropColor,
  backdropOpacity = TRAY_DEFAULTS.BACKDROP_OPACITY,
  dismissible = true,
  draggable = true,
  fadeOnDrag = true,
  fullScreen: fullScreenProp,
  stack = false,
  onDidPresent,
  onDidDismiss,
  ...rest
}: ITrayContentProps): React.JSX.Element | null => {
  const context = useTrayContext(COMPONENT_NAMES.CONTENT);
  const { open, setOpen, onDidClose, duration, originTag, springs } = context;
  const fullScreen = fullScreenProp ?? context.fullScreen;

  const windowDimensions = useWindowDimensions();
  const [insets, setInsets] = useState<ITrayInsets>({
    top: 0,
    bottom: 0,
    keyboard: 0,
    width: 0,
    height: 0,
  });
  const window =
    insets.width > 0 && insets.height > 0 ? insets : windowDimensions;

  const [isRendered, setIsRendered] = useState(open);
  if (open && !isRendered) {
    setIsRendered(true);
  }

  const openRef = useRef(open);
  openRef.current = open;

  const {
    backgroundColor: styleBackgroundColor,
    borderRadius: styleBorderRadius,
    ...containerStyle
  } = StyleSheet.flatten(style) ?? {};

  const safeTop = insets.top > 0 ? insets.top : FALLBACK_TOP_INSET;
  const sizeStyle: ViewStyle = fullScreen
    ? {
        width: window.width,
        height: Math.max(0, window.height - insets.keyboard),
        paddingTop: safeTop + paddingOf(containerStyle, 'Top'),
        paddingBottom:
          (insets.keyboard > 0 ? 0 : insets.bottom) +
          paddingOf(containerStyle, 'Bottom'),
      }
    : {
        width: Math.max(
          0,
          Math.min(window.width - horizontalInset * 2, maxWidth)
        ),
        maxHeight: Math.max(
          0,
          window.height - safeTop - topInset - bottomOffset - insets.keyboard
        ),
      };

  return (
    <MorphletHostView
      style={styles.host}
      open={open}
      cardColor={backgroundColor ?? styleBackgroundColor}
      cornerRadius={
        cornerRadius ??
        (typeof styleBorderRadius === 'number'
          ? styleBorderRadius
          : TRAY_DEFAULTS.CORNER_RADIUS)
      }
      cornerSmoothing={cornerSmoothing}
      bottomOffset={bottomOffset}
      backdropColor={backdropColor}
      backdropOpacity={backdropOpacity}
      dismissible={dismissible}
      draggable={draggable}
      fadeOnDrag={fadeOnDrag}
      fullScreen={fullScreen}
      stack={stack}
      originTag={originTag}
      duration={duration}
      presentSpring={springs.present}
      dismissSpring={springs.dismiss}
      morphSpring={springs.morph}
      layoutSpring={springs.layout}
      snapSpring={springs.drag}
      onInsetsChange={(event: NativeSyntheticEvent<TInsetsChangeEvent>) => {
        const { top, bottom, keyboard, width, height } = event.nativeEvent;
        setInsets({ top, bottom, keyboard, width, height });
      }}
      onWillDismiss={() => {
        if (openRef.current) {
          setOpen(false);
        }
      }}
      onDidPresent={onDidPresent}
      onDidDismiss={() => {
        if (!openRef.current) {
          setIsRendered(false);
          onDidClose();
        }
        onDidDismiss?.();
      }}
    >
      {isRendered ? (
        <MorphletContainerView
          collapsable={false}
          accessibilityViewIsModal
          onTouchStart={stopTouchPropagation}
          onTouchMove={stopTouchPropagation}
          onTouchEnd={stopTouchPropagation}
          onTouchCancel={stopTouchPropagation}
          onStartShouldSetResponder={stopResponderNegotiation}
          onMoveShouldSetResponder={stopResponderNegotiation}
          {...rest}
          style={[styles.container, containerStyle, sizeStyle]}
        >
          {children}
        </MorphletContainerView>
      ) : null}
    </MorphletHostView>
  );
};

const styles = StyleSheet.create({
  host: {
    position: 'absolute',
    width: 0,
    height: 0,
  },
  container: {
    position: 'absolute',
    top: 0,
    left: 0,
  },
});

TrayContent.displayName = COMPONENT_NAMES.CONTENT;

export { TrayContent };
