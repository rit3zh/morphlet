import { Children, cloneElement, type ReactElement, type Ref } from 'react';
import { Pressable, type PressableProps } from 'react-native';

import type { ITrayCloseProps } from '../../interfaces';
import type { THostRef, TPressHandler } from '../../types';
import { assignRef, composePress, withHiddenStyle } from '../../utils';

const renderTrayPressable = (
  { asChild, children, onPress, ...rest }: ITrayCloseProps,
  action: () => void,
  hostRef?: { current: THostRef },
  hidden = false
): ReactElement => {
  const handlePress = composePress(onPress, action);

  if (asChild) {
    const child = Children.only(children) as ReactElement<{
      onPress?: TPressHandler;
      ref?: Ref<THostRef>;
      style?: PressableProps['style'];
    }>;
    const childRef = child.props.ref;
    return cloneElement(child, {
      ...rest,
      onPress: composePress(child.props.onPress, handlePress),
      ...(hidden && {
        style: withHiddenStyle(rest.style ?? child.props.style),
      }),
      ...(hostRef && {
        ref: (instance: THostRef) => {
          hostRef.current = instance;
          assignRef(childRef, instance);
        },
      }),
    });
  }

  return (
    <Pressable
      accessibilityRole="button"
      onPress={handlePress}
      collapsable={false}
      {...rest}
      style={hidden ? withHiddenStyle(rest.style) : rest.style}
      ref={
        hostRef &&
        ((instance: THostRef) => {
          hostRef.current = instance;
        })
      }
    >
      {children}
    </Pressable>
  );
};

export { renderTrayPressable };
