import { ActRegisterArgs, fadeStoryIn, fadeStoryOut } from './types';
import { PALETTE_THREE } from '../engine/palette';

export const registerAwakening = ({ tl, world, camera, copy, label, start, duration, isMobile }: ActRegisterArgs): void => {
    tl.addLabel(label, start);

    tl.to(world.boat.pulseSphere.material, { opacity: 0, duration: 0.5 }, label);
    tl.call(() => { world.sosState.active = false; }, [], label);

    world.mesh.nodes.forEach((n, idx) => {
        tl.to(n.mat.color, {
            r: PALETTE_THREE.cyan.r, g: PALETTE_THREE.cyan.g, b: PALETTE_THREE.cyan.b,
            duration: 1.0,
        }, `${label}+=${idx * 1.0}`);
    });

    const meshProxy = { value: 0 };
    tl.to(meshProxy, {
        value: 1,
        duration: 0.1,
        onUpdate: () => {
            const on = meshProxy.value > 0.5;
            world.meshAnim.active = on;
            world.mesh.group.visible = on;
            world.mesh.arcMaterial.opacity = on ? 1 : 0;
            if (!on) {
                const arr = (world.mesh.arcLines.geometry.attributes.position.array as Float32Array);
                arr.fill(0);
                world.mesh.arcLines.geometry.attributes.position.needsUpdate = true;
            }
        },
        onReverseComplete: () => {
            world.meshAnim.active = false;
            world.mesh.group.visible = false;
        },
    }, `${label}+=2`);

    tl.to([world.terrain.material, world.tower.towerMaterial], { opacity: 1, duration: 2 }, label);

    tl.to(world.boat.mat.color, {
        r: PALETTE_THREE.magenta.r,
        g: PALETTE_THREE.magenta.g,
        b: PALETTE_THREE.magenta.b,
        duration: 1.0,
    }, `${label}+=${duration * 0.5}`);

    fadeStoryIn(tl, copy, `${label}+=0.5`);
    fadeStoryOut(tl, copy, `${label}+=${Math.max(3, duration - 5)}`);
};
