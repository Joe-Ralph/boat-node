import * as THREE from 'three';
import gsap from 'gsap';
import { World } from '../engine/World';
import { ActCopyRef } from './types';
import { registerDeparture } from './DepartureScene';
import { registerBeyondSignal } from './BeyondSignalScene';
import { registerStorm } from './StormScene';
import { registerSOS } from './SOSScene';
import { registerAwakening } from './AwakeningScene';
import { registerHome } from './HomeScene';

export interface ActCopies {
    departure: ActCopyRef;
    beyondSignal: ActCopyRef;
    storm: ActCopyRef;
    sos: ActCopyRef;
    awakening: ActCopyRef;
    home: ActCopyRef;
}

export interface SceneRegistryArgs {
    tl: gsap.core.Timeline;
    world: World;
    camera: THREE.PerspectiveCamera;
    copies: ActCopies;
    isMobile: boolean;
    introEnd: number;
}

export interface ActSpec {
    label: string;
    duration: number;
}

export const ACT_SPECS: ActSpec[] = [
    { label: 'departure', duration: 18 },
    { label: 'beyondSignal', duration: 18 },
    { label: 'storm', duration: 18 },
    { label: 'sos', duration: 14 },
    { label: 'awakening', duration: 22 },
    { label: 'home', duration: 14 },
];

export const registerAllActs = ({
    tl,
    world,
    camera,
    copies,
    isMobile,
    introEnd,
}: SceneRegistryArgs): { actStarts: number[]; storyEnd: number } => {
    const actStarts: number[] = [];
    let cursor = introEnd;

    const acts: { spec: ActSpec; copy: ActCopyRef; register: (a: Parameters<typeof registerDeparture>[0]) => void }[] = [
        { spec: ACT_SPECS[0], copy: copies.departure, register: registerDeparture },
        { spec: ACT_SPECS[1], copy: copies.beyondSignal, register: registerBeyondSignal },
        { spec: ACT_SPECS[2], copy: copies.storm, register: registerStorm },
        { spec: ACT_SPECS[3], copy: copies.sos, register: registerSOS },
        { spec: ACT_SPECS[4], copy: copies.awakening, register: registerAwakening },
        { spec: ACT_SPECS[5], copy: copies.home, register: registerHome },
    ];

    acts.forEach(({ spec, copy, register }) => {
        actStarts.push(cursor);
        register({
            tl,
            world,
            camera,
            copy,
            label: spec.label,
            start: cursor,
            duration: spec.duration,
            isMobile,
        });
        cursor += spec.duration;
    });

    return { actStarts, storyEnd: cursor };
};
