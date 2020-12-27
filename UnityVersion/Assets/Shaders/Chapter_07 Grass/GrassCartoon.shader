// ****************************************************************************************
// ************************************* 草地着色器 ****************************************
// ****************************************************************************************

Shader "GPU Gems/Chapter_07 Grass/GrassCartoon"
{
    Properties
    {
        [Header(Shading)]
        [Space]
        _TopColor("Grass Top Color", Color) = (1, 1, 1, 1)                      // 草的顶部颜色.
        _BottomColor("Grass Bottom Color", Color) = (1, 1, 1, 1)                // 草的底部颜色.
        _TranslucentGain("Translucent Gain", Range(0, 1)) = 0.5                 // 用于控制草地的明暗程度.
        _TessellationUniform("Tessellation Uniform", Range(1, 64)) = 5          // 曲面细分程度.

        [Header(Blades)]
        [Space]
        _BladeWidth("Blade Width", Float) = 0.05                                // 草叶片的宽度.
        _BladeWidthWidthRandom("Blade Width Random", Float) = 0.02              // 宽度随机的范围.
        _BladeHeight("Blade Height", Float) = 0.5                               // 草叶片的高度.
        _BladeHeightWidthRandom("Blade Height Random", Float) = 0.3             // 高度的随机范围.
        _BladeForward("Blade Forward Amount", Float) = 0.38                     // 草地的朝向, 越小草越直.
        _BladeCurve("Blade Curvature Amount", Range(1, 4)) = 2                  // 一根草细分的段数.
        _BendRotationRandom("Bend Rotation Random", Range(0, 1)) = 0.2          // 草地旋转的随机程度.

        [Header(Wind)]
        [Space]
        _WindDistortionMap("Wind Distortion Map", 2D) = "white" {}              // 模拟风向的噪声纹理.
        _WindStrength("Wind Strength", Float) = 1                               // 风力强度.
        _WindFrequency("Wind Frequency",  Vector) = (0.05, 0.05, 0, 0)          // 风速.
    }

    CGINCLUDE

    #include "UnityCG.cginc"
    #include "AutoLight.cginc"
    #include "Tessellation.cginc"

    // 几何着色器输出, 在这里分为前向渲染和阴影渲染两个版本, 存储的数据不一样.
    struct geometryOutput
    {
        float4 pos : SV_POSITION;

    #if UNITY_PASS_FORWARDBASE
        float3 normal : NORMAL;
        float2 uv : TEXCOORD0;
        SHADOW_COORDS(1)
    #endif
    };

	// 简单的 Shader 随机数功能, 参考 http://answers.unity.com/answers/624136/view.html
	// 更多的讨论可以参考如下链接:
	// https://forum.unity.com/threads/am-i-over-complicating-this-random-function.454887/#post-2949326
	// 返回值是 [0, 1].
    float rand(float3 co)
    {
        return frac(sin(dot(co.xyz, float3(12.9898, 78.233, 53.539))) * 43758.5453);
    }

    // 构建绕任意轴旋转的矩阵, 参考 https://gist.github.com/keijiro/ee439d5e7388f3aafc5296005c8c3f33
    float3x3 AngleAxis3x3(float angle, float3 axis)
    {
        float c, s;
        sincos(angle, s, c);

        float t = 1 - c;
        float x = axis.x;
        float y = axis.y;
        float z = axis.z;

	    return float3x3
        (
			t * x * x + c, t * x * y - s * z, t * x * z + s * y,
			t * x * y + s * z, t * y * y + c, t * y * z - s * x,
			t * x * z - s * y, t * y * z + s * x, t * z * z + c
		);
    }

	// 几何着色器的核心工作.
	// 1. 世界坐标 --> 投影空间坐标.
	// 2. 模型空间法线 --> 世界空间法线.
	// 3. UV 传递.
	// 4. 阴影坐标计算.
    geometryOutput VertexOutput(float3 localPos, float3 normal, float2 uv)
    {
        geometryOutput o;
        o.pos = UnityObjectToClipPos(localPos);

    #if UNITY_PASS_FORWARDBASE
        o.normal = UnityObjectToWorldNormal(normal);
        o.uv = uv;

        TRANSFER_SHADOW(o);
    #elif UNITY_PASS_SHADOWCASTER
        // 相关细节参考 https://catlikecoding.com/unity/tutorials/rendering/part-7/
        o.pos = UnityApplyLinearShadowBias(o.pos);
    #endif

        return o;
    }

    // 计算草地顶点的位置, 在这里草地位置是在切线空间中计算.
    geometryOutput GenerateGrassVertex(float3 vertexPostion, float width, float height, 
        float forward, float2 uv, float3x3 transformMatrix)
    {
        float3 tangentPoint = float3(width, forward, height);
        float3 tangnetNormal = normalize(float3(0, -1, forward));

        float3 localPosition = vertexPostion + mul(transformMatrix, tangentPoint);
        float3 localNormal = mul(transformMatrix, tangnetNormal);

        return VertexOutput(localPosition, localNormal, uv);
    }

    float _BladeHeight;
	float _BladeHeightRandom;

	float _BladeWidthRandom;
	float _BladeWidth;

	float _BladeForward;
	float _BladeCurve;

	float _BendRotationRandom;

	sampler2D _WindDistortionMap;
	float4 _WindDistortionMap_ST;

	float _WindStrength;
	float2 _WindFrequency;

    // 草地分段的数量, 分段越多则代表草地的结构越精细.
	#define BLADE_SEGMENTS 3

    [maxvertexcount(BLADE_SEGMENTS * 2 + 1)]
    void geo(triangle vertexOutput IN[3], inout TriangleStream<geometryOutput> triStream)
    {
        float3 pos = IN[0].vertex.xyz;

        float3x3 facingRotationMatrix = AngleAxis3x3(rand(pos) * UNITY_TWO_PI, float3(0, 0, 1));		

		// 沿着草表面朝向弯曲, _BendRotationRandom 越大草的弯曲程度越大.
		float3x3 bendRotationMatrix = AngleAxis3x3(rand(pos.zzx) * _BendRotationRandom * UNITY_PI * 0.5, float3(-1, 0, 0));		

		// 对风向的扰动图进行采样, 得到较为分散随机的风.
		// 其中 _WindDistortionMap_ST 调整凌乱随机程度.
		// _WindFrequency 调整风速.
		// _WindStrength 调整风力.
		float2 uv = pos.xz * _WindDistortionMap_ST.xy + _WindDistortionMap_ST.zw + _WindFrequency * _Time.y;
		float2 windSample = (tex2Dlod(_WindDistortionMap, float4(uv, 0, 0)).xy * 2 - 1) * _WindStrength;
		float3 wind = normalize(float3(windSample.x, windSample.y, 0));

		// 最后获得风向变换的矩阵.
		float3x3 windRotation = AngleAxis3x3(UNITY_PI / 4 * windSample, wind);
		//float3x3 windRotation = AngleAxis3x3(0, wind);

		float3 vNormal = IN[0].normal;
		float4 vTangent = IN[0].tangent;
		float3 vBinormal = cross(vNormal, vTangent) * vTangent.w;

		float3x3 tangentToLocal = float3x3
		(
			vTangent.x, vBinormal.x, vNormal.x,
			vTangent.y, vBinormal.y, vNormal.y,
			vTangent.z, vBinormal.z, vNormal.z
		);

		// 先对切线空间的顶点进行风向变化, 然后变换到本地空间, 然后对顶点进行轴旋转, 最后再完成草地弯曲.
		// 矩阵乘法要严格按照 SRT 的顺序进行, 否则效果会错误.
		float3x3 transformationMatrix = mul(mul(mul(tangentToLocal, windRotation), facingRotationMatrix), bendRotationMatrix);

		// 对于最底部的顶点, 不需要风向和弯曲变换, 因为草地肯定时扎根地下不动的.
		float3x3 transformationMatrixFacing = mul(tangentToLocal, facingRotationMatrix);

		// 随机草的高度、宽度以及朝向.
		float height = (rand(pos.zyx) * 2 - 1) * _BladeHeightRandom + _BladeHeight;
		float width = (rand(pos.xzy) * 2 - 1) * _BladeWidthRandom + _BladeWidth;
		float forward = rand(pos.yyz) * _BladeForward;

		for (int i = 0; i < BLADE_SEGMENTS; i++)
		{
			float t = i / (float)BLADE_SEGMENTS;

			float segmentHeight = height * t;
			float segmentWidth = width * (1 - t);
			float segmentForward = pow(t, _BladeCurve) * forward;

			float3x3 transformMatrix = i == 0 ? transformationMatrixFacing : transformationMatrix;

			triStream.Append(GenerateGrassVertex(pos, segmentWidth, segmentHeight, segmentForward, float2(0, t), transformMatrix));
			triStream.Append(GenerateGrassVertex(pos, -segmentWidth, segmentHeight, segmentForward, float2(1, t), transformMatrix));
		}

		triStream.Append(GenerateGrassVertex(pos, 0, height, forward, float2(0.5, 1), transformationMatrix));
    }
    ENDCG

    SubShader
    {
		Cull Off

        Pass
        {
			Tags { "RenderType" = "Opaque" "LightMode" = "ForwardBase" }

            CGPROGRAM
            #pragma vertex vert
			#pragma geometry geo
            #pragma fragment frag
			#pragma hull hull
			#pragma domain domain
			#pragma target 4.6					// 曲面细分必须在 Shader Model 4.6 之后才有.
			#pragma multi_compile_fwdbase
            
			#include "Lighting.cginc"

			float4 _TopColor;
			float4 _BottomColor;
			float _TranslucentGain;

			float4 frag (geometryOutput i,  fixed facing : VFACE) : SV_Target
            {			
				float3 normal = facing > 0 ? i.normal : -i.normal;

				float shadow = SHADOW_ATTENUATION(i);
				float NdotL = saturate(saturate(dot(normal, _WorldSpaceLightPos0)) + _TranslucentGain) * shadow;

				float3 ambient = UNITY_LIGHTMODEL_AMBIENT.rgb;
				float4 lightIntensity = NdotL * _LightColor0 + float4(ambient, 1);
                float4 col = lerp(_BottomColor, _TopColor * lightIntensity, i.uv.y);

				return col;
            }
            ENDCG
        }

		Pass
		{
			Tags { "LightMode" = "ShadowCaster" }

			CGPROGRAM
			#pragma vertex vert
			#pragma geometry geo
			#pragma fragment frag
			#pragma hull hull
			#pragma domain domain
			#pragma target 4.6
			#pragma multi_compile_shadowcaster

			float4 frag(geometryOutput i) : SV_Target
			{
				SHADOW_CASTER_FRAGMENT(i)
			}

			ENDCG
		}
    }
}
