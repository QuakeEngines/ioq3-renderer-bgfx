/*
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of Quake III Arena source code.

Quake III Arena source code is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the License,
or (at your option) any later version.

Quake III Arena source code is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Quake III Arena source code; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
*/
#include "Precompiled.h"
#pragma hdrstop

namespace renderer {
namespace meta {

struct Meta
{
	Material *bfgExplosionMaterial = nullptr;
	Model *bfgMissibleModel = nullptr;
	Material *plasmaBallMaterial = nullptr;
	Material *plasmaExplosionMaterial = nullptr;
};

static Meta s_meta;

static const char *s_reflectiveMaterialNames[] =
{
	"textures/liquids/clear_ripple1",
	"textures/liquids/calm_poollight",
	"textures/liquids/clear_calm1"
};

void Initialize()
{
	s_meta = Meta();
}

static float CalculateExplosionLight(float entityShaderTime, float durationMilliseconds)
{
	// From CG_AddExplosion
	float light = (main::GetFloatTime() - entityShaderTime) / (durationMilliseconds / 1000.0f);

	if (light < 0.5f)
		return 1.0f;

	return 1.0f - (light - 0.5f) * 2.0f;
}

void OnEntityAddedToScene(const Entity &entity, bool isWorldScene)
{
	if (!isWorldScene)
		return;

	// Hack in extra dlights for Quake 3 content.
	const vec3 bfgColor = util::ToLinear(vec3(0.08f, 1.0f, 0.4f));
	const vec3 lightningColor = util::ToLinear(vec3(0.6f, 0.6f, 1));
	const vec3 plasmaColor = util::ToLinear(vec3(0.6f, 0.6f, 1.0f));
	DynamicLight dl;
	dl.color_radius = vec4::empty;
	dl.position_type = vec4(entity.e.origin, DynamicLight::Point);

	// BFG projectile.
	if (entity.e.reType == RT_MODEL && s_meta.bfgMissibleModel && entity.e.hModel == s_meta.bfgMissibleModel->getIndex())
	{
		dl.color_radius = vec4(bfgColor, 200); // Same radius as rocket.
	}
	// BFG explosion.
	else if (entity.e.reType == RT_SPRITE && s_meta.bfgExplosionMaterial && entity.e.customShader == s_meta.bfgExplosionMaterial->index)
	{
		dl.color_radius = vec4(bfgColor, 300 * CalculateExplosionLight(entity.e.shaderTime, 1000)); // Same radius and duration as rocket explosion.
	}
	// Lightning bolt.
	else if (entity.e.reType == RT_LIGHTNING)
	{
		const float base = 1;
		const float amplitude = 0.1f;
		const float phase = 0;
		const float freq = 10.1f;
		const float radius = base + g_sinTable[ri.ftol((phase + main::GetFloatTime() * freq) * g_funcTableSize) & g_funcTableMask] * amplitude;
		dl.capsuleEnd = vec3(entity.e.oldorigin);
		dl.color_radius = vec4(lightningColor, 200 * radius);
		dl.position_type.w = DynamicLight::Capsule;
	}
	// Plasma ball.
	else if (entity.e.reType == RT_SPRITE && s_meta.plasmaBallMaterial && entity.e.customShader == s_meta.plasmaBallMaterial->index)
	{
		dl.color_radius = vec4(plasmaColor, 150);
	}
	// Plasma explosion.
	else if (entity.e.reType == RT_MODEL && s_meta.plasmaExplosionMaterial && entity.e.customShader == s_meta.plasmaExplosionMaterial->index)
	{
		dl.color_radius = vec4(plasmaColor, 200 * CalculateExplosionLight(entity.e.shaderTime, 600)); // CG_MissileHitWall: 600ms duration.
	}
	// Rail core.
	else if (entity.e.reType == RT_RAIL_CORE)
	{
		dl.capsuleEnd = vec3(entity.e.oldorigin);
		dl.color_radius = vec4(util::ToLinear(vec4::fromBytes(entity.e.shaderRGBA).xyz()), 200);
		dl.position_type.w = DynamicLight::Capsule;
	}

	if (dl.color_radius.a > 0)
	{
		main::AddDynamicLightToScene(dl);
	}
}

void OnMaterialCreate(Material *material)
{
	if (!util::Stricmp(material->name, "bfgExplosion"))
	{
		s_meta.bfgExplosionMaterial = material;
	}
	else if (!util::Stricmp(material->name, "sprites/plasma1"))
	{
		s_meta.plasmaBallMaterial = material;
	}
	else if (!util::Stricmp(material->name, "plasmaExplosion"))
	{
		s_meta.plasmaExplosionMaterial = material;
	}

	for (int i = 0; i < Material::maxStages; i++)
	{
		MaterialStage &stage = material->stages[i];

		if (!stage.active)
			break;

		for (int j = 0; j < MaterialTextureBundle::maxImageAnimations; j++)
		{
			const Texture *texture = stage.bundles[MaterialTextureBundleIndex::DiffuseMap].textures[j];

			if (!texture)
				break;

			if (!util::Stricmp(texture->getName(), "textures/sfx/fireswirl2blue.tga"))
			{
				stage.emissiveLight = 2;
				break;
			}
		}
	}

	if (g_cvars.waterReflections->integer)
	{
		for (size_t i = 0; i < BX_COUNTOF(s_reflectiveMaterialNames); i++)
		{
			if (util::Stricmp(material->name, s_reflectiveMaterialNames[i]) != 0)
				continue;

			// Use the existing material as the reflective back side, i.e. what you see when under the water plane.
			material->cullType = MaterialCullType::BackSided;
			material->reflective = MaterialReflective::BackSide;

			// Create a copy of this material to use for the reflective front side, i.e. what you see when above the water plane - the surface that displays the reflection.
			// Insert a reflection stage at index 0.
			Material reflection = *material;
			util::Strncpyz(reflection.name, util::VarArgs("%s/reflection", material->name), sizeof(reflection.name));
			reflection.cullType = MaterialCullType::FrontSided;
			reflection.reflective = MaterialReflective::FrontSide;

			for (int i = Material::maxStages - 1; i > 0; i--)
			{
				MaterialStage *stage = &reflection.stages[i];
				MaterialStage *prevStage = &reflection.stages[i - 1];

				if (prevStage->active)
					*stage = *prevStage;
			}

			MaterialStage *stage = &reflection.stages[0];
			*stage = MaterialStage();
			stage->active = true;
			stage->bundles[0].textures[0] = Texture::find("*reflection");
			stage->bundles[0].tcGen = MaterialTexCoordGen::Fragment;
			stage->blendSrc = BGFX_STATE_BLEND_SRC_ALPHA;
			stage->blendDst = BGFX_STATE_BLEND_INV_SRC_ALPHA;
			stage->rgbGen = MaterialColorGen::Identity;
			stage->alphaGen = MaterialAlphaGen::Water;
			material->reflectiveFrontSideMaterial = g_materialCache->createMaterial(reflection);
		}
	}
}

void OnModelCreate(Model *model)
{
	if (!util::Stricmp(model->getName(), "models/weaphits/bfg.md3"))
	{
		s_meta.bfgMissibleModel = model;
	}
}

} // namespace meta
} // namespace renderer