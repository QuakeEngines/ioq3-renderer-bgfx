BASE_PATH = path.getabsolute(".")

newaction
{
	trigger = "shaders",
	description = "Compile shaders",
	
	onStart = function()
		-- No bitwise and in Lua 5.1
		-- https://stackoverflow.com/questions/5977654/lua-bitwise-logical-operations
		function isBitSet(a, b)
			local p,c=1,0
			while a>0 and b>0 do
				local ra,rb=a%2,b%2
				if ra+rb>1 then c=c+p end
				a,b,p=(a-ra)/2,(b-rb)/2,p*2
			end
			return c ~= 0
		end
		
		-- { name, { variantName, variantDefines } }
		-- becomes
		-- { name, variant1Name, variant1Defines }
		-- { name, variant2Name, variant2Defines }
		-- { name, variant1Name .. variant2Name, variant1Defines .. ";" .. variant2Defines }
		-- etc. for all variant combinations/permutations.
		function expandShaderVariants(shaders)
			local expandedShaders = {}
			local index = 1
		
			for _,shader in pairs(shaders) do
				expandedShaders[index] = { shader[1] }
				index = index + 1
				local variants = shader[2]
			
				if variants ~= nil then
					local n = #variants
				
					for i=0,2^n-1 do
						local concatVariant = ""
						local concatDefines = ""
					
						for vi,variant in ipairs(variants) do
							if isBitSet(i, 2^(vi-1)) then
								concatVariant = concatVariant .. variant[1]
								
								if concatDefines ~= "" then
									concatDefines = concatDefines .. ";"
								end
								
								concatDefines = concatDefines .. variant[2]
							end
						end
						
						if concatVariant ~= "" then
							expandedShaders[index] = { shader[1], concatVariant, concatDefines }
							index = index + 1
						end
					end
				end
			end
			
			return expandedShaders
		end
	
		-- Compile an individual shader for each renderer, appending the output to a file.
		function compileShader(input, type, variant, defines, outputFilename, renderers)
			local tempOutputFilename = path.join(BASE_PATH, "build", "tempoutput")
			io.write("Compiling " .. input .. "_" .. type)
			
			if variant == nil then
				io.write("\n")
			else
				io.write(" " .. variant .. "\n")
			end
			io.flush()
			
			local inputFilename = string.format(path.join(BASE_PATH, "shaders/%s_%s.sc"), input, type)
			local includePaths = path.join(BASE_PATH, "shaders") .. ";" .. path.join(BASE_PATH, "code/bgfx/src")
			local varyingPath = path.join(BASE_PATH, "shaders/varying.def.sc")
			
			-- Compile the shader for all renderers.
			for _,renderer in pairs(renderers) do
				local command = nil
				
				if os.ishost("windows") then
					command = path.join(BASE_PATH, "bin/shaderc.exe")
				elseif os.ishost("linux") then
					command = path.join(BASE_PATH, "bin/shaderc64")
				end
				
				local variableName = input .. "_"

				if variant ~= nil then
					variableName = variableName .. variant .. "_"
				end

				variableName = variableName .. type .. "_" .. renderer
				
				command = command .. string.format(" -i \"%s\" -f \"%s\" -o \"%s\" --varyingdef %s --bin2c \"%s\" --type %s", includePaths, inputFilename, tempOutputFilename, varyingPath, variableName, type)
			
				if defines ~= nil then
					command = command .. " --define \"" .. defines .. "\""
				end
				
				if renderer == "gl" then
					command = command .. " --platform linux -p 130"
				elseif renderer == "d3d9" or renderer == "d3d11" then
					command = command .. " --platform windows"
				
					if type == "fragment" then
						command = command .. " -p ps_"
					else
						command = command .. " -p vs_"
					end
				
					if renderer == "d3d9" then
						command = command .. "3_0"
					elseif renderer == "d3d11" then
						command = command .. "5_0"
					end
					
					command = command .. " -O 3"
				elseif renderer == "vk" then
					command = command .. " --platform linux -p spirv"
				end
				
				if not os.execute(command) then
					local message = "\n" .. input .. " " .. type
					
					if variant ~= nil then
						message = message .. " " .. variant
					end
					
					message = message .. " " .. renderer .. "\n" .. command
					error(message)
				end
				
				-- Append the temp output file to the real output file.
				local tempFile = io.open(tempOutputFilename, "r")
				local tempContent = tempFile:read("*all")
				tempFile:close()
				local outputFile = io.open(outputFilename, "a")
				outputFile:write("\n")
				outputFile:write(tempContent)
				outputFile:close()
			end
		end
		
		local renderers = nil
		
		if os.ishost("windows") then
			renderers = { "gl", "d3d11", "vk" }
		else
			renderers = { "gl", "vk" }
		end
		
		local depthFragmentVariants =
		{
			{ "AlphaTest", "USE_ALPHA_TEST" }
		}
		
		local depthVertexVariants =
		{
			{ "AlphaTest", "USE_ALPHA_TEST" }
		}
		
		local fogFragmentVariants =
		{
			{ "Bloom", "USE_BLOOM" }
		}
		
		local genericFragmentVariants =
		{
			{ "AlphaTest", "USE_ALPHA_TEST" },
			{ "Bloom", "USE_BLOOM" },
			{ "DynamicLights", "USE_DYNAMIC_LIGHTS" },
			{ "SoftSprite", "USE_SOFT_SPRITE" },
			{ "SunLight", "USE_SUN_LIGHT" }
		}
		
		local genericVertexVariants =
		{
			{ "SunLight", "USE_SUN_LIGHT" }
		}
		
		local textureVariationFragmentVariants =
		{
			{ "Bloom", "USE_BLOOM" },
			{ "SunLight", "USE_SUN_LIGHT" }
		}
		
		local fragmentShaders =
		{
			{ "Bloom" },
			{ "Color" },
			{ "Depth", depthFragmentVariants },
			{ "Fog", fogFragmentVariants },
			{ "GaussianBlur" },
			{ "Generic", genericFragmentVariants },
			{ "SMAABlendingWeightCalculation" },
			{ "SMAAEdgeDetection" },
			{ "SMAANeighborhoodBlending" },
			{ "Texture" },
			{ "TextureColor" },
			{ "TextureDebug" },
			{ "TextureVariation", textureVariationFragmentVariants }
		}
		
		local vertexShaders =
		{
			{ "Color" },
			{ "Depth", depthVertexVariants },
			{ "Fog" },
			{ "Generic", genericVertexVariants },
			{ "SMAABlendingWeightCalculation" },
			{ "SMAAEdgeDetection" },
			{ "SMAANeighborhoodBlending" },
			{ "Texture" }
		}
		
		-- Make sure the build directory exists
		os.mkdir(path.join(BASE_PATH, "build"))
		
		-- Delete the output files.
		local outputSourceFilename = path.join(BASE_PATH, "shaders_bin/Shader.cpp")
		local outputHeaderFilename = path.join(BASE_PATH, "shaders_bin/Shader.h")
		os.remove(outputSourceFilename)
		os.remove(outputHeaderFilename)
		for _,v in pairs(fragmentShaders) do
			os.remove(path.join(BASE_PATH, "shaders_bin", v[1] .. "_fragment.h"))
		end
		for _,v in pairs(vertexShaders) do
			os.remove(path.join(BASE_PATH, "shaders_bin", v[1] .. "_vertex.h"))
		end
		
		-- Expand shader lists so each variant has a single entry.
		local expandedFragmentShaders = expandShaderVariants(fragmentShaders)
		local expandedVertexShaders = expandShaderVariants(vertexShaders)

		-- Compile the shaders.
		local ok, message = pcall(function()
			for _,v in pairs(expandedFragmentShaders) do
				compileShader(v[1], "fragment", v[2], v[3], path.join(BASE_PATH, "shaders_bin", v[1] .. "_fragment.h"), renderers)
			end
			
			for _,v in pairs(expandedVertexShaders) do
				compileShader(v[1], "vertex", v[2], v[3], path.join(BASE_PATH, "shaders_bin", v[1] .. "_vertex.h"), renderers)
			end
		end)
		
		if not ok then
			print(message)
			return
		end
		
		-- Generate shader ID and variant enums, writing them to the output header file.
		function writeShaderIds(of, data, enumName, stringsVarName)
			of:write("struct " .. enumName .. "\n")
			of:write("{\n")
			of:write("\tenum Enum\n")
			of:write("\t{\n")
			
			for _,v in pairs(data) do
				of:write("\t\t" .. v[1])
				
				if v[2] ~= nil then
					of:write("_" .. v[2])
				end
				
				of:write(",\n")
			end
			
			of:write("\t\tNum\n")
			of:write("\t};\n")
			of:write("};\n\n")
			
			of:write("#ifdef _DEBUG\n")
			of:write("static const char *" .. stringsVarName .. "[] =\n")
			of:write("{\n")
			
			for _,v in pairs(data) do
				of:write("\t\"" .. v[1])
				
				if v[2] ~= nil then
					of:write("_" .. v[2])
				end
				
				of:write("\",\n")
			end
			
			of:write("};\n")
			of:write("#endif\n\n")
		end
		
		function writeShaderVariantEnum(of, data, name)
			of:write("struct " .. name .. "ShaderVariant\n")
			of:write("{\n")
			of:write("\tenum\n")
			of:write("\t{\n")
			local i = 0
			
			for _,v in pairs(data) do
				of:write(string.format("\t\t%s = 1 << %d,\n", v[1], i))
				i = i + 1
			end
			
			of:write(string.format("\t\tNum = 1 << %d\n", i))
			of:write("\t};\n")
			of:write("};\n\n")
		end
		
		local outputHeaderFile = io.open(outputHeaderFilename, "w")
		writeShaderIds(outputHeaderFile, expandedFragmentShaders, "FragmentShaderId", "s_fragmentShaderNames")
		writeShaderIds(outputHeaderFile, expandedVertexShaders, "VertexShaderId", "s_vertexShaderNames")
		writeShaderVariantEnum(outputHeaderFile, genericFragmentVariants, "GenericFragment")
		writeShaderVariantEnum(outputHeaderFile, depthFragmentVariants, "DepthFragment")
		writeShaderVariantEnum(outputHeaderFile, depthVertexVariants, "DepthVertex")
		writeShaderVariantEnum(outputHeaderFile, fogFragmentVariants, "FogFragment")
		writeShaderVariantEnum(outputHeaderFile, textureVariationFragmentVariants, "TextureVariationFragment")
		outputHeaderFile:close()

		-- Generate functions to map shader ID enums to source strings, appending them to the output source file.
		function writeSourceMap(of, data, renderer, name, nameLower)
			of:write(string.format("\nstatic std::array<ShaderSourceMem, %sShaderId::Num> Get%sShaderSourceMap_%s()\n", name, name, renderer))
			of:write("{\n")
			of:write(string.format("\tstd::array<ShaderSourceMem, %sShaderId::Num> mem;\n", name))
			
			for _,v in pairs(data) do
				local id = v[1]
				
				if v[2] ~= nil then
					id = id .. "_" .. v[2]
				end
			
				local source = string.format("%s_%s_%s", id, nameLower, renderer)
				of:write(string.format("\tmem[%sShaderId::%s].mem = %s;\n", name, id, source))
				of:write(string.format("\tmem[%sShaderId::%s].size = sizeof(%s);\n", name, id, source))
			end
			
			of:write("\treturn mem;\n")
			of:write("}\n")
		end
		
		local outputSourceFile = io.open(outputSourceFilename, "w")
		for _,v in pairs(fragmentShaders) do
			outputSourceFile:write("#include \"" .. v[1] .. "_fragment.h\"\n")
		end
		for _,v in pairs(vertexShaders) do
			outputSourceFile:write("#include \"" .. v[1] .. "_vertex.h\"\n")
		end
		outputSourceFile:write("\nstruct ShaderSourceMem { const uint8_t *mem; size_t size; };\n");
		
		for _,renderer in pairs(renderers) do
			writeSourceMap(outputSourceFile, expandedFragmentShaders, renderer, "Fragment", "fragment")
			writeSourceMap(outputSourceFile, expandedVertexShaders, renderer, "Vertex", "vertex")
		end
		
		outputSourceFile:close()
		
		print("Done.")
    end,
}

