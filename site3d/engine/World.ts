import * as THREE from 'three';
import { createLowPolyBoat, LowPolyBoat } from './utils/createLowPolyBoat';
import { createOcean, OceanBundle } from './utils/createOcean';
import { createTerrain, TerrainBundle } from './utils/createTerrain';
import { createTower, TowerBundle } from './utils/createTower';
import { createMeshBoats, MeshBoatsBundle } from './utils/createMeshBoats';
import { createSignalArcs, SignalArcsBundle } from './utils/createSignalArcs';
import { createRain, RainBundle } from './utils/createRain';
import { createHarborLights, HarborLightsBundle } from './utils/createHarborLights';
import { PALETTE_THREE } from './palette';

export interface SceneParams {
    timeScale: number;
    waveHeight: number;
    surfaceR: number;
    surfaceG: number;
    surfaceB: number;
}

export interface MeshAnimState {
    active: boolean;
    loopTimer: number;
    step: number;
    pulseRadius: number;
}

export interface World {
    ocean: OceanBundle;
    terrain: TerrainBundle;
    tower: TowerBundle;
    shoreGroup: THREE.Group;
    shoreMaterials: THREE.Material[];
    pulseRings: THREE.Mesh[];
    pulseMat: THREE.MeshBasicMaterial;
    pulseParams: { speed: number; maxRadius: number; count: number };
    towerSignalState: { opacity: number };
    boat: LowPolyBoat;
    ambientGroup: THREE.Group;
    mesh: MeshBoatsBundle;
    signalArcs: SignalArcsBundle;
    rain: RainBundle;
    harborLights: HarborLightsBundle;
    sceneParams: SceneParams;
    meshAnim: MeshAnimState;
    sosState: { active: boolean; t: number };
    morsePattern: number[];
    rainDensity: { value: number };
    bgColor: THREE.Color;
}

const MORSE_SOS_PATTERN = [
    1, 0.2, 1, 0.2, 1, 0.6,
    1.4, 0.2, 1.4, 0.2, 1.4, 0.6,
    1, 0.2, 1, 0.2, 1, 1.2,
];

