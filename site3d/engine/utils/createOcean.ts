import * as THREE from 'three';
import { oceanVertexShader, oceanFragmentShader } from '../../shaders';

export interface OceanBundle {
    ocean: THREE.Points;
    material: THREE.ShaderMaterial;
    geometry: THREE.PlaneGeometry;
}

export const createOcean = (surfaceColor: THREE.Color): OceanBundle => {
    const geometry = new THREE.PlaneGeometry(500, 500, 400, 400);
    geometry.rotateX(-Math.PI / 2);

    const material = new THREE.ShaderMaterial({
        vertexShader: oceanVertexShader,
        fragmentShader: oceanFragmentShader,
        uniforms: {
            uTime: { value: 0 },
            uWaveHeight: { value: 0.3 },
            uDepthColor: { value: new THREE.Color(0x000011) },
            uSurfaceColor: { value: surfaceColor },
        },
        transparent: true,
        blending: THREE.AdditiveBlending,
    });

    const ocean = new THREE.Points(geometry, material);
    return { ocean, material, geometry };
};