newoption
{
	trigger = "mingw",
	value = "VALUE",
	description = "MinGW variety",
	allowed =
	{
		{ "mingw", "MinGW or mingw32" },
		{ "mingw-pc", "MinGW-w64" },
		{ "mingw-w64", "MinGW-w64" }
	}
}

newoption
{
	trigger = "engine",
	value = "VALUE",
	description = "Target engine",
	allowed =
	{
		{ "ioq3", "ioquake3" },
		{ "iortcw", "iortcw" }
	}
}

if _ACTION == nil then
	return
end

if not _OPTIONS["mingw"] then
	_OPTIONS["mingw"] = "mingw-w64"
end

if not _OPTIONS["engine"] then
	_OPTIONS["engine"] = "ioq3"
end

local IOQ3_PATH = path.join(path.getabsolute(".."), "ioq3")
local IORTCW_PATH = path.join(path.getabsolute(".."), "iortcw")

if os.ishost("windows") then
	if _OPTIONS["engine"] == "ioq3" and not os.isdir(IOQ3_PATH) then
		print("ioquake3 not found at " .. IOQ3_PATH)
		os.exit()
	elseif _OPTIONS["engine"] == "iortcw" and not os.isdir(IORTCW_PATH) then
		print("iortcw not found at " .. IORTCW_PATH)
		os.exit()
	end
