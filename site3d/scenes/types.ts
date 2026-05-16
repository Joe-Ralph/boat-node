import type { RefObject } from 'react';
import * as THREE from 'three';
import gsap from 'gsap';
import { World } from '../engine/World';

export interface ActCopyRef {
    container: RefObject<HTMLDivElement | null>;
}

export interface ActRegisterArgs {
    tl: gsap.core.Timeline;
    world: World;
    camera: THREE.PerspectiveCamera;
    copy: ActCopyRef;
    label: string;
    start: number | string;
    duration: number;
    isMobile: boolean;
}

export const fadeStoryIn = (
    tl: gsap.core.Timeline,
    copy: ActCopyRef,
    at: number | string,
): void => {
    const el = copy.container.current;
    if (!el) return;
    tl.to(el, { autoAlpha: 1, duration: 0.4 }, at);
    const lines = el.querySelectorAll<HTMLElement>('.story-line');
    tl.to(lines, { opacity: 1, duration: 0.8, stagger: 0.9 }, at);
};

export const fadeStoryOut = (
    tl: gsap.core.Timeline,
    copy: ActCopyRef,
    at: number | string,
): void => {
    const el = copy.container.current;
    if (!el) return;
    const lines = el.querySelectorAll<HTMLElement>('.story-line');
    tl.to(lines, { opacity: 0, duration: 0.6, stagger: 0.3 }, at);
    tl.to(el, { autoAlpha: 0, duration: 0.4 }, `${at}+=0.6`);
};
