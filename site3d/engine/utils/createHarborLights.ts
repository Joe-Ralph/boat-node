import * as THREE from 'three';
import { PALETTE } from '../palette';

export interface HarborLightsBundle {
    group: THREE.Group;
    material: THREE.SpriteMaterial;
    update(t: number): void;
}

const makeGlowTexture = (): THREE.CanvasTexture => {
    const size = 64;
    const c = document.createElement('canvas');
    c.width = c.height = size;
    const ctx = c.getContext('2d')!;
    const grad = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
    grad.addColorStop(0, 'rgba(255,179,71,1)');
    grad.addColorStop(0.4, 'rgba(255,179,71,0.5)');
    grad.addColorStop(1, 'rgba(255,179,71,0)');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, size, size);
    return new THREE.CanvasTexture(c);
};

const DEFAULT_POSITIONS: [number, number, number][] = [
    [-22, 1.5, -10],
    [-23, 1.5, -2],
    [-22, 1.5, 6],
    [-24, 1.5, 14],
    [-21, 1.5, 22],
    [-25, 2.0, -18],
    [-25, 2.0, 18],
    [-18, 1.2, 0],
];

export const createHarborLights = (positions = DEFAULT_POSITIONS): HarborLightsBundle => {
    const group = new THREE.Group();
    group.visible = false;

    const tex = makeGlowTexture();
    const material = new THREE.SpriteMaterial({
        map: tex,
        color: PALETTE.amber,
        transparent: true,
        opacity: 0,
        depthWrite: false,
        blending: THREE.AdditiveBlending,
    });

    const sprites: { sprite: THREE.Sprite; phase: number; baseScale: number }[] = [];
    positions.forEach((p, i) => {
        const sprite = new THREE.Sprite(material.clone());
        const baseScale = 1.6 + (i % 3) * 0.4;
        sprite.scale.setScalar(baseScale);
        sprite.position.set(p[0], p[1], p[2]);
        group.add(sprite);
        sprites.push({ sprite, phase: i * 0.7, baseScale });
    });

    return {
        group,
        material,
        update(t: number) {
            sprites.forEach(({ sprite, phase, baseScale }) => {
                const flicker = 0.85 + Math.sin(t * 2 + phase) * 0.1 + Math.sin(t * 7 + phase) * 0.05;
                sprite.scale.setScalar(baseScale * flicker);
                (sprite.material as THREE.SpriteMaterial).opacity =
                    (material.opacity ?? 0) * (0.7 + 0.3 * flicker);
            });
        },
    };
};
