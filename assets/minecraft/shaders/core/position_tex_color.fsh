#version 150

#moj_import <minecraft:dynamictransforms.glsl>
#moj_import <minecraft:projection.glsl>
#moj_import <minecraft:globals.glsl>
#moj_import <minecraft:config.glsl>

const float PI = 3.141592654;

uniform sampler2D Sampler0;

in vec2 texCoord0;
in vec4 vertexColor;
in float isSun;
in vec4 vertex1;
in vec4 vertex2;
in vec4 vertex3;

out vec4 fragColor;

vec2 convertToCubemapUV(vec3 direction) {
	float l = max(max(abs(direction.x), abs(direction.y)), abs(direction.z));
	vec3 dir = direction / l;
	vec3 absDir = abs(dir);
	
	vec2 skyboxUV;
	vec4 backgroundColor;
	if (absDir.x >= absDir.y && absDir.x > absDir.z) {
		if (dir.x < 0) {
			return vec2(0, 0.5) + (dir.zy * vec2(-1, -1) + 1) / 2 / vec2(3, 2);
		} else {
			return vec2(2.0 / 3, 0.5) + (-dir.zy * vec2(-1, 1) + 1) / 2 / vec2(3, 2);
		}
	} else if (absDir.y >= absDir.z) {
		if (dir.y > 0) {
			return vec2(1.0 / 3, 0) + (dir.xz * vec2(1, -1) + 1) / 2 / vec2(3, 2);
		} else {
			return vec2(0, 0) + (-dir.xz * vec2(-1, -1) + 1) / 2 / vec2(3, 2);
		}
	} else {
		if (dir.z < 0) {
			return vec2(1.0 / 3, 0.5) + (-dir.xy * vec2(-1, 1) + 1) / 2 / vec2(3, 2);
		} else {
			return vec2(2.0 / 3, 0) + (dir.xy * vec2(-1, -1) + 1) / 2 / vec2(3, 2);
		}
	}
}

float rayPlane(vec3 rayOrigin, vec3 rayDir, vec3 point, vec3 normal) {
    return dot(point - rayOrigin, normal) / dot(rayDir, normal);
}

