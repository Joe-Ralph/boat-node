import React, { useRef, useEffect } from 'react';
import * as THREE from 'three';
import { Fish } from 'lucide-react';

const LandingOverlay: React.FC = () => {
    const containerRef = useRef<HTMLDivElement>(null);
    const canvasRef = useRef<HTMLCanvasElement>(null);

    useEffect(() => {
        if (!canvasRef.current || !containerRef.current) return;

        // --- PARTICLE SYSTEM SETUP ---
        const scene = new THREE.Scene();
        const camera = new THREE.PerspectiveCamera(75, 1, 0.1, 1000);
        camera.position.z = 12; // Moved back to see full sphere & fix interaction parallax

        const renderer = new THREE.WebGLRenderer({
            canvas: canvasRef.current,
            alpha: true,
            antialias: true
        });

        // Resize handler
        const resize = () => {
            if (!containerRef.current) return;
            const width = containerRef.current.clientWidth;
            const height = containerRef.current.clientHeight;
            renderer.setSize(width, height);
            camera.aspect = width / height;
            camera.updateProjectionMatrix();
        };
        resize();
        window.addEventListener('resize', resize);

        // --- GLOWING BLACK HOLE PARTICLE SYSTEM ---

        const count = 1000; // 12 strands * 1000 particles
        const geometry = new THREE.BufferGeometry();
        const positions = new Float32Array(count * 3);
        const randoms = new Float32Array(count * 3);
        const colors = new Float32Array(count * 3);
        const scales = new Float32Array(count);

        // Strand Setup
        const numStrands = 12; // Fewer, "Beautiful Pattern" (Atomic/Geometric)
        const particlesPerStrand = Math.ceil(count / numStrands);

        const colorPalette = [
            new THREE.Color('#00ffff'), // Cyan
            new THREE.Color('#4488ff'), // Electric Blue
            new THREE.Color('#00ccff'), // Light Blue
            new THREE.Color('#D54DFF')
        ];

        // Fibonacci Sphere Algorithm for evenly distributed axes (Beautiful Symmetry)
        const goldenRatio = (1 + Math.sqrt(5)) / 2;

        for (let s = 0; s < numStrands; s++) {
            // Calculate evenly distributed axis
            const theta = 2 * Math.PI * s / goldenRatio;
            const phi = Math.acos(1 - 2 * (s + 0.5) / numStrands);

            const axis = new THREE.Vector3(
                Math.cos(theta) * Math.sin(phi),
                Math.sin(theta) * Math.sin(phi),
                Math.cos(phi)
            ).normalize();

            // Build a basis
            const temp = new THREE.Vector3(0, 1, 0);
            if (Math.abs(axis.y) > 0.9) temp.set(1, 0, 0);
            const u = new THREE.Vector3().crossVectors(axis, temp).normalize();
            const v = new THREE.Vector3().crossVectors(axis, u).normalize();

            // Consistent elegant radius
            const strandRadius = 6.0;
            const strandSpeed = 0.5; // Uniform speed for harmony? Or slightly varied? 
            // "Beautiful pattern" -> Uniformity is safely beautiful.

            // Offset phase to ensure they don't all start at same relative spot
            const offset = (s / numStrands) * Math.PI * 2;

            for (let p = 0; p < particlesPerStrand; p++) {
                const i = s * particlesPerStrand + p;
                if (i >= count) break;

                const i3 = i * 3;

                // Perfect Circle Distribution
                const angle = (p / particlesPerStrand) * Math.PI * 2 + offset;

                const pos = new THREE.Vector3()
                    .addScaledVector(u, Math.cos(angle) * strandRadius)
                    .addScaledVector(v, Math.sin(angle) * strandRadius);

                positions[i3] = pos.x;
                positions[i3 + 1] = pos.y;
                positions[i3 + 2] = pos.z;

                // Store Axis scaled by Speed
                randoms[i3] = axis.x * strandSpeed;
                randoms[i3 + 1] = axis.y * strandSpeed;
                randoms[i3 + 2] = axis.z * strandSpeed;

                const color = colorPalette[Math.floor(Math.random() * colorPalette.length)];
                colors[i3] = color.r;
                colors[i3 + 1] = color.g;
                colors[i3 + 2] = color.b;

                // Uniform solid lines needed? 
                scales[i] = 0.2;
            }
        }

        geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
        geometry.setAttribute('aAxisSpeed', new THREE.BufferAttribute(randoms, 3));
        geometry.setAttribute('color', new THREE.BufferAttribute(colors, 3));
        geometry.setAttribute('aScale', new THREE.BufferAttribute(scales, 1));

        const material = new THREE.ShaderMaterial({
            depthWrite: false,
            blending: THREE.AdditiveBlending,
            vertexColors: true,
            transparent: true,
            uniforms: {
                uTime: { value: 0 },
                uMouse: { value: new THREE.Vector2(-999, -999) },
                uPixelRatio: { value: Math.min(window.devicePixelRatio, 2) },
                uSize: { value: 60.0 } // Larger dots since camera is far
            },
            vertexShader: `
                uniform float uTime;
                uniform float uPixelRatio;
                uniform float uSize;
                uniform vec2 uMouse;
                
                attribute float aScale;
                attribute vec3 aAxisSpeed; // Axis * Speed
                
                varying vec3 vColor;
                
                // Axis-Angle Rotation (Rodrigues' Formula)
                vec3 rotate3d(vec3 v, vec3 k, float theta) {
                    float c = cos(theta);
                    float s = sin(theta);
                    return v * c + cross(k, v) * s + k * dot(k, v) * (1.0 - c);
                }
                
                void main() {
                    vec3 pos = position; 
                    
                    // 1. Yarn Ball Flow (Discrete Threads)
                    // Extract Axis and Speed
                    float speed = length(aAxisSpeed);
                    vec3 axis = aAxisSpeed / speed; // Normalize
                    
                    float angle = uTime * speed;
                    
                    // Rotate the point around the strand's axis
                    // Since the point started ON the great circle of this axis, 
                    // it will stay on the trail.
                    pos = rotate3d(pos, axis, angle);
                    
                    
                    
                    // 2. GRAVITATIONAL LENSING (Black Hole Distortion)
                    float dist = distance(pos.xy, uMouse);
                    float radius = 10.0; // Tighter influence radius
                    float eventHorizon = 7.0; // The dark void center
                    
                    if(dist < radius) {
                        // Calculate distortion strength based on proximity to center
                        // We want a strong push at the center (creating void) falling off to 0
                        float strength = 1.0 - (dist / radius); 
                        float distortion = pow(strength, 2.0) * 2.0; // Non-linear warping
                        
                        // Direction away from singluarity
                        vec2 dir = normalize(pos.xy - uMouse);
                        
                        // Apply warping (Push outward to create Einstein Ring)
                        pos.x += dir.x * distortion;
                        pos.y += dir.y * distortion;
                        
                        // OPTIONAL: Pull Z towards viewer (bulge) or away? 
                        // Let's pull Z closer to simulate magnification/lens curve
                        pos.z += strength * 2.0;
                        
                        // Scale up particles in the lensing field (Magnification effect)
                        // Particles at the "Ring" (high distortion) become brighter/larger
                        gl_PointSize *= (1.0 + strength * 3.0);
                    }

                    vec4 modelPosition = modelMatrix * vec4(pos, 1.0);
                    vec4 viewPosition = viewMatrix * modelPosition;
                    vec4 projectionPosition = projectionMatrix * viewPosition;
                    
                    gl_Position = projectionPosition;
                    
                    gl_PointSize = uSize * aScale * uPixelRatio;
                    gl_PointSize *= (1.0 / -viewPosition.z);
                    
                    vColor = color;
                }
            `,
            fragmentShader: `
                varying vec3 vColor;
                
                void main() {
                    // Sharp Circular Dot (No Glow)
                    float dist = distance(gl_PointCoord, vec2(0.5));
                    
                    // Strict Cutoff
                    if (dist > 0.5) discard;
                    
                    gl_FragColor = vec4(vColor, 1.0);
                }
            `
        });

        const particles = new THREE.Points(geometry, material);
        scene.add(particles);

        // Interaction Logic (Mouse & Touch)
        const plane = new THREE.Plane(new THREE.Vector3(0, 0, 1), 0); // Z=0 plane
        const raycaster = new THREE.Raycaster();
        const mouse = new THREE.Vector2();

        const updateInteraction = (clientX: number, clientY: number) => {
            // Normalized Device Coordinates (-1 to +1)
            mouse.x = (clientX / window.innerWidth) * 2 - 1;
            mouse.y = -(clientY / window.innerHeight) * 2 + 1;

            raycaster.setFromCamera(mouse, camera);
            const target = new THREE.Vector3();
            raycaster.ray.intersectPlane(plane, target);

            // Update Uniform
            if (material.uniforms.uMouse) {
                material.uniforms.uMouse.value.set(target.x, target.y);
            }
        };

        const onMouseMove = (event: MouseEvent) => {
            updateInteraction(event.clientX, event.clientY);
        };

        const onTouchMove = (event: TouchEvent) => {
            if (event.touches.length > 0) {
                const touch = event.touches[0];
                updateInteraction(touch.clientX, touch.clientY);
            }
        };

        window.addEventListener('mousemove', onMouseMove);
        window.addEventListener('touchmove', onTouchMove, { passive: true });
        window.addEventListener('touchstart', onTouchMove, { passive: true }); // Update on initial touch too

        // Animation Loop
        const clock = new THREE.Clock();
        const animate = () => {
            requestAnimationFrame(animate);
            material.uniforms.uTime.value = clock.getElapsedTime();
            renderer.render(scene, camera);
        };
        const animId = requestAnimationFrame(animate);

        return () => {
            window.removeEventListener('resize', resize);
            window.removeEventListener('mousemove', onMouseMove);
            window.removeEventListener('touchmove', onTouchMove);
            window.removeEventListener('touchstart', onTouchMove);
            cancelAnimationFrame(animId);
            renderer.dispose();
            geometry.dispose();
            material.dispose();
        }

    }, []);


    return (
        <div className="w-full h-full bg-black flex flex-col items-center justify-center font-['Rajdhani']">
            {/* Full Screen Particle Background */}
            <div ref={containerRef} className="absolute inset-0 z-0 pointer-events-none">
                <canvas ref={canvasRef} className="w-full h-full opacity-60" />
            </div>

            {/* Typography - Questions Only */}
            <div className="text-center z-10 max-w-4xl px-6">
                 <h1 className="text-3xl md:text-6xl font-light tracking-wide text-white leading-tight">
                    Ever wondered how the fish you eat reaches you?<br />
                    <span className="text-cyan-200 font-medium">Someone risks their life for it.</span>
                </h1>
                <p className="text-gray-500 text-xs md:text-sm tracking-[0.3em] uppercase mt-8 animate-pulse">
                    Scroll to begin
                </p>
            </div>
        </div>
    );
};

export default LandingOverlay;