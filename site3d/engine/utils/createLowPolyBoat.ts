import * as THREE from 'three';

export interface LowPolyBoat {
    group: THREE.Group;
    mat: THREE.MeshBasicMaterial;
    glowMat: THREE.MeshBasicMaterial;
    glow: THREE.Mesh;
    pulseSphere: THREE.Mesh;
    signalRing: THREE.Mesh;
}

export const createLowPolyBoat = (color: number | string | THREE.Color): LowPolyBoat => {
    const group = new THREE.Group();
    const mat = new THREE.MeshBasicMaterial({ color: color as THREE.ColorRepresentation, side: THREE.DoubleSide });
    const edgeColor = 0x000000;
    const edgeMat = new THREE.LineBasicMaterial({ color: edgeColor, linewidth: 2 });

    // Hull: Trapezoid (cylinder with 4 sides)
    const hullGeo = new THREE.CylinderGeometry(0.6, 0.3, 0.5, 4);
    const hull = new THREE.Mesh(hullGeo, mat);
    hull.rotation.y = Math.PI / 2;
    hull.scale.set(1, 1, 2);
    hull.position.y = 0.25;
    group.add(hull);

    const hullEdges = new THREE.EdgesGeometry(hullGeo);
    const hullLines = new THREE.LineSegments(hullEdges, edgeMat);
    hullLines.rotation.copy(hull.rotation);
    hullLines.scale.copy(hull.scale);
    hullLines.position.copy(hull.position);
    group.add(hullLines);

    // Sail: Pyramid
    const sailGeo = new THREE.ConeGeometry(0.5, 1.5, 3);
    const sail = new THREE.Mesh(sailGeo, mat);
    sail.position.set(0, 1.0, 0);
    sail.rotation.y = Math.PI + Math.PI / 2;
    sail.scale.set(0.1, 1, 1);
    group.add(sail);

    const sailEdges = new THREE.EdgesGeometry(sailGeo);
    const sailLines = new THREE.LineSegments(sailEdges, edgeMat);
    sailLines.position.copy(sail.position);
    sailLines.rotation.copy(sail.rotation);
    sailLines.scale.copy(sail.scale);
    group.add(sailLines);

    // Glow sphere (kept hidden; retained for API compatibility)
    const glowGeo = new THREE.SphereGeometry(2, 16, 16);
    const glowMat = new THREE.MeshBasicMaterial({ color: color as THREE.ColorRepresentation, transparent: true, opacity: 0 });
    const glow = new THREE.Mesh(glowGeo, glowMat);
    glow.visible = false;
    group.add(glow);

    // SOS Pulse Sphere
    const pulseSphereGeo = new THREE.SphereGeometry(1, 32, 32);
    const pulseSphereMat = new THREE.MeshBasicMaterial({ color: 0xff0000, transparent: true, opacity: 0 });
    const pulseSphere = new THREE.Mesh(pulseSphereGeo, pulseSphereMat);
    pulseSphere.visible = false;
    group.add(pulseSphere);

    // Generic Signal Ring (driven by mesh animation)
    const signalRingGeo = new THREE.RingGeometry(0.5, 0.6, 32);
    const signalRingMat = new THREE.MeshBasicMaterial({ color: 0xBC13FE, transparent: true, opacity: 0, side: THREE.DoubleSide });
    const signalRing = new THREE.Mesh(signalRingGeo, signalRingMat);
    signalRing.rotation.x = -Math.PI / 2;
    signalRing.visible = false;
    group.add(signalRing);

    return { group, mat, glowMat, glow, pulseSphere, signalRing };
};
