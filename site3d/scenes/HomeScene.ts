import { ActRegisterArgs, fadeStoryIn, fadeStoryOut } from './types';
import { PALETTE_THREE } from '../engine/palette';

export const registerHome = ({ tl, world, camera, copy, label, start, duration, isMobile }: ActRegisterArgs): void => {
    tl.addLabel(label, start);

    tl.to(camera.position, {
        x: 20,
        y: isMobile ? 150 : 60,
        z: 20,
        duration: duration * 0.6,
        ease: 'power2.inOut',
    }, label);
    tl.to(camera.rotation, { x: -Math.PI / 2, y: 0, z: 0, duration: duration * 0.6 }, label);

    tl.call(() => { world.harborLights.group.visible = true; }, [], label);
    tl.to(world.harborLights.material, { opacity: 1, duration: 3 }, label);

    tl.to(world.sceneParams, {
        surfaceR: PALETTE_THREE.cyanLight.r,
        surfaceG: PALETTE_THREE.cyanLight.g,
        surfaceB: PALETTE_THREE.cyanLight.b,
        waveHeight: 0.3,
        timeScale: 0.8,
        duration,
    }, label);

    fadeStoryIn(tl, copy, `${label}+=0.5`);
    fadeStoryOut(tl, copy, `${label}+=${Math.max(3, duration - 4)}`);
};