export const buildWorld = (scene: THREE.Scene): World => {
    const ocean = createOcean(PALETTE_THREE.cyanLight);
    scene.add(ocean.ocean);

    const shoreGroup = new THREE.Group();
    const terrain = createTerrain();
    shoreGroup.add(terrain.mesh);

    const tower = createTower();
    tower.group.position.set(-20, 0.1, 0);
    shoreGroup.add(tower.group);

    const trunkMat = new THREE.MeshBasicMaterial({ color: 0x8b4513, transparent: true, opacity: 1 });
    const foliageMat = new THREE.MeshBasicMaterial({ color: 0x228b22, transparent: true, opacity: 1 });
    const houseMat = new THREE.MeshBasicMaterial({ color: 0xeeeeee, transparent: true, opacity: 1 });
    const roofMat = new THREE.MeshBasicMaterial({ color: 0x8b0000, transparent: true, opacity: 1 });
    const shoreMaterials: THREE.Material[] = [
        tower.edgeMaterial,
        tower.towerMaterial,
        terrain.material,
        trunkMat,
        foliageMat,
        houseMat,
        roofMat,
    ];

    const treePositions: [number, number][] = [
        [-20, -45], [-20, -35], [-20, -25], [-20, -15], [-20, -5],
        [-20, 5], [-20, 15], [-20, 25], [-20, 35], [-20, 45],
        [-30, -45], [-30, -35], [-30, -25], [-30, -15], [-30, -5],
        [-30, 5], [-30, 15], [-30, 25], [-30, 35], [-30, 45],
    ];
    treePositions.forEach((pos) => {
        const treeGroup = new THREE.Group();
        const trunkGeo = new THREE.CylinderGeometry(0.2, 0.2, 1, 6);
        const trunk = new THREE.Mesh(trunkGeo, trunkMat);
        trunk.position.y = 0.5;
        trunk.add(new THREE.LineSegments(new THREE.EdgesGeometry(trunkGeo), tower.edgeMaterial));
        const foliageGeo = new THREE.ConeGeometry(0.8, 2, 6);
        const foliage = new THREE.Mesh(foliageGeo, foliageMat);
        foliage.position.y = 2;
        foliage.add(new THREE.LineSegments(new THREE.EdgesGeometry(foliageGeo), tower.edgeMaterial));
        treeGroup.add(trunk, foliage);
        treeGroup.position.set(pos[0], terrain.getHeight(pos[0], pos[1]), pos[1]);
        shoreGroup.add(treeGroup);
    });

    const housePositions: [number, number][] = [
        [-25, -50], [-25, -40], [-25, -30], [-25, -20], [-25, -10],
        [-25, 0],
        [-25, 10], [-25, 20], [-25, 30], [-25, 40], [-25, 50],
    ];
    housePositions.forEach((pos, i) => {
        const houseGroup = new THREE.Group();
        const w = 2 + (i % 3) * 0.5;
        const d = 2 + ((i + 1) % 3) * 0.5;
        const h = 1.5;
        const houseGeo = new THREE.BoxGeometry(w, h, d);
        const house = new THREE.Mesh(houseGeo, houseMat);
        house.position.y = h / 2;
        house.add(new THREE.LineSegments(new THREE.EdgesGeometry(houseGeo), tower.edgeMaterial));
        const roofGeo = new THREE.ConeGeometry(Math.max(w, d) * 0.8, 1, 4);
        const roof = new THREE.Mesh(roofGeo, roofMat);
        roof.position.y = h + 0.5;
        roof.rotation.y = Math.PI / 4;
        roof.add(new THREE.LineSegments(new THREE.EdgesGeometry(roofGeo), tower.edgeMaterial));
        houseGroup.add(house, roof);
        houseGroup.position.set(pos[0], terrain.getHeight(pos[0], pos[1]), pos[1]);
        shoreGroup.add(houseGroup);
    });

    const towerTipY = 8.0;
    const pulseParams = { speed: 10.0, maxRadius: 45, count: 3 };
    const pulseMat = new THREE.MeshBasicMaterial({
        color: PALETTE_THREE.magenta,
        transparent: true,
        opacity: 0.8,
        side: THREE.DoubleSide,
        depthWrite: false,
    });
    const pulseRings: THREE.Mesh[] = [];
    for (let i = 0; i < pulseParams.count; i++) {
        const ringGeo = new THREE.RingGeometry(0.99, 1.0, 64);
        const ring = new THREE.Mesh(ringGeo, pulseMat.clone());
        ring.rotation.x = -Math.PI / 2;
        ring.position.set(-20, towerTipY + i * 0.01, 0);
        ring.userData = { phase: (i / pulseParams.count) * pulseParams.maxRadius };
        shoreGroup.add(ring);
        pulseRings.push(ring);
    }
    scene.add(shoreGroup);

    const boat = createLowPolyBoat(PALETTE_THREE.white);
    boat.group.position.set(-10, 0.5, 0);
    scene.add(boat.group);

    const mesh = createMeshBoats();
    scene.add(mesh.group);

    const signalArcs = createSignalArcs(
        new THREE.Vector3(-20, towerTipY, 0),
        [
            new THREE.Vector3(0, 0.5, 5),
            new THREE.Vector3(15, 0.5, -6),
            new THREE.Vector3(30, 0.5, 8),
        ],
    );
    signalArcs.group.visible = false;
    scene.add(signalArcs.group);

    const ambientGroup = new THREE.Group();
    const ambientCount = 15;
    for (let i = 0; i < ambientCount; i++) {
        const { group: bGroup } = createLowPolyBoat(PALETTE_THREE.white);
        const x = (Math.random() - 0.5) * 100 + 40;
        let z = (Math.random() - 0.5) * 80;
        if (Math.abs(z) < 10) z += 20 * (Math.sign(z) || 1);
        bGroup.position.set(x, 0.5, z);
        bGroup.rotation.y = Math.random() * Math.PI * 2;
        bGroup.traverse((c) => {
            if (c instanceof THREE.Mesh && (c.material as THREE.MeshBasicMaterial)?.color) {
                const m = c.material as THREE.MeshBasicMaterial;
                c.material = m.clone();
                (c.material as THREE.MeshBasicMaterial).color.setHex(0x555555);
            }
        });
        ambientGroup.add(bGroup);
    }
    scene.add(ambientGroup);

    const rain = createRain();
    scene.add(rain.points);

    const harborLights = createHarborLights();
    scene.add(harborLights.group);

    const sceneParams: SceneParams = {
        timeScale: 0.5,
        waveHeight: 0.2,
        surfaceR: PALETTE_THREE.cyanLight.r,
        surfaceG: PALETTE_THREE.cyanLight.g,
        surfaceB: PALETTE_THREE.cyanLight.b,
    };

    return {
        ocean,
        terrain,
        tower,
        shoreGroup,
        shoreMaterials,
        pulseRings,
        pulseMat,
        pulseParams,
        towerSignalState: { opacity: 0 },
        boat,
        ambientGroup,
        mesh,
        signalArcs,
        rain,
        harborLights,
        sceneParams,
        meshAnim: { active: false, loopTimer: 0, step: -1, pulseRadius: 0 },
        sosState: { active: false, t: 0 },
        morsePattern: MORSE_SOS_PATTERN,
        rainDensity: { value: 0 },
        bgColor: new THREE.Color(PALETTE_THREE.white).set(0x111116),
    };
};
