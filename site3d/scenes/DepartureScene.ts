import { ActRegisterArgs, fadeStoryIn, fadeStoryOut } from './types';
import { PALETTE_THREE } from '../engine/palette';

export const registerDeparture = ({ tl, world, camera, copy, label, start, duration, isMobile }: ActRegisterArgs): void => {
    tl.addLabel(label, start);

    tl.to(world.towerSignalState, { opacity: 1, duration: 1 }, label);
    tl.to(world.sceneParams, { waveHeight: 1.0, timeScale: 1.2, duration: 5 }, label);

    tl.call(() => { world.harborLights.group.visible = true; }, [], label);
    tl.to(world.harborLights.material, { opacity: 1, duration: 2 }, label);

    fadeStoryIn(tl, copy, `${label}+=0.5`);

    tl.to(world.boat.group.position, { x: 10, z: 0, duration, ease: 'power1.in' }, `${label}+=2`);
    tl.to(camera.position, { x: 10, z: isMobile ? 30 : 12, duration, ease: 'power1.in' }, `${label}+=2`);

    tl.to(world.boat.mat.color, {
        r: PALETTE_THREE.amber.r,
        g: PALETTE_THREE.amber.g,
        b: PALETTE_THREE.amber.b,
        duration: 3,
    }, label);

    fadeStoryOut(tl, copy, `${label}+=${Math.max(2, duration - 4)}`);

    tl.to(world.harborLights.material, { opacity: 0, duration: 3 }, `${label}+=${Math.max(2, duration - 3)}`);
};
