import { useFonts } from 'expo-font';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';

import { fonts } from '../constants';

const FONT_SOURCES = {
  [fonts.regular]: require('../../assets/fonts/rounded-regular.otf'),
  [fonts.medium]: require('../../assets/fonts/rounded-medium.otf'),
  [fonts.bold]: require('../../assets/fonts/rounded-bold.otf'),
};

export default function RootLayout() {
  const [fontsLoaded, fontError] = useFonts(FONT_SOURCES);

  if (!fontsLoaded && !fontError) return null;

  return (
    <>
      <StatusBar style="dark" />
      <Stack
        screenOptions={{
          headerShown: false,
          headerTitleStyle: { fontFamily: fonts.bold },
        }}
      >
        <Stack.Screen name="index" />
        <Stack.Screen name="game" />
        <Stack.Screen name="collections" />
        <Stack.Screen name="playground" />
        <Stack.Screen name="picker" />
      </Stack>
    </>
  );
}
