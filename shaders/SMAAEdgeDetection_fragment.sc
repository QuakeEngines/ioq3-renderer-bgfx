$input v_texcoord0, v_texcoord2, v_texcoord3, v_texcoord4

#include <bgfx_shader.sh>

#define SMAA_INCLUDE_VS 0
#define SMAA_INCLUDE_PS 1
#include "SMAA.sh"

SAMPLER2D(s_SmaaColor, 0);

void main()
{
	vec4 offset[3];
	offset[0] = v_texcoord2;
	offset[1] = v_texcoord3;
	offset[2] = v_texcoord4;
#if BGFX_SHADER_LANGUAGE_GLSL
	vec2 rg = SMAALumaEdgeDetectionPS(v_texcoord0, offset, s_SmaaColor);
#else
	vec2 rg = SMAALumaEdgeDetectionPS(v_texcoord0, offset, s_SmaaColor.m_texture);
#endif
	gl_FragColor = vec4(rg.r, rg.g, 0.0, 0.0);
}
