/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

export const oceanVertexShader = `
  uniform float uTime;
  uniform float uWaveHeight;
  
  varying float vElevation;
  varying vec2 vUv;

  void main() {
    vUv = uv;
    vec4 modelPosition = modelMatrix * vec4(position, 1.0);

    // Aggressive, fast waves
    float elevation = sin(modelPosition.x * 0.2 + uTime * 1.5) * 0.5; // Faster x speed
    elevation += sin(modelPosition.z * 0.5 + uTime * 1.2) * 0.2;      // Faster z speed
    
    // Chaotic additive wave layer for "stormy" feel
    elevation += sin(modelPosition.x * 0.8 - uTime * 2.0) * 0.1;

    // Apply wave height multiplier
    elevation *= uWaveHeight;

    // Dampen waves near shore (x < 0) to prevent clipping through land
    // Smoothstep from x=-10 (0 amplitude) to x=20 (1 amplitude)
    float dampening = smoothstep(-20.0, 10.0, modelPosition.x);
    elevation *= dampening;
    
    // Sharpen peaks significantly for "Deep Sea" danger look
    elevation = pow(abs(elevation), 1.5) * sign(elevation);

    modelPosition.y += elevation;

    vec4 viewPosition = viewMatrix * modelPosition;
    vec4 projectedPosition = projectionMatrix * viewPosition;

    gl_Position = projectedPosition;
    
    // Variation in point size based on depth/elevation
    gl_PointSize = (6.0 + elevation) * (1.0 / -viewPosition.z); 
    // Ensure min size
    gl_PointSize = max(2.0, gl_PointSize);

    vElevation = elevation;
  }
`;

export const oceanFragmentShader = `
  uniform vec3 uDepthColor;
  uniform vec3 uSurfaceColor;
  
  varying float vElevation;

  void main() {
    // High contrast mix
    float mixStrength = (vElevation + 1.0) * 0.6;
    vec3 color = mix(uDepthColor, uSurfaceColor, mixStrength);
    
    // Additive glow factor for crests
    float glow = smoothstep(0.5, 1.0, vElevation);
    color += uSurfaceColor * glow * 0.5;

    // Distance fade to black (simple fog-like effect)
    float alpha = 1.0; 
    
    gl_FragColor = vec4(color, alpha);
  }
`;

export const pulseVertexShader = `
  varying vec2 vUv;
  void main() {
    vUv = uv;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  }
`;

export const pulseFragmentShader = `
  uniform float uTime;
  uniform vec3 uColor;
  varying vec2 vUv;

  void main() {
    float dist = distance(vUv, vec2(0.5));
    float ring = fract(dist * 10.0 - uTime * 2.0);
    float alpha = smoothstep(0.4, 0.5, ring) - smoothstep(0.5, 0.6, ring);
    alpha *= (1.0 - smoothstep(0.3, 0.5, dist));
    gl_FragColor = vec4(uColor, alpha);
  }
`;
