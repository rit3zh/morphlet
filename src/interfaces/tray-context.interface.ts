import type { TTrayTransition } from '../types';
import type { IResolvedTrayAnimation } from './tray-animation.interface';
import type { ITrayState } from './tray-state.interface';

interface ITrayContext extends ITrayState {
  transition: TTrayTransition;
  duration: number;
  springs: IResolvedTrayAnimation;
  registerDefaultView: (view: string) => void;
  registerFullScreenViews: (names: string[]) => void;
  onDidClose: () => void;
  originTag: number;
  setOriginTag: (tag: number) => void;
}

export type { ITrayContext };
