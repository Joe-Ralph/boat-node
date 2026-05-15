import * as THREE from 'three';

export interface TowerBundle {
    group: THREE.Group;
    towerMaterial: THREE.MeshBasicMaterial;
    edgeMaterial: THREE.LineBasicMaterial;
}

const createStrut = (
    p1: THREE.Vector3,
    p2: THREE.Vector3,
    thickness: number,
    bodyMat: THREE.Material,
    edgeMat: THREE.LineBasicMaterial,
) => {
    const vec = new THREE.Vector3().subVectors(p2, p1);
    const len = vec.length();
    const geo = new THREE.BoxGeometry(thickness, len, thickness);
    const mesh = new THREE.Mesh(geo, bodyMat);

    const mid = new THREE.Vector3().addVectors(p1, p2).multiplyScalar(0.5);
    mesh.position.copy(mid);

    const axis = new THREE.Vector3(0, 1, 0);
    mesh.quaternion.setFromUnitVectors(axis, vec.clone().normalize());

    const edges = new THREE.EdgesGeometry(geo);
    const line = new THREE.LineSegments(edges, edgeMat.clone());
    mesh.add(line);
    return mesh;
};

export const createTower = (): TowerBundle => {
    const group = new THREE.Group();

    const edgeMaterial = new THREE.LineBasicMaterial({
        color: 0x000000,
        transparent: true,
        opacity: 0.5,
        depthWrite: false,
    });
    const towerMaterial = new THREE.MeshBasicMaterial({ color: 0xff0000, transparent: true, opacity: 1 });

    const segments = 4;
    const totalHeight = 6;
    const segmentHeight = totalHeight / segments;
    const baseRadius = 0.8;
    const topRadius = 0.3;
    const strutThick = 0.05;
    const angleOffset = Math.PI / 4;

    const getCorner = (y: number, r: number, index: number) => {
        const angle = angleOffset + index * Math.PI / 2;
        return new THREE.Vector3(Math.cos(angle) * r, y, Math.sin(angle) * r);
    };

    for (let i = 0; i < segments; i++) {
        const yBottom = i * segmentHeight;
        const yTop = (i + 1) * segmentHeight;

        const rBottom = baseRadius - (baseRadius - topRadius) * (i / segments);
        const rTop = baseRadius - (baseRadius - topRadius) * ((i + 1) / segments);

        for (let k = 0; k < 4; k++) {
            const pBot = getCorner(yBottom, rBottom, k);
            const pTop = getCorner(yTop, rTop, k);
            const nextK = (k + 1) % 4;
            const pBotNext = getCorner(yBottom, rBottom, nextK);
            const pTopNext = getCorner(yTop, rTop, nextK);

            group.add(createStrut(pBot, pTop, strutThick * 2, towerMaterial, edgeMaterial));

            if (i === 0) {
                group.add(createStrut(pBot, pBotNext, strutThick, towerMaterial, edgeMaterial));
            }
            group.add(createStrut(pTop, pTopNext, strutThick, towerMaterial, edgeMaterial));

            group.add(createStrut(pBot, pTopNext, strutThick * 0.8, towerMaterial, edgeMaterial));
            group.add(createStrut(pBotNext, pTop, strutThick * 0.8, towerMaterial, edgeMaterial));
        }
    }

    const platformGeo = new THREE.CylinderGeometry(0.8, 0.8, 0.2, 8);
    const platform = new THREE.Mesh(platformGeo, towerMaterial);
    platform.position.y = 5.8;
    platform.add(new THREE.LineSegments(new THREE.EdgesGeometry(platformGeo), edgeMaterial));
    group.add(platform);

    const mastGeo = new THREE.CylinderGeometry(0.05, 0.05, 2, 4);
    const mast = new THREE.Mesh(mastGeo, towerMaterial);
    mast.position.y = 6 + 1;
    mast.add(new THREE.LineSegments(new THREE.EdgesGeometry(mastGeo), edgeMaterial));
    group.add(mast);

    const dishGeo = new THREE.CylinderGeometry(0.2, 0.2, 0.1, 8);
    const dish1 = new THREE.Mesh(dishGeo, towerMaterial);
    dish1.rotation.x = Math.PI / 2;
    dish1.position.set(0.4, 5.5, 0.4);
    const dishEdges = new THREE.EdgesGeometry(dishGeo);
    dish1.add(new THREE.LineSegments(dishEdges, edgeMaterial));
    group.add(dish1);

    const dish2 = new THREE.Mesh(dishGeo, towerMaterial);
    dish2.rotation.x = Math.PI / 2;
    dish2.rotation.z = Math.PI / 2;
    dish2.position.set(-0.4, 5.2, 0.4);
    dish2.add(new THREE.LineSegments(dishEdges, edgeMaterial));
    group.add(dish2);

    return { group, towerMaterial, edgeMaterial };
};
