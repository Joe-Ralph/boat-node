import * as THREE from 'three';

export interface TerrainBundle {
    mesh: THREE.Mesh;
    material: THREE.MeshBasicMaterial;
    getHeight: (x: number, z: number) => number;
}

export const createTerrain = (): TerrainBundle => {
    const terrainWidth = 200;
    const terrainDepth = 500;
    const terrainSegW = 40;
    const terrainSegD = 40;

    const geometry = new THREE.PlaneGeometry(terrainWidth, terrainDepth, terrainSegW, terrainSegD);
    geometry.rotateX(-Math.PI / 2);

    const posAttr = geometry.attributes.position;
    const vertex = new THREE.Vector3();

    const getHeight = (x: number, z: number) => {
        const shoreX = -10 + Math.sin(z * 0.05) * 5 + Math.sin(z * 0.2) * 2;
        let h = 0;
        if (x < -80) {
            h = 6;
        } else if (x < -30) {
            const t = (x - -80) / (-30 - -80);
            h = (1 - t) * 6;
        } else {
            const t = (x - -30) / (shoreX - -30);
            h = Math.max(0, (1 - t) * 1);
        }
        return h;
    };

    for (let i = 0; i < posAttr.count; i++) {
        vertex.fromBufferAttribute(posAttr, i);
        vertex.x -= 110;

        let height = 0;
        const shoreX = -10 + Math.sin(vertex.z * 0.05) * 5 + Math.sin(vertex.z * 0.2) * 2;
        const noise = (Math.random() - 0.5) * 1.5;

        if (vertex.x < -80) {
            height = 6 + Math.random() * 2;
        } else if (vertex.x < -30) {
            const t = (vertex.x - -80) / (-30 - -80);
            height = (1 - t) * 6 + noise;
        } else {
            const t = (vertex.x - -30) / (shoreX - -30);
            height = Math.max(0, (1 - t) * 1) + Math.random() * 0.2;
        }

        vertex.y = Math.max(0, height);
        posAttr.setXYZ(i, vertex.x, vertex.y, vertex.z);
    }

    geometry.computeVertexNormals();

    const count = geometry.attributes.position.count;
    geometry.setAttribute('color', new THREE.BufferAttribute(new Float32Array(count * 3), 3));
    const colorAttr = geometry.attributes.color;
    const baseColor = new THREE.Color(0xd2b48c);
    const rockColor = new THREE.Color(0x6b5b4e);

    for (let i = 0; i < count; i++) {
        vertex.fromBufferAttribute(posAttr, i);
        const finalColor = baseColor.clone();
        if (vertex.y > 2) {
            finalColor.lerp(rockColor, 0.5 + Math.random() * 0.5);
        } else {
            finalColor.offsetHSL(0, 0, (Math.random() - 0.5) * 0.1);
        }
        finalColor.offsetHSL(0, 0, (Math.random() - 0.5) * 0.1);
        colorAttr.setXYZ(i, finalColor.r, finalColor.g, finalColor.b);
    }

    const material = new THREE.MeshBasicMaterial({
        vertexColors: true,
        transparent: true,
        opacity: 1,
    });

    const mesh = new THREE.Mesh(geometry, material);
    return { mesh, material, getHeight };
};
