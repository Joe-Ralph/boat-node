import { ActRegisterArgs, fadeStoryIn, fadeStoryOut } from './types';
import { PALETTE } from '../engine/palette';
import * as THREE from 'three';

export const registerStorm = ({ tl, world, camera, copy, label, start, duration, isMobile }: ActRegisterArgs): void => {
    tl.addLabel(label, start);

    tl.to(world.sceneParams, {
        waveHeight: 1.6,
        timeScale: 3.0,
        duration,
    }, label);

    const storm = new THREE.Color(PALETTE.bgStorm);
    tl.to(world.bgColor, {
        r: storm.r,
        g: storm.g,
        b: storm.b,
        duration: duration * 0.6,
    }, label);

    tl.call(() => { world.rain.points.visible = true; }, [], label);
    tl.to(world.rainDensity, { value: 1, duration: duration * 0.4, ease: 'power2.in' }, label);

    tl.to(world.boat.group.position, { x: 55, duration, ease: 'none' }, label);
    tl.to(camera.position, { x: 55, z: isMobile ? 30 : 12, y: 5, duration, ease: 'none' }, label);

    fadeStoryIn(tl, copy, `${label}+=0.5`);
    fadeStoryOut(tl, copy, `${label}+=${Math.max(2, duration - 4)}`);

    tl.to(world.rainDensity, { value: 0, duration: duration * 0.2 }, `${label}+=${duration * 0.85}`);
};
