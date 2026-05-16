import { ActRegisterArgs, fadeStoryIn, fadeStoryOut } from './types';

export const registerSOS = ({ tl, world, camera, copy, label, start, duration, isMobile }: ActRegisterArgs): void => {
    tl.addLabel(label, start);

    tl.to(world.boat.mat.color, { r: 1, g: 0, b: 0, duration: 0.5 }, label);
    tl.to(world.boat.pulseSphere.material, { opacity: 0.5, duration: 0.5 }, label);
    tl.set(world.boat.pulseSphere.scale, { x: 1, y: 1, z: 1 }, label);

    tl.call(() => { world.sosState.active = true; }, [], label);

    tl.to(world.mesh.nodes.map((n) => n.mat.color), {
        r: 0.1, g: 0.1, b: 0.13, duration: 1,
    }, label);
    tl.call(() => { world.mesh.group.visible = true; }, [], label);

    tl.to(camera.position, { y: 5, duration, ease: 'none' }, label);

    fadeStoryIn(tl, copy, `${label}+=0.5`);
    fadeStoryOut(tl, copy, `${label}+=${Math.max(2, duration - 4)}`);
};