void main() {
    if (isSun < 0.5) {
        vec4 color = texture(Sampler0, texCoord0) * vertexColor;
        if (color.a == 0.0) {
            discard;
        }
        fragColor = color * ColorModulator;
        return;
    }
    
    if (gl_PrimitiveID >= 1) {
        discard;
    }

    vec3 pos1 = vertex1.xyz / vertex1.w;
    vec3 pos2 = vertex2.xyz / vertex2.w;
    vec3 pos3 = vertex3.xyz / vertex3.w;
    vec3 center = (pos1 + pos3) * 0.5;
    vec3 pos4 = center + (center - pos1);

    // Remove bobbing from the projection matrix
    mat4 projMat = ProjMat;
    projMat[3].xy = vec2(0.0);

    // Get the fragment position
    vec4 ndcPos = vec4(gl_FragCoord.xy / ScreenSize * 2.0 - 1.0, 0.0, 1.0);
    vec4 temp = inverse(projMat) * ndcPos;
    vec3 viewPos = temp.xyz / temp.w;
    vec3 playerPos = viewPos * mat3(ModelViewMat);
    vec3 rayDir = normalize(playerPos);

    ivec2 texSize = textureSize(Sampler0, 0);
    ivec2 cubemapSize = ivec2(texSize.x, texSize.x / 3 * 2);
    int cubemapCount = texSize.y / cubemapSize.y;
    int sunSize = texSize.y - cubemapCount * (cubemapSize.y + 1);
    vec2 uv = convertToCubemapUV(rayDir);
    ivec2 relativePixelCoord = ivec2(cubemapSize * uv);

    // Figure out which cubemaps to use
    float currentTime = 1.0 - fract(atan(center.x, center.y) / PI * 0.5 + 0.5);

    fragColor = vec4(1.0, 0.0, 1.0, 1.0);
    bool found = false;

    int currentIndex = -1;
    float startTime;
    for (int i = cubemapCount - 1; i >= 0; i--) {
        startTime = texelFetch(Sampler0, ivec2(0, sunSize + (1 + cubemapSize.y) * i), 0).r;
        if (currentTime > startTime) {
            currentIndex = i;
            break;
        }
    }
    float interpolationEndTime;
    if (currentIndex == -1) {
        // We're before the first skybox, use the last one
        currentIndex = cubemapCount - 1;
        startTime = texelFetch(Sampler0, ivec2(0, sunSize + (1 + cubemapSize.y) * currentIndex), 0).r;
        interpolationEndTime = texelFetch(Sampler0, ivec2(1, sunSize + (1 + cubemapSize.y) * currentIndex), 0).r;
        if (interpolationEndTime > startTime) {
            interpolationEndTime -= 1.0;
        }
        startTime -= 1.0;
    } else {
        interpolationEndTime = texelFetch(Sampler0, ivec2(1, sunSize + (1 + cubemapSize.y) * currentIndex), 0).r;
    }

    float interpolationFactor = clamp((currentTime - startTime) / (interpolationEndTime - startTime), 0.0, 1.0);

    int previousIndex = (currentIndex - 1 + cubemapCount) % cubemapCount;
    ivec2 previousBaseCoord = ivec2(0, sunSize + (1 + cubemapSize.y) * previousIndex + 1);
    ivec2 currentBaseCoord =  ivec2(0, sunSize + (1 + cubemapSize.y) * currentIndex + 1);
    vec3 previousValue = texelFetch(Sampler0, previousBaseCoord + relativePixelCoord, 0).rgb;
    vec3 currentValue =  texelFetch(Sampler0,  currentBaseCoord + relativePixelCoord, 0).rgb;
    fragColor.rgb = mix(previousValue, currentValue, clamp(interpolationFactor, 0.0, 1.0));

    // Raytrace the original sun
    vec3 normal = normalize(cross(pos1 - pos2, pos3 - pos2));
    float t = rayPlane(vec3(0.0), rayDir, center, normal);
    if (t > 0.0) {
        vec3 hitPos = rayDir * t;
        vec3 sideX = pos3 - pos2;
        vec3 sideY = pos1 - pos2;
        vec2 uv = vec2(
            dot(hitPos - pos2, sideX) / dot(sideX, sideX),
            dot(hitPos - pos2, sideY) / dot(sideY, sideY)
        );
        if (clamp(uv, 0.0, 1.0) == uv) {
            // Draw the sun
            fragColor.rgb += texelFetch(Sampler0, ivec2(uv * sunSize), 0).rgb;
        }
    }

    // Moon should be solid, raytrace it as well
    normal *= -1;
    center *= -1;
    t = rayPlane(vec3(0.0), rayDir, center, normal);
    if (t > 0.0) {
        vec3 hitPos = rayDir * t;
        vec3 sideX = -pos3 + pos2;
        vec3 sideY = -pos1 + pos2;
        vec2 uv = vec2(
            dot(hitPos + pos2, sideX) / dot(sideX, sideX),
            dot(hitPos + pos2, sideY) / dot(sideY, sideY)
        );
        uv = (uv - 0.5) / (2.0 / 3.0) + 0.5;
        // Rotate the uv to match up with the actual moon
        uv = uv * vec2(-1.0, -1.0) + vec2(1.0, 1.0);
        if (clamp(uv, 0.0, 1.0) == uv) {
            // Check if the moon is solid at this position
            vec4 moonColor = texelFetch(Sampler0, ivec2(uv * sunSize) + ivec2(sunSize, 0), 0);
            if (moonColor.a < 0.1) {
                // Not solid
                return;
            }

            vec3 ambientColor = vec3(0.0);
            if (AVERAGE_MOON_LIGHTING) {
                // Set background to average around this area
                for (int x = -5; x <= 5; x++) {
                    for (int y = -5; y <= 5; y++) {
                        vec3 pos = hitPos + sideX * x * 0.3 / 5.0 + sideY * y * 0.3 / 5.0;
                        vec2 uv = convertToCubemapUV(normalize(pos));
                        ivec2 relativePixelCoord = ivec2(cubemapSize * uv);
                        vec3 previousValue = texelFetch(Sampler0, previousBaseCoord + relativePixelCoord, 0).rgb;
                        vec3 currentValue =  texelFetch(Sampler0,  currentBaseCoord + relativePixelCoord, 0).rgb;
                        ambientColor += mix(previousValue, currentValue, clamp(interpolationFactor, 0.0, 1.0));
                    }
                }
                ambientColor /= 11 * 11;
            } 
            fragColor = vec4(ambientColor, 1.0);
        }
    }
}
