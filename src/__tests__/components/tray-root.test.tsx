import { describe, expect, it, jest } from '@jest/globals';
import { act, fireEvent, render, screen } from '@testing-library/react-native';
import { Text } from 'react-native';

import { Tray, useTray } from '../../root';
import { containerViews, hostView } from '../helpers/native';

const Basic = (props: Parameters<typeof Tray.Root>[0]) => (
  <Tray.Root {...props}>
    <Tray.Trigger>
      <Text>Open</Text>
    </Tray.Trigger>
    <Tray.Content>
      <Tray.Title>Title</Tray.Title>
      <Tray.Close>
        <Text>Close</Text>
      </Tray.Close>
    </Tray.Content>
  </Tray.Root>
);

describe('Tray.Root', () => {
  it('starts closed with no content mounted', () => {
    render(<Basic />);

    expect(hostView().props.open).toBe(false);
    expect(containerViews()).toHaveLength(0);
    expect(screen.queryByText('Title')).toBeNull();
  });

  it('opens from the trigger', () => {
    render(<Basic />);

    fireEvent.press(screen.getByText('Open'));

    expect(hostView().props.open).toBe(true);
    expect(screen.getByText('Title')).toBeTruthy();
  });

  it('starts open with defaultOpen', () => {
    render(<Basic defaultOpen />);

    expect(hostView().props.open).toBe(true);
  });

  it('keeps content mounted until the native close animation finishes', () => {
    render(<Basic defaultOpen />);

    fireEvent.press(screen.getByText('Close'));

    expect(hostView().props.open).toBe(false);
    expect(screen.getByText('Title')).toBeTruthy();

    act(() => hostView().props.onDidDismiss());

    expect(screen.queryByText('Title')).toBeNull();
  });

  it('reports a close started natively, such as a drag', () => {
    const onOpenChange = jest.fn();
    render(<Basic defaultOpen onOpenChange={onOpenChange} />);

    act(() => hostView().props.onWillDismiss());

    expect(onOpenChange).toHaveBeenCalledWith(false);
    expect(hostView().props.open).toBe(false);
  });

  it('stays open when controlled and the parent ignores the change', () => {
    const onOpenChange = jest.fn();
    render(<Basic open onOpenChange={onOpenChange} />);

    fireEvent.press(screen.getByText('Close'));

    expect(onOpenChange).toHaveBeenCalledWith(false);
    expect(hostView().props.open).toBe(true);
  });

  it('merges into its child with asChild', () => {
    const onPress = jest.fn();
    render(
      <Tray.Root>
        <Tray.Trigger asChild>
          <Text onPress={onPress}>Custom trigger</Text>
        </Tray.Trigger>
        <Tray.Content />
      </Tray.Root>
    );

    fireEvent.press(screen.getByText('Custom trigger'));

    expect(onPress).toHaveBeenCalled();
    expect(hostView().props.open).toBe(true);
  });

  it('requires a root for its parts', () => {
    const Orphan = () => {
      useTray();
      return null;
    };
    jest.spyOn(console, 'error').mockImplementation(() => {});

    expect(() => render(<Orphan />)).toThrow(
      '<useTray> must be used within <Tray.Root>.'
    );
  });
});
