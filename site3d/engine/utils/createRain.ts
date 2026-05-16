import * as THREE from 'three';

export interface RainBundle {
    points: THREE.Points;
    material: THREE.PointsMaterial;
    update(dt: number, density: number): void;
}

export const createRain = (count = 4000, area = 120): RainBundle => {
    const positions = new Float32Array(count * 3);
    const velocities = new Float32Array(count);

    for (let i = 0; i < count; i++) {
        positions[i * 3 + 0] = (Math.random() - 0.5) * area;
        positions[i * 3 + 1] = Math.random() * 40 + 5;
        positions[i * 3 + 2] = (Math.random() - 0.5) * area;
        velocities[i] = 20 + Math.random() * 20;
    }

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));

    const material = new THREE.PointsMaterial({
        color: 0x88aacc,
        size: 0.15,
        transparent: true,
        opacity: 0,
        depthWrite: false,
    });

    const points = new THREE.Points(geometry, material);
    points.frustumCulled = false;
    points.visible = false;

    return {
        points,
        material,
        update(dt: number, density: number) {
            const target = Math.min(1, Math.max(0, density));
            material.opacity = target * 0.6;
            points.visible = target > 0.01;
            if (!points.visible) return;
            const pos = geometry.attributes.position as THREE.BufferAttribute;
            const arr = pos.array as Float32Array;
            for (let i = 0; i < count; i++) {
                arr[i * 3 + 1] -= velocities[i] * dt * (0.5 + target);
                if (arr[i * 3 + 1] < 0) {
                    arr[i * 3 + 1] = Math.random() * 40 + 5;
                    arr[i * 3 + 0] = (Math.random() - 0.5) * area;
                    arr[i * 3 + 2] = (Math.random() - 0.5) * area;
                }
            }
            pos.needsUpdate = true;
        },
    };
};
