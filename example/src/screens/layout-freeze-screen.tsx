import { useEffect, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { Tray } from 'morphlet';

import { colors, fonts, radius, spacing } from '../constants';

export default function LayoutFreezeScreen() {
  return (
    <View style={styles.screen}>
      <Ticker />
      <Tray.Root>
        <Tray.Trigger asChild>
          <Pressable style={styles.button}>
            <Text style={styles.label}>Open tray</Text>
          </Pressable>
        </Tray.Trigger>
        <Tray.Content backgroundColor={colors.background} cornerRadius={40}>
          <Rows />
        </Tray.Content>
      </Tray.Root>
    </View>
  );
}

function Ticker() {
  const [opacity, setOpacity] = useState(1);

  useEffect(() => {
    let frame = requestAnimationFrame(function tick(time) {
      setOpacity(0.5 + 0.5 * Math.sin(time / 300));
      frame = requestAnimationFrame(tick);
    });
    return () => cancelAnimationFrame(frame);
  }, []);

  return <View style={[styles.ticker, { opacity }]} />;
}

function Rows() {
  const [count, setCount] = useState(1);

  return (
    <View style={styles.rows}>
      {Array.from({ length: count }, (_, index) => (
        <View key={index} style={styles.row} />
      ))}
      <Pressable
        onPress={() => setCount(count === 1 ? 3 : 1)}
        style={styles.button}
      >
        <Text style={styles.label}>Toggle rows</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    justifyContent: 'center',
    gap: spacing.xl,
    padding: spacing.xl,
    backgroundColor: colors.background,
  },
  ticker: {
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.text,
  },
  rows: {
    gap: spacing.md,
    padding: spacing.xl,
  },
  row: {
    height: 56,
    borderRadius: radius.md,
    backgroundColor: colors.border,
  },
  button: {
    alignItems: 'center',
    padding: spacing.lg,
    borderRadius: radius.pill,
    backgroundColor: colors.text,
  },
  label: {
    fontFamily: fonts.medium,
    fontSize: 16,
    color: colors.background,
  },
});
