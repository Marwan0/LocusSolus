﻿// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "ArtSpaces/marchingCubesShaderTriplanarNoise" {
	Properties{
			_Color( "Color", Color ) = ( 1, 1, 1, 1 )
			_WorldSpaceScale( "WorldSpaceScale", Vector ) = ( 1, 1, 1, 1 )
			_RoughnessTex( "Roughness (Gray)", 2D ) = "white" {}
			_Metallic( "Metallic", Range( 0, 1 ) ) = 0.0
			_Roughness( "Roughness", Range( 0, 1 ) ) = 1.0
			_NoiseAmount( "NoiseAmount", Range( 0, 1 ) ) = 0.0
			_TriplanarBlendSharpness( "_TriplanarBlendSharpness", Range( 0, 128 ) ) = 4
			_Emission( "Emission", Range( 0, 1 ) ) = 0.0
		}
		SubShader{
		Tags{ "Queue" = "Geometry" "RenderType" = "Opaque" }

		LOD 2000
		//AlphaToMask On
		//Cull Off		

		CGPROGRAM

		// Physically based Standard lighting model, and enable shadows on all light types
#pragma surface surf Standard vertex:vert fullforwardshadows addshadow
#pragma multi_compile_instancing
#pragma instancing_options procedural:setup

#pragma target 5.0

//#include "Compute/shaderQuat.cginc"

	sampler2D _AlphaTex;

	struct Vertex
	{
		float3 vPosition;
		float3 vNormal;
		float3 vColor;
	};

	struct Triangle
	{
		Vertex v[3];
	};

#ifdef UNITY_PROCEDURAL_INSTANCING_ENABLED
	uniform StructuredBuffer<Triangle> triangles;
	uniform StructuredBuffer<uint> indexStructure;
#endif
	float4x4 _LocalToWorld;
	float4x4 _WorldToLocal;

	sampler2D _RoughnessTex;

	float4 _WorldSpaceScale;
	float _TriplanarBlendSharpness;
	half _Metallic;
	half _Roughness;
	half _Emission;
	half _NoiseAmount;
	fixed4 _Color;

	struct appdata {
		float4 vertex : POSITION;
		float4 color : COLOR;
		float3 normal : NORMAL;

		uint id : SV_VertexID;
		UNITY_VERTEX_INPUT_INSTANCE_ID
	};

	struct Input {
		float3 worldPos;
		float3 worldNormal;
		float4 color : COLOR;
	};

	float hash( float h )
	{
		return frac( sin( h ) * 43758.5453123 );
	}

	float noise( float3 x )
	{
		float3 p = floor( x );
		float3 f = frac( x );
		f = f * f * ( 3.0 - 2.0 * f );

		float n = p.x + p.y * 157.0 + 113.0 * p.z;
		return lerp(
			lerp( lerp( hash( n + 0.0 ), hash( n + 1.0 ), f.x ),
				  lerp( hash( n + 157.0 ), hash( n + 158.0 ), f.x ), f.y ),
			lerp( lerp( hash( n + 113.0 ), hash( n + 114.0 ), f.x ),
				  lerp( hash( n + 270.0 ), hash( n + 271.0 ), f.x ), f.y ), f.z );
	}

	float fbm( float3 p )
	{
		float f = 0.0;
		f = 0.5000 * noise( p );
		p *= 2.01;
		f += 0.2500 * noise( p );
		p *= 2.02;
		f += 0.1250 * noise( p );

		return f;
	}
	
	void vert( inout appdata v, out Input data ) {
		UNITY_INITIALIZE_OUTPUT( Input, data );

#ifdef UNITY_PROCEDURAL_INSTANCING_ENABLED
		UNITY_SETUP_INSTANCE_ID( v );

		uint pid = ( v.id + indexStructure[0] * UNITY_GET_INSTANCE_ID( v ) ) / 3;
		uint vid = ( v.id + indexStructure[0] * UNITY_GET_INSTANCE_ID( v ) ) % 3;

		v.vertex = mul( _LocalToWorld, float4( triangles[pid].v[vid].vPosition, 1 ) );
		v.normal = mul( _LocalToWorld, triangles[pid].v[vid].vNormal );
		v.vertex.xyz += 0.1 * _NoiseAmount * ( 2.0f * fbm( v.vertex.xyz * 4 ) - 1.0 ) * v.normal.xyz;
		v.color = float4( triangles[pid].v[vid].vColor, 1.0 );
#endif
		//data.worldPos = v.vertex;
		//data.worldNormal = v.normal;
	}

	void setup()
	{
	}

#define max3(x, y, z) ( max(max(x, y), z) )
	float maxElem( float3 v ) { return max3( v.x, v.y, v.z ); }

	float2 uvMapPerpendicularToDominantNormalElement( float3 N, float3 uvw )
	{
		N = abs( N );
		float m = maxElem( N );
		float2 uv;

		if( m == N.x ) uv = uvw.yz;
		else if( m == N.y ) uv = uvw.xz;
		else uv = uvw.xy;
		return uv;
	}

	void surf( Input IN, inout SurfaceOutputStandard o ) {

		fixed4 c = _Color;

		// Metallic and smoothness come from slider variables
		o.Metallic = _Metallic;

		half2 yUV = IN.worldPos.xz / _WorldSpaceScale;
		half2 xUV = IN.worldPos.zy / _WorldSpaceScale;
		half2 zUV = IN.worldPos.xy / _WorldSpaceScale;
		// Now do texture samples from our diffuse map with each of the 3 UV set's we've just made.
		half yDiff = tex2D( _RoughnessTex, yUV ).r;
		half xDiff = tex2D( _RoughnessTex, xUV ).r;
		half zDiff = tex2D( _RoughnessTex, zUV ).r;
		// Get the absolute value of the world normal.
		// Put the blend weights to the power of BlendSharpness, the higher the value, 
		// the sharper the transition between the planar maps will be.
		half3 blendWeights = pow( abs( IN.worldNormal ), _TriplanarBlendSharpness );
		// Divide our blend mask by the sum of it's components, this will make x+y+z=1
		blendWeights = blendWeights / ( blendWeights.x + blendWeights.y + blendWeights.z );
		// Finally, blend together all three samples based on the blend mask.
		half triplanarRoughness = xDiff * blendWeights.x + yDiff * blendWeights.y + zDiff * blendWeights.z;
		o.Smoothness = 1.0 - _Roughness * min( 1.0, triplanarRoughness* 4.0f - 0.1 );
		o.Emission = _Emission;

		o.Albedo = _Color.xyz;// *IN.color;
	}
	ENDCG
	}
	FallBack "Diffuse"
}


