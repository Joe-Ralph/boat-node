import React, { forwardRef } from 'react';
import gsap from 'gsap';
import LandingOverlay from '../components/LandingOverlay';

export interface InvocationProps {
    sectionRef: React.RefObject<HTMLDivElement | null>;
}

export const InvocationOverlay = forwardRef<HTMLDivElement, InvocationProps>(({ sectionRef }, _ref) => {
    return (
        <div
            ref={sectionRef}
            className="story-section absolute inset-0 opacity-100 pointer-events-auto"
        >
            <LandingOverlay />
        </div>
    );
});
InvocationOverlay.displayName = 'InvocationOverlay';

export interface InvocationArgs {
    tl: gsap.core.Timeline;
    sectionRef: React.RefObject<HTMLDivElement | null>;
    canvasEl: HTMLCanvasElement | null;
    label: string;
    start: number;
}

export const registerInvocation = ({
    tl,
    sectionRef,
    canvasEl,
    label,
    start,
}: InvocationArgs): void => {
    tl.addLabel(label, start);
    tl.to(sectionRef.current, { scale: 100, duration: 1.0, ease: 'power4.in' }, label);
    tl.to(sectionRef.current, { opacity: 0, duration: 0.5 }, `${label}+=0.5`);
    tl.set(sectionRef.current, { pointerEvents: 'none' }, `${label}+=1.0`);
    if (canvasEl) {
        tl.to(canvasEl, { y: '0vh', ease: 'none', duration: 1.0 }, label);
    }
};
