import * as React from 'react';
import { useCallback, useMemo, useRef, useState } from 'react';

import { COMPONENT_NAMES, NO_ORIGIN_TAG, TRAY_DEFAULTS } from '../constants';
import { TrayContext } from '../context';
import { useControllableState } from '../hooks';
import type { INavigation, ITrayContext, ITrayRootProps } from '../interfaces';
import { initialNavigation, navigate, resolveAnimation } from '../utils';

const TrayRoot: React.FC<ITrayRootProps> = ({
  children,
  open: openProp,
  defaultOpen = false,
  onOpenChange,
  view: viewProp,
  defaultView,
  onViewChange,
  resetOnClose = true,
  transition = TRAY_DEFAULTS.TRANSITION,
  duration = TRAY_DEFAULTS.DURATION,
  animation,
}: ITrayRootProps): React.JSX.Element => {
  const [open, setOpen] = useControllableState(
    openProp,
    defaultOpen,
    onOpenChange
  );

  const [registeredView, setRegisteredView] = useState<string>();
  const initialView = defaultView ?? viewProp ?? registeredView;

  const [navigation, setNavigation] = useState<INavigation>(() =>
    initialNavigation(initialView)
  );

  const top = navigation.history[navigation.history.length - 1];
  if (viewProp !== undefined && viewProp !== top) {
    setNavigation(navigate(navigation, viewProp));
  } else if (top === undefined && initialView !== undefined) {
    setNavigation(initialNavigation(initialView));
  }

  const view = viewProp ?? top;
  const isViewControlled = viewProp !== undefined;

  const onViewChangeRef = useRef(onViewChange);
  onViewChangeRef.current = onViewChange;

  const setView = useCallback((next: string) => {
    setNavigation((current) => navigate(current, next));
    onViewChangeRef.current?.(next);
  }, []);

  const goBack = useCallback(() => {
    const previous = navigation.history[navigation.history.length - 2];
    if (previous !== undefined) {
      setView(previous);
    }
  }, [navigation, setView]);

  const registerDefaultView = useCallback((name: string) => {
    setRegisteredView((current) => current ?? name);
  }, []);

  const [originTag, setOriginTag] = useState<number>(NO_ORIGIN_TAG);
  // Native code hides a morph trigger while the tray is open, but React Native
  // re-applies the opacity prop when the trigger re-lays out. Mirror the hiding
  // in JS once presented: earlier, it would race the native snapshot on open.
  const [originHidden, setOriginHidden] = useState(false);
  const onDidPresent = useCallback(() => setOriginHidden(true), []);

  const [fullScreenRequested, setFullScreen] = useState(false);
  const [fullScreenViews, setFullScreenViews] = useState<string[]>([]);
  const registerFullScreenViews = useCallback((names: string[]) => {
    setFullScreenViews((current) =>
      current.join('\n') === names.join('\n') ? current : names
    );
  }, []);
  const fullScreen =
    fullScreenRequested ||
    (view !== undefined && fullScreenViews.includes(view));

  const onDidClose = useCallback(() => {
    setOriginTag(NO_ORIGIN_TAG);
    setOriginHidden(false);
    setFullScreen(false);
    if (!resetOnClose || initialView === undefined) {
      return;
    }
    setNavigation(initialNavigation(initialView));
    if (isViewControlled && viewProp !== initialView) {
      onViewChangeRef.current?.(initialView);
    }
  }, [resetOnClose, initialView, isViewControlled, viewProp]);

  const close = useCallback(() => setOpen(false), [setOpen]);

  const animationKey = JSON.stringify(animation ?? null);
  const springs = useMemo(
    () => resolveAnimation(JSON.parse(animationKey) ?? undefined, duration),
    [animationKey, duration]
  );

  const value = useMemo<ITrayContext>(
    () => ({
      open,
      setOpen,
      close,
      view,
      setView,
      goBack,
      canGoBack: navigation.history.length > 1,
      direction: navigation.direction,
      fullScreen,
      setFullScreen,
      transition,
      duration,
      springs,
      registerDefaultView,
      registerFullScreenViews,
      onDidPresent,
      onDidClose,
      originTag,
      originHidden,
      setOriginTag,
    }),
    [
      open,
      setOpen,
      close,
      view,
      setView,
      goBack,
      navigation,
      fullScreen,
      transition,
      duration,
      springs,
      registerDefaultView,
      registerFullScreenViews,
      onDidPresent,
      onDidClose,
      originTag,
      originHidden,
    ]
  );

  return <TrayContext.Provider value={value}>{children}</TrayContext.Provider>;
};

TrayRoot.displayName = COMPONENT_NAMES.ROOT;

export { TrayRoot };
