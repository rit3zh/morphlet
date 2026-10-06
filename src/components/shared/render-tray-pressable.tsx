import { Children, cloneElement, type ReactElement, type Ref } from 'react';
import { Pressable } from 'react-native';

import type { ITrayCloseProps } from '../../interfaces';
import type { THostRef, TPressHandler } from '../../types';
import { assignRef, composePress } from '../../utils';

const renderTrayPressable = (
  { asChild, children, onPress, ...rest }: ITrayCloseProps,
  action: () => void,
  hostRef?: { current: THostRef }
): ReactElement => {
  const handlePress = composePress(onPress, action);

  if (asChild) {
    const child = Children.only(children) as ReactElement<{
      onPress?: TPressHandler;
      ref?: Ref<THostRef>;
    }>;
    const childRef = child.props.ref;
    return cloneElement(child, {
      ...rest,
      onPress: composePress(child.props.onPress, handlePress),
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
