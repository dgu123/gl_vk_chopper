/*-----------------------------------------------------------------------
  Copyright (c) 2014-2016, NVIDIA. All rights reserved.
  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions
  are met:
   * Redistributions of source code must retain the above copyright
     notice, this list of conditions and the following disclaimer.
   * Neither the name of its contributors may be used to endorse 
     or promote products derived from this software without specific
     prior written permission.
  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY
  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
  PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
  CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
  OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
-----------------------------------------------------------------------*/

#version 450 core
#extension GL_KHR_vulkan_glsl : require
#extension GL_ARB_shading_language_include : enable

in FS_OUT{
	vec4 pos;
	vec4 wPos;
	vec3 nml;
	vec2 uv;
} vs_in;

struct CameraData{
	mat4 proj_matrix;
	mat4 view_matrix;
	vec4 cameraPosition;
};


layout(std140, binding = 1) uniform cameraBuffer{
	CameraData camera;
};

layout(location = 0) out vec4 out_color;
layout(binding = 2) uniform sampler2D lookup;
layout(binding = 3) uniform samplerCube env;


float cubicLerp(float in0, float in1, float inT){
	float c = (3.0 - 2.0 * inT) * inT * inT;
	return ((1.0 - c) * in0) + (in1 * c);
}

ivec2 offsetUV(ivec2 inUV, float inOffset, int inSize){

	int lVal = (inSize*inUV.y + inUV.x) + int(inOffset);

	ivec2 outV;

	outV.x = lVal % inSize;
	outV.y = lVal / inSize;

	return outV;
}

vec2 offsetUVf(vec2 inUV, float inOffset){

	ivec2 iUV = ivec2(inUV*vec2(1000.0));
	iUV = offsetUV(iUV, inOffset, 1000);

	vec2 outUV = vec2(iUV)*(1.0 / 1000.0);

	return outUV;
}

vec2 rotV2(vec2 inVec, float inAngle){
	vec2 outV;
	float c = cos(inAngle);
	float s = sin(inAngle);
	outV.x = inVec.x * c - inVec.y *s;
	outV.y = inVec.x * s + inVec.y * c;

	return outV;
}

float perlin(vec2 inUV){

	float scl = 16.0;
	int iterations = 3;
	float value = 0.0;

	ivec2 tsize = textureSize(lookup, 0);

	for (int i = 0; i < iterations; ++i){

		vec2 fUV = vec2(tsize*scl) * inUV;

		ivec2 iXY0;
		ivec2 iXY1;
		iXY0.x = (fUV.x <= 0.0) ? int(fUV.x - 1.0) : int(fUV.x);
		iXY1.x = iXY0.x + 1;
		iXY0.y = (fUV.y <= 0.0) ? int(fUV.y - 1.0) : int(fUV.y);
		iXY1.y = iXY0.y + 1;

		float sx = fUV.x - float(iXY0.x);
		float sy = fUV.y - float(iXY0.y);

		ivec2 uv00 = iXY0;
		ivec2 uv10 = ivec2(iXY1.x, iXY0.y);
		ivec2 uv01 = ivec2(iXY0.x, iXY1.y);
		ivec2 uv11 = iXY1;

		float timeValue = camera.cameraPosition.w*scl;

		vec2 v00 = rotV2(texelFetch(lookup, uv00%tsize, 0).xy, timeValue);
		vec2 v10 = rotV2(texelFetch(lookup, uv10%tsize, 0).xy, timeValue);
		vec2 v01 = rotV2(texelFetch(lookup, uv01%tsize, 0).xy, timeValue);
		vec2 v11 = rotV2(texelFetch(lookup, uv11%tsize, 0).xy, timeValue);



		float n0, n1, l0, l1;
		n0 = dot(v00, fUV - vec2(uv00));
		n1 = dot(v10, fUV - vec2(uv10));
		l0 = cubicLerp(n0, n1, sx);

		n0 = dot(v01, fUV - vec2(uv01));
		n1 = dot(v11, fUV - vec2(uv11));
		l1 = cubicLerp(n0, n1, sx);

		value += cubicLerp(l0, l1, sy);// *(1.2 - scl);
		scl *= 0.5;

	}

	return clamp(value * 0.5 + 0.5, 0, 1);

}


void main(){

	vec3 upVector = vec3(0.0, -1.0, 0.0);

	vec3 light_pos = vec3(-100.0, 100.0, 100.0);

	vec3 light_vector = normalize(light_pos - vs_in.wPos.xyz);
	vec3 view_pos = camera.cameraPosition.xyz;
	vec3 view_vector = normalize(view_pos - vs_in.wPos.xyz);

	vec3 pNml = normalize(vs_in.nml.xyz) * vec3(1+(perlin(vs_in.uv*4.0)*0.4));

	float diffuse = clamp(dot(light_vector, (pNml)), 0.1, 1.0);

	float upValue = clamp(pow(-dot(upVector, (pNml)), 32.0), 0.0, 1.0);

	float heightValue = pow(((1.0 / 96.0)*-(vs_in.wPos.y - 60.0)), 2.0);

	vec3 clr2 = vec3(0.0, 0.0, 1.0);

	vec3 ref_vector = 2.0 * dot(pNml, -view_vector) * pNml - view_vector;
	vec3 light_ref_vector = 2.0 * dot(pNml, light_vector) * pNml - light_vector;
	vec4 refColor = texture(env, ref_vector);
	float spec = pow(clamp(dot(light_ref_vector, view_vector), 0.0, 0.7), 3.0);


	const float minFog = 80.0;
	const float maxFog = 360.0;
	float fogRng = maxFog - minFog;

	float pLen = length(vs_in.pos.xyz);
	float fogFactor = clamp((pLen - minFog) / fogRng, 0.0, 0.85);

	vec3 finalColor2 = mix(vec3(0.4,0.5,0.6), refColor.xyz, 0.3)*diffuse+spec;
	vec3 finalColor3 = mix(finalColor2, vec3(1.0),  fogFactor);

	out_color = vec4(finalColor3.xyz, 1.0-fogFactor);
}

