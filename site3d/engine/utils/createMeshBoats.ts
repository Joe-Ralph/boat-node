import * as THREE from 'three';
import { createLowPolyBoat } from './createLowPolyBoat';
import { PALETTE_THREE } from '../palette';

export interface MeshBoatNode {
    mesh: THREE.Group;
    pos: THREE.Vector3;
    signalRing: THREE.Mesh;
    mat: THREE.MeshBasicMaterial;
}

export interface MeshBoatsBundle {
    group: THREE.Group;
    nodes: MeshBoatNode[];
    arcLines: THREE.LineSegments;
    arcMaterial: THREE.LineBasicMaterial;
    segmentsPerLine: number;
    maxHops: number;
}

const PREDEFINED_POSITIONS: [number, number, number][] = [
    [45, 0, -5],
    [30, 0, 8],
    [15, 0, -6],
    [0, 0, 5],
    [-5, 0, -2],
];

export const createMeshBoats = (): MeshBoatsBundle => {
    const group = new THREE.Group();
    group.visible = false;

    const nodes: MeshBoatNode[] = [];

    PREDEFINED_POSITIONS.forEach((pos) => {
        const { group: bGroup, signalRing, mat } = createLowPolyBoat(PALETTE_THREE.magenta);
        bGroup.position.set(pos[0], 0.5, pos[2]);
        bGroup.rotation.y = Math.PI / 2;
        mat.color.set(0x222233);
        group.add(bGroup);
        nodes.push({
            mesh: bGroup,
            pos: new THREE.Vector3(pos[0], 0.5, pos[2]),
            signalRing,
            mat,
        });
    });

    const segmentsPerLine = 30;
    const maxHops = 10;
    const vertexCount = maxHops * (segmentsPerLine - 1) * 2;
    const arcPositions = new Float32Array(vertexCount * 3);
    const arcGeo = new THREE.BufferGeometry();
    arcGeo.setAttribute('position', new THREE.BufferAttribute(arcPositions, 3));

    const arcMaterial = new THREE.LineBasicMaterial({
        color: 0x00ffff,
        transparent: true,
        opacity: 0,
    });
    const arcLines = new THREE.LineSegments(arcGeo, arcMaterial);
    arcLines.frustumCulled = false;
    group.add(arcLines);

    return { group, nodes, arcLines, arcMaterial, segmentsPerLine, maxHops };
};
