import React, { useState } from 'react';
import { PALETTE } from '../engine/palette';

export interface BootOverlayProps {
    onBoot: () => void;
    label?: string;
}

const BootOverlay: React.FC<BootOverlayProps> = ({ onBoot, label = 'Tap to begin' }) => {
    const [gone, setGone] = useState(false);

    const handle = () => {
        setGone(true);
        setTimeout(() => onBoot(), 400);
    };

    if (gone) return null;

    return (
        <div
            onClick={handle}
            className="fixed inset-0 z-50 flex items-center justify-center cursor-pointer"
            style={{
                background: PALETTE.bgPage,
                transition: 'opacity 400ms ease',
                opacity: gone ? 0 : 1,
            }}
        >
            <div className="text-center">
                <div
                    style={{
                        fontFamily: '"JetBrains Mono", monospace',
                        fontSize: 11,
                        textTransform: 'uppercase',
                        letterSpacing: '0.4em',
                        color: PALETTE.cyan,
                        marginBottom: 18,
                    }}
                >
                    Neduvaai
                </div>
                <div
                    style={{
                        fontFamily: 'Rajdhani, sans-serif',
                        fontSize: 'clamp(24px, 4vw, 36px)',
                        color: PALETTE.offWhite,
                        letterSpacing: '0.04em',
                    }}
                >
                    {label}
                </div>
                <div
                    style={{
                        marginTop: 24,
                        fontFamily: '"JetBrains Mono", monospace',
                        fontSize: 10,
                        textTransform: 'uppercase',
                        letterSpacing: '0.3em',
                        color: `${PALETTE.white}66`,
                    }}
                >
                    Best with sound · scroll to journey
                </div>
            </div>
        </div>
    );
};

export default BootOverlay;
