import { useState, type ComponentRef, type Ref } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useRouter } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Tray, useTray } from 'morphlet';
import { SymbolView, type SFSymbol } from '../components/symbol-view';
import {
  TRAY_CONTENT,
  playgroundColors as colors,
  playgroundType as type,
} from '../components/tray-playground';
import { PlaygroundTrayHeader } from '../components/tray-playground/playground-tray-parts';

interface IField {
  key: string;
  label: string;
  title: string;
  icon: SFSymbol;
  options: string[];
}

const FIELDS: IField[] = [
  {
    key: 'from',
    label: 'From',
    title: 'Departing from',
    icon: 'tram.fill',
    options: ['Aarhus', 'Odense', 'Copenhagen Central', 'Aalborg'],
  },
  {
    key: 'to',
    label: 'To',
    title: 'Arriving at',
    icon: 'mappin.and.ellipse',
    options: ['Esbjerg', 'Roskilde', 'Kolding', 'Helsingør'],
  },
  {
    key: 'passengers',
    label: 'Passengers',
    title: 'Passengers',
    icon: 'person.2.fill',
    options: [
      '1 adult',
      '2 adults',
      '2 adults, 1 child',
      '2 adults, 2 children',
    ],
  },
];

export default function PickerScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const [values, setValues] = useState<Record<string, string>>(() =>
    Object.fromEntries(
      FIELDS.map((field: IField) => [field.key, field.options[0]!])
    )
  );

  return (
    <View style={styles.screen}>
      <StatusBar style="dark" />

      <ScrollView
        contentContainerStyle={[
          styles.content,
          { paddingTop: insets.top + 8, paddingBottom: insets.bottom + 24 },
        ]}
      >
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Back"
          hitSlop={8}
          onPress={() => router.back()}
          style={styles.back}
        >
          <SymbolView
            name="chevron.left"
            size={15}
            weight="semibold"
            tintColor={colors.text}
          />
        </Pressable>

        <Text style={styles.title}>Picker</Text>
        <Text style={styles.subtitle}>Tap a value to change it.</Text>

        <View style={styles.group}>
          {FIELDS.map((field, index) => (
            <View
              key={field.key}
              style={[styles.field, index > 0 && styles.separator]}
            >
              <SymbolView
                name={field.icon}
                size={16}
                tintColor={colors.text}
                style={styles.fieldIcon}
              />
              <Text style={[type.label, styles.fieldLabel]}>{field.label}</Text>
              <FieldPicker
                field={field}
                value={values[field.key]!}
                onChange={(value) =>
                  setValues((current) => ({ ...current, [field.key]: value }))
                }
              />
            </View>
          ))}
        </View>
      </ScrollView>
    </View>
  );
}

interface IFieldPickerProps {
  field: IField;
  value: string;
  onChange: (value: string) => void;
}

function FieldPicker({ field, value, onChange }: IFieldPickerProps) {
  return (
    <Tray.Root>
      <Tray.Trigger asChild morph>
        <Chip label={value} />
      </Tray.Trigger>
      <Tray.Content {...TRAY_CONTENT}>
        <PlaygroundTrayHeader title={field.title} />
        <Tray.Body>
          <Options options={field.options} value={value} onChange={onChange} />
        </Tray.Body>
      </Tray.Content>
    </Tray.Root>
  );
}

interface IOptionsProps {
  options: string[];
  value: string;
  onChange: (value: string) => void;
}

function Options({ options, value, onChange }: IOptionsProps) {
  const { close } = useTray();

  return (
    <View style={styles.options}>
      <View style={styles.optionGroup}>
        {options.map((option, index) => {
          const selected = option === value;
          return (
            <Pressable
              key={option}
              accessibilityRole="button"
              accessibilityState={{ selected }}
              onPress={() => {
                onChange(option);
                close();
              }}
              style={({ pressed }) => [
                styles.option,
                index > 0 && styles.separator,
                pressed && styles.optionPressed,
              ]}
            >
              <Text style={[type.value, styles.optionLabel]}>{option}</Text>
              {selected && (
                <SymbolView
                  name="checkmark"
                  size={15}
                  weight="semibold"
                  tintColor={colors.text}
                />
              )}
            </Pressable>
          );
        })}
      </View>
    </View>
  );
}

interface IChipProps {
  label: string;
  onPress?: () => void;
  ref?: Ref<ComponentRef<typeof Pressable>>;
}

function Chip({ label, onPress, ref }: IChipProps) {
  return (
    <Pressable
      ref={ref}
      accessibilityRole="button"
      onPress={onPress}
      style={({ pressed }) => [styles.chip, pressed && styles.chipPressed]}
    >
      <Text style={[type.value, styles.chipLabel]} numberOfLines={1}>
        {label}
      </Text>
      <SymbolView
        name="chevron.right"
        size={11}
        weight="semibold"
        tintColor={colors.label}
      />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.background,
  },
  content: {
    paddingHorizontal: 20,
  },
  back: {
    width: 40,
    height: 40,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.card,
  },
  title: {
    ...type.display,
    fontSize: 34,
    marginTop: 20,
    color: colors.text,
  },
  subtitle: {
    ...type.body,
    marginTop: 4,
    marginBottom: 24,
    color: colors.label,
  },
  group: {
    borderRadius: 24,
    borderCurve: 'continuous',
    backgroundColor: colors.card,
  },
  field: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    minHeight: 60,
    paddingHorizontal: 16,
  },
  fieldIcon: {
    width: 20,
  },
  separator: {
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.separator,
  },
  fieldLabel: {
    flex: 1,
    color: colors.text,
  },
  chip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    maxWidth: 220,
    paddingVertical: 8,
    paddingHorizontal: 12,
    borderRadius: 999,
    backgroundColor: colors.background,
  },
  chipPressed: {
    opacity: 0.6,
  },
  chipLabel: {
    flexShrink: 1,
    color: colors.textSecondary,
  },
  options: {
    paddingHorizontal: 20,
    paddingBottom: 20,
  },
  optionGroup: {
    overflow: 'hidden',
    borderRadius: 20,
    borderCurve: 'continuous',
    backgroundColor: colors.card,
  },
  option: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    height: 54,
    paddingHorizontal: 18,
  },
  optionPressed: {
    backgroundColor: colors.cardPressed,
  },
  optionLabel: {
    flex: 1,
    color: colors.text,
  },
});
