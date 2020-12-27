// ****************************************************************************************
// *********************************** 曲面细分着色器 **************************************
// ****************************************************************************************
// 参考：https://catlikecoding.com/unity/tutorials/advanced-rendering/tessellation/

// 顶点输入.
struct vertexInput
{
    float4 vertex : POSITION;
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
};

// 流水线最终顶点输出, 顶点着色器不必变换到投影空间, 但是一定要在几何着色器完成之前保证顶点变换到投影空间.
struct vertexOutput
{
    float4 vertex : SV_POSITION;
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
};

// 曲面细分因子, 决定多边形了细分的样式.
struct TessellationFactors
{
    float edge[3] : SV_TESSFACTOR;
    float inside : SV_INSIDETESSFACTOR;
};

// 顶点着色器, 在这里没有实质的作用.
vertexInput vert(vertexInput v)
{
    return v;
}

// 转换.
vertexOutput tessVert(vertexInput v)
{
    vertexOutput o;

    o.vertex = v.vertex;
    o.normal = v.normal;
    o.tangent = v.tangent;

    return o;
}

// 曲面细分的次数, 也就是每条边细分多少段.
float _TessellationUniform;

// 细分过程不可控制, 这里是对曲面细分因子的准备.
TessellationFactors patchConstantFunction(InputPatch<vertexInput, 3> patch)
{
    TessellationFactors f;

    // 外部细分, 也就是一条边的分段.
    f.edge[0] = _TessellationUniform;
    f.edge[1] = _TessellationUniform;
    f.edge[2] = _TessellationUniform;

    // 内部细分.
    f.inside = _TessellationUniform;

    return f;
}

// 外壳着色器, 和 DX 的语法及其相似.
[UNITY_domain("tri")]
[UNITY_outputcontrolpoints(3)]
[UNITY_outputtopology("triangle_cw")]
[UNITY_partitioning("integer")]
[UNITY_patchconstantfunc("patchConstantFunction")]
vertexInput hull(InputPatch<vertexInput, 3> patch, uint id : SV_OUTPUTCONTROLPOINTID)
{
    return patch[id];
}

// 域着色器.
[UNITY_domain("tri")]
vertexOutput domain(TessellationFactors factors, 
    OutputPatch<vertexInput, 3> patch, 
    float3 uvw : SV_DomainLocation)
{
    vertexInput v;

	#define MY_DOMAIN_PROGRAM_INTERPOLATE(fieldName) v.fieldName = \
		patch[0].fieldName * uvw.x + \
		patch[1].fieldName * uvw.y + \
		patch[2].fieldName * uvw.z;

	MY_DOMAIN_PROGRAM_INTERPOLATE(vertex)
	MY_DOMAIN_PROGRAM_INTERPOLATE(normal)
	MY_DOMAIN_PROGRAM_INTERPOLATE(tangent)

	return tessVert(v);
}
