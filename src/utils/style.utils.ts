import type { ViewStyle } from 'react-native';

const paddingOf = <T extends ViewStyle>(
  style: T,
  edge: 'Top' | 'Bottom'
): number => {
  const value =
    style[`padding${edge}`] ?? style.paddingVertical ?? style.padding ?? 0;
  return typeof value === 'number' ? value : 0;
};

export { paddingOf };
