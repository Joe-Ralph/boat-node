import * as THREE from 'three';

export interface SignalArcsBundle {
    group: THREE.Group;
    material: THREE.LineBasicMaterial;
    setProgress(p: number): void;
}

/**
 * Snapping mesh-style arcs between the tower and a series of waypoints,
 * used for Act 2 "Beyond Signal" — arcs snap then dissolve as the boat
 * drifts past the radio horizon.
 */
export const createSignalArcs = (
    origin: THREE.Vector3,
    waypoints: THREE.Vector3[],
    color = 0x00ffff,
): SignalArcsBundle => {
    const group = new THREE.Group();
    const material = new THREE.LineBasicMaterial({
        color,
        transparent: true,
        opacity: 0.7,
    });

    const arcs: { line: THREE.Line; basePositions: Float32Array }[] = [];
    const SEG = 24;

    waypoints.forEach((end) => {
        const mid = new THREE.Vector3().lerpVectors(origin, end, 0.5);
        mid.y += origin.distanceTo(end) * 0.3;
        const curve = new THREE.QuadraticBezierCurve3(origin, mid, end);
        const points = curve.getPoints(SEG);
        const positions = new Float32Array(points.length * 3);
        points.forEach((p, i) => {
            positions[i * 3 + 0] = p.x;
            positions[i * 3 + 1] = p.y;
            positions[i * 3 + 2] = p.z;
        });
        const geo = new THREE.BufferGeometry();
        geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
        const line = new THREE.Line(geo, material);
        line.frustumCulled = false;
        group.add(line);
        arcs.push({ line, basePositions: positions.slice() });
    });

    return {
        group,
        material,
        setProgress(p: number) {
            const clamped = Math.min(1, Math.max(0, p));
            arcs.forEach(({ line, basePositions }) => {
                const pos = line.geometry.attributes.position as THREE.BufferAttribute;
                const arr = pos.array as Float32Array;
                const segments = basePositions.length / 3;
                const visible = Math.floor(segments * clamped);
                for (let i = 0; i < segments; i++) {
                    const idx = i * 3;
                    if (i <= visible) {
                        arr[idx] = basePositions[idx];
                        arr[idx + 1] = basePositions[idx + 1];
                        arr[idx + 2] = basePositions[idx + 2];
                    } else {
                        arr[idx] = basePositions[Math.max(0, visible) * 3];
                        arr[idx + 1] = basePositions[Math.max(0, visible) * 3 + 1];
                        arr[idx + 2] = basePositions[Math.max(0, visible) * 3 + 2];
                    }
                }
                pos.needsUpdate = true;
            });
        },
    };
};
