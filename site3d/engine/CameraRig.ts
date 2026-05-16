import * as THREE from 'three';

export interface CameraPose {
    x: number;
    y: number;
    z: number;
    lookX: number;
    lookY: number;
    lookZ: number;
}

export class CameraRig {
    base: CameraPose;
    shake = { intensity: 0, decay: 4 };
    parallax = { x: 0, y: 0, strength: 0.6 };

    constructor(public camera: THREE.PerspectiveCamera, initial: CameraPose) {
        this.base = { ...initial };
        this.apply();
    }

    setBase(pose: Partial<CameraPose>) {
        Object.assign(this.base, pose);
    }

    triggerShake(intensity: number) {
        this.shake.intensity = Math.max(this.shake.intensity, intensity);
    }

    setParallaxStrength(s: number) {
        this.parallax.strength = s;
    }

    setPointer(nx: number, ny: number) {
        this.parallax.x = nx;
        this.parallax.y = ny;
    }

    update(dt: number) {
        const sx = (Math.random() - 0.5) * this.shake.intensity;
        const sy = (Math.random() - 0.5) * this.shake.intensity;
        const px = this.parallax.x * this.parallax.strength;
        const py = this.parallax.y * this.parallax.strength;
        this.camera.position.set(this.base.x + sx + px, this.base.y + sy + py, this.base.z);
        this.camera.lookAt(this.base.lookX, this.base.lookY, this.base.lookZ);
        this.shake.intensity = Math.max(0, this.shake.intensity - dt * this.shake.decay);
    }

    apply() {
        this.camera.position.set(this.base.x, this.base.y, this.base.z);
        this.camera.lookAt(this.base.lookX, this.base.lookY, this.base.lookZ);
    }
}
