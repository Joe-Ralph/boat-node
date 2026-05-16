import React, { forwardRef } from 'react';
import gsap from 'gsap';
import CTAPanel from '../ui/CTAPanel';

export interface ActSceneProps {
    sectionRef: React.RefObject<HTMLDivElement | null>;
}

export const ActOverlay = forwardRef<HTMLDivElement, ActSceneProps>(({ sectionRef }, _ref) => {
    return (
        <div
            ref={sectionRef}
            className="story-section absolute inset-0 flex items-center justify-center pointer-events-none"
            style={{ opacity: 0 }}
        >
            <CTAPanel />
        </div>
    );
});
ActOverlay.displayName = 'ActOverlay';

export interface ActRegisterArgs {
    tl: gsap.core.Timeline;
    sectionRef: React.RefObject<HTMLDivElement | null>;
    label: string;
    start: number | string;
    duration: number;
}

export const registerAct = ({ tl, sectionRef, label, start, duration }: ActRegisterArgs): void => {
    tl.addLabel(label, start);
    tl.to(sectionRef.current, { autoAlpha: 1, duration: 1.2 }, label);
    tl.set(sectionRef.current, { pointerEvents: 'auto' }, `${label}+=1.2`);
    tl.to(sectionRef.current, { autoAlpha: 1, duration: 0.1 }, `${label}+=${duration - 0.2}`);
};
