import React, { useEffect, useRef } from 'react';
import { PALETTE } from '../engine/palette';

export interface ScrollProgressProps {
    targetRef: React.RefObject<HTMLDivElement | null>;
}

const ScrollProgress: React.FC<ScrollProgressProps> = ({ targetRef }) => {
    const barRef = useRef<HTMLDivElement>(null);

    useEffect(() => {
        const onScroll = () => {
            const el = targetRef.current;
            const bar = barRef.current;
            if (!el || !bar) return;
            const rect = el.getBoundingClientRect();
            const total = rect.height - window.innerHeight;
            const scrolled = Math.min(total, Math.max(0, -rect.top));
            const pct = total > 0 ? scrolled / total : 0;
            bar.style.transform = `scaleX(${pct})`;
        };
        window.addEventListener('scroll', onScroll, { passive: true });
        onScroll();
        return () => window.removeEventListener('scroll', onScroll);
    }, [targetRef]);

    return (
        <div
            className="fixed top-0 left-0 w-full z-40 pointer-events-none"
            style={{ height: 2 }}
        >
            <div
                ref={barRef}
                style={{
                    height: '100%',
                    width: '100%',
                    background: PALETTE.cyan,
                    transformOrigin: '0 50%',
                    transform: 'scaleX(0)',
                    boxShadow: `0 0 10px ${PALETTE.cyan}`,
                }}
            />
        </div>
    );
};

export default ScrollProgress;
