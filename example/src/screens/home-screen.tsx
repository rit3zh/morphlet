import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Link, type Href } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { SymbolView, type SFSymbol } from '../components/symbol-view';
import { colors, fonts, radius, shadows, spacing } from '../constants';

interface IExample {
  title: string;
  subtitle: string;
  icon: SFSymbol;
  href: Href;
}

const EXAMPLES: IExample[] = [
  {
    title: 'Playground',
    subtitle: 'Every kind of tray, with tunable springs.',
    icon: 'wand.and.stars',
    href: '/playground',
  },
  {
    title: 'Picker',
    subtitle: 'Chips that grow into options and fold into the new value.',
    icon: 'checkmark.circle.fill',
    href: '/picker',
  },
  {
    title: 'Game',
    subtitle: 'A game page where every button grows into a tray.',
    icon: 'crown.fill',
    href: '/game',
  },
  {
    title: 'Collections',
    subtitle: 'Folders, glass and a tray that grows from the FAB.',
    icon: 'folder.fill',
    href: '/collections',
  },
];

export default function HomeScreen() {
  const insets = useSafeAreaInsets();

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={[
        styles.content,
        { paddingTop: insets.top + spacing.xl, paddingBottom: insets.bottom },
      ]}
    >
      <Text style={styles.title}>Morphlet</Text>
      <Text style={styles.subtitle}>A floating tray that morphs.</Text>

      <View style={styles.list}>
        {EXAMPLES.map((example) => (
          <Link key={example.title} href={example.href} asChild>
            <Pressable style={styles.row}>
              <View style={styles.icon}>
                <SymbolView
                  name={example.icon}
                  size={18}
                  weight="semibold"
                  tintColor={colors.inverse}
                />
              </View>
              <View style={styles.text}>
                <Text style={styles.rowTitle}>{example.title}</Text>
                <Text style={styles.rowSubtitle}>{example.subtitle}</Text>
              </View>
              <SymbolView
                name="chevron.right"
                size={14}
                weight="semibold"
                tintColor={colors.textMuted}
              />
            </Pressable>
          </Link>
        ))}
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.background,
  },
  content: {
    paddingHorizontal: spacing.lg,
  },
  title: {
    fontFamily: fonts.bold,
    fontSize: 34,
    color: colors.text,
  },
  subtitle: {
    marginTop: spacing.xs,
    fontFamily: fonts.regular,
    fontSize: 16,
    color: colors.textMuted,
  },
  list: {
    marginTop: spacing.xl,
    gap: spacing.md,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    padding: spacing.lg,
    borderRadius: radius.md,
    backgroundColor: colors.surface,
    ...shadows.soft,
  },
  icon: {
    width: 36,
    height: 36,
    borderRadius: radius.sm,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.text,
  },
  text: {
    flex: 1,
    gap: 2,
  },
  rowTitle: {
    fontFamily: fonts.bold,
    fontSize: 17,
    color: colors.text,
  },
  rowSubtitle: {
    fontFamily: fonts.regular,
    fontSize: 14,
    color: colors.textMuted,
  },
});
