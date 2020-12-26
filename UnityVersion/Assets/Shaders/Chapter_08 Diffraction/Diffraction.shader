Shader "GPU Gems/Chapter_08 Diffraction/Diffraction"
{
    Properties
    {
        _Color("Color", Color) = (1, 1, 1, 1)
        _RoughX("Rough X", Range(0, 1)) = 0.5               // 颜色发散的程度, 越大颜色越深.
        _SpacingX("Spacing X", Range(0.5, 1)) = 0.7         // 越大越接近红光, 越小越接近紫光.
    }
    SubShader
    {
        Pass
        {
            Tags { "RenderType" = "Opaque" "LightMode" = "ForwardBase" }

            CGPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_fwdbase
            
            #include "Lighting.cginc"
            #include "UnityCG.cginc"

            fixed4 _Color;
            half _RoughX;
            half _SpacingX;

            struct a2v
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
                float2 texcoord : TEXCOORD0;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float4 color : COLOR;
            };

            fixed3 Blend3(fixed3 x)
            {
                fixed3 y = 1 - x * x;
                y = max(y, fixed3(0, 0, 0));
                return y;
            }

            v2f vert(a2v v)
            {
                float3 worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                fixed3 worldLightDir = normalize(UnityWorldSpaceLightDir(worldPos));
                fixed3 worldViewDir = normalize(UnityWorldSpaceViewDir(worldPos));
                fixed3 halfDir = normalize(worldLightDir + worldViewDir);

                fixed3 worldNormal = normalize(UnityObjectToWorldNormal(v.normal));
                fixed3 worldTangent = normalize(UnityWorldToObjectDir(v.tangent)).xyz;

                float vx = dot(worldTangent, halfDir);
                float vz = dot(worldNormal, halfDir);

                float e = vx * _RoughX / vz;
                float c = exp(-e * e);

                fixed4 anis = _Color * c.rrrr;
                anis.w = 1.0;

                vx *= _SpacingX;
                vx = abs(vx);

                float vx0;
                fixed4 diffuse = float4(0, 0, 0, 1);
                for (int i = 1; i < 7; ++i)
                {
                    vx0 = 2 * vx / i - 1;
                    diffuse.rgb += Blend3(fixed3(4 * (vx0 - 0.75), 4 * (vx0 - 0.5), 4 * (vx0 - 0.25)));
                }

                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.color = 0.8 * diffuse + anis;

                return o;
            }

            fixed4 frag(v2f i) : SV_TARGET
            {
                return i.color;
            }
            
            ENDCG
        }
    }

    FallBack "Diffuse"
}
