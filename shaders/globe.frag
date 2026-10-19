// The Earth as a lit sphere (orthographic), wrapped in the map's own
// Web Mercator world picture, with a soft atmosphere around it.
// Drawn by FlagsGlobe (lib/widgets/flags_globe.dart).
#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uCenter;   // the sphere's middle, in pixels
uniform float uRadius;  // its radius, in pixels
uniform float uLng0;    // the point facing the viewer, in radians
uniform float uLat0;
uniform float uOpacity;
uniform sampler2D uWorld;

out vec4 fragColor;

const float PI = 3.14159265359;
// Web Mercator stops at about 85.05°.
const float MAX_LAT = 1.48442222;
const vec3 SKY = vec3(0.70, 0.84, 0.95);

void main() {
  vec2 p = (FlutterFragCoord().xy - uCenter) / uRadius;
  p.y = -p.y;
  float rho = length(p);

  if (rho > 1.0) {
    // The atmosphere: a pale halo fading out from the edge.
    float glow = exp(-(rho - 1.0) * 14.0) * 0.6;
    fragColor = vec4(SKY, 1.0) * glow * uOpacity;
    return;
  }

  // Back from the picture to latitude and longitude.
  float c = asin(clamp(rho, 0.0, 1.0));
  float sinc = sin(c);
  float cosc = cos(c);
  float lat = asin(clamp(cosc * sin(uLat0) +
      (rho > 0.0 ? p.y * sinc * cos(uLat0) / rho : 0.0), -1.0, 1.0));
  float lng = uLng0 + atan(p.x * sinc,
      rho * cos(uLat0) * cosc - p.y * sin(uLat0) * sinc);

  vec3 color;
  if (abs(lat) > MAX_LAT) {
    color = vec3(0.94, 0.96, 0.97); // the poles: ice
  } else {
    float u = fract((lng + PI) / (2.0 * PI));
    float v = (1.0 - log(tan(PI / 4.0 + lat / 2.0)) / PI) / 2.0;
    vec4 map = texture(uWorld, vec2(u, v));
    // Ocean where the picture has nothing (a tile that didn't load).
    color = mix(vec3(0.67, 0.83, 0.87), map.rgb, map.a);
  }

  // Sunlight from the top left, a little in front.
  float z = sqrt(max(1.0 - rho * rho, 0.0));
  vec3 normal = vec3(p.x, p.y, z);
  float sun = max(dot(normal, normalize(vec3(-0.45, 0.55, 0.7))), 0.0);
  color *= 0.62 + 0.48 * sun;
  // A glint off the oceans.
  color += vec3(1.0) * pow(sun, 24.0) * 0.12;
  // Haze towards the edge, where we look through more air.
  color = mix(color, SKY, pow(1.0 - z, 2.5) * 0.65);

  fragColor = vec4(color, 1.0) * uOpacity;
}
