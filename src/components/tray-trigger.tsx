import * as React from 'react';
import { useRef } from 'react';

import { COMPONENT_NAMES, NO_ORIGIN_TAG } from '../constants';
import { useTrayContext } from '../hooks';
import type { ITrayTriggerProps } from '../interfaces';
import type { THostRef } from '../types';
import { resolveOriginTag } from '../utils';
import { renderTrayPressable } from './shared';

const TrayTrigger: React.FC<ITrayTriggerProps> = ({
  morph = false,
  ...props
}: ITrayTriggerProps): React.ReactElement => {
  const { open, setOpen, setOriginTag } = useTrayContext(
    COMPONENT_NAMES.TRIGGER
  );
  const hostRef = useRef<THostRef>(null);

  return renderTrayPressable(
    { accessibilityState: { expanded: open }, ...props },
    () => {
      if (!open) {
        const tag =
          morph && hostRef.current ? resolveOriginTag(hostRef.current) : null;
        setOriginTag(tag ?? NO_ORIGIN_TAG);
      }
      setOpen(!open);
    },
    hostRef
  );
};

TrayTrigger.displayName = COMPONENT_NAMES.TRIGGER;

export { TrayTrigger };
