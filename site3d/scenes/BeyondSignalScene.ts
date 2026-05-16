import { ActRegisterArgs, fadeStoryIn, fadeStoryOut } from './types';
import { PALETTE_THREE } from '../engine/palette';

export const registerBeyondSignal = ({ tl, world, camera, copy, label, start, duration, isMobile }: ActRegisterArgs): void => {
    tl.addLabel(label, start);

    tl.to(world.boat.group.position, { x: 35, z: 0, duration, ease: 'none' }, label);
    tl.to(camera.position, { x: 35, z: isMobile ? 30 : 12, y: 5, duration, ease: 'none' }, label);

    tl.to(world.shoreMaterials, { opacity: 0, duration: 3 }, `${label}+=${duration * 0.4}`);
    tl.to(world.towerSignalState, { opacity: 0, duration: 2 }, `${label}+=${duration * 0.4}`);

    tl.to(world.sceneParams, {
        waveHeight: 0.9,
        timeScale: 2.0,
        surfaceR: PALETTE_THREE.ultramarine.r,
        surfaceG: PALETTE_THREE.ultramarine.g,
        surfaceB: PALETTE_THREE.ultramarine.b,
        duration,
    }, label);

    tl.call(() => { world.signalArcs.group.visible = true; }, [], label);
    const arcProxy = { v: 0 };
    tl.to(arcProxy, {
        v: 1,
        duration: duration * 0.35,
        onUpdate: () => world.signalArcs.setProgress(arcProxy.v),
    }, label);
    tl.to(world.signalArcs.material, { opacity: 0, duration: duration * 0.3 }, `${label}+=${duration * 0.5}`);
    tl.call(() => { world.signalArcs.group.visible = false; }, [], `${label}+=${duration * 0.85}`);

    fadeStoryIn(tl, copy, `${label}+=0.5`);
    fadeStoryOut(tl, copy, `${label}+=${Math.max(2, duration - 5)}`);
};