end

solution "renderer_bgfx"
	configurations { "Release", "Debug" }
	location "build"
	
	if os.is64bit() and not os.ishost("windows") then
		platforms { "x86_64", "x86" }
	else
		platforms { "x86", "x86_64" }
	end
		
	startproject "renderer_bgfx"
	
	configuration "platforms:x86"
		architecture "x86"
		
	configuration "platforms:x86_64"
		architecture "x86_64"
	
	configuration "Debug"
		optimize "Debug"
		defines { "_DEBUG" }
		symbols "On"
		
	configuration { "Debug", "x86" }
		targetdir "build/bin_x86_debug"
		
	configuration { "Debug", "x86_64" }
		targetdir "build/bin_x64_debug"
		
	configuration "Release"
		optimize "Full"
		defines "NDEBUG"
		
	configuration { "Release", "x86" }
		targetdir "build/bin_x86"
		
	configuration { "Release", "x86_64" }
		targetdir "build/bin_x64"
		
	configuration "vs*"
		defines { "_CRT_SECURE_NO_DEPRECATE" }
		
	configuration { "vs*", "x86_64" }
		defines { "_WIN64", "__WIN64__" }
		
dofile("renderer_bgfx.lua")
rendererProject(_OPTIONS["engine"], path.getabsolute("."))

if os.ishost("windows") then
	if _OPTIONS["engine"] == "ioq3" then
		includedirs(path.join(IOQ3_PATH, "code/SDL2/include"))
		configuration "x86"
			links(path.join(IOQ3_PATH, "code/libs/win32/libSDL2"))
		configuration "x86_64"
			links(path.join(IOQ3_PATH, "code/libs/win64/libSDL264"))
	elseif _OPTIONS["engine"] == "iortcw" then
		includedirs(path.join(IORTCW_PATH, "SP/code/SDL2/include"))
		configuration "x86"
			links(path.join(IORTCW_PATH, "SP/code/libs/win32/libSDL2"))
		configuration "x86_64"
			links(path.join(IORTCW_PATH, "SP/code/libs/win64/libSDL264"))
	end
end
