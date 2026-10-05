import type {
  PressableProps,
  PressableStateCallbackType,
  StyleProp,
  ViewStyle,
} from 'react-native';

const paddingOf = <T extends ViewStyle>(
  style: T,
  edge: 'Top' | 'Bottom'
): number => {
  const value =
    style[`padding${edge}`] ?? style.paddingVertical ?? style.padding ?? 0;
  return typeof value === 'number' ? value : 0;
};

const HIDDEN_STYLE: ViewStyle = { opacity: 0 };

const withHiddenStyle = (
  style: PressableProps['style']
): PressableProps['style'] =>
  typeof style === 'function'
    ? (state: PressableStateCallbackType): StyleProp<ViewStyle> => [
        style(state),
        HIDDEN_STYLE,
      ]
    : [style, HIDDEN_STYLE];

export { paddingOf, withHiddenStyle };
