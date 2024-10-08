Shader "Skybox/NightSkyShader"
{// Unity built-in shader source. Copyright (c) 2016 Unity Technologies. MIT license (see license.txt)

Properties {
    [KeywordEnum(None, Simple, High Quality)] _SunDisk ("Sun", Int) = 2
    _SunSize ("Sun Size", Range(0,1)) = 0.04
    _SunSizeConvergence("Sun Size Convergence", Range(1,10)) = 5

    _AtmosphereThickness ("Atmosphere Thickness", Range(0,5)) = 1.0
    _SkyTint ("Sky Tint", Color) = (.5, .5, .5, 1)
    _GroundColor ("Ground", Color) = (.369, .349, .341, 1)

    _Exposure("Exposure", Range(0, 8)) = 1.3
}

SubShader {
    Tags { "Queue"="Background" "RenderType"="Background" "PreviewType"="Skybox" }
    Cull Off ZWrite Off

    Pass {

        CGPROGRAM
        #pragma vertex vert
        #pragma fragment frag

        #include "UnityCG.cginc"
        #include "Lighting.cginc"

        #pragma multi_compile_local _SUNDISK_NONE _SUNDISK_SIMPLE _SUNDISK_HIGH_QUALITY

        uniform half _Exposure;     // HDR exposure
        uniform half3 _GroundColor;
        uniform half _SunSize;
        uniform half _SunSizeConvergence;
        uniform half3 _SkyTint;
        uniform half _AtmosphereThickness;



      
        #define OUTER_RADIUS 1.025
        static const float kOuterRadius = OUTER_RADIUS;
        static const float kOuterRadius2 = OUTER_RADIUS*OUTER_RADIUS;
        static const float kInnerRadius = 1.0;
        static const float kInnerRadius2 = 1.0;

        static const float kCameraHeight = 0.0001;

       

        static const half kHDSundiskIntensityFactor = 15.0;
        static const half kSimpleSundiskIntensityFactor = 27.0;

        
        static const float kScale = 1.0 / (OUTER_RADIUS - 1.0);
        static const float kScaleDepth = 0.25;
        static const float kScaleOverScaleDepth = (1.0 / (OUTER_RADIUS - 1.0)) / 0.25;
        static const float kSamples = 2.0; // THIS IS UNROLLED MANUALLY, DON'T TOUCH

      
        #define SKY_GROUND_THRESHOLD 0.02

        // fine tuning of performance. You can override defines here if you want some specific setup
        // or keep as is and allow later code to set it according to target api

        // if set vprog will output color in final color space (instead of linear always)
        // in case of rendering in gamma mode that means that we will do lerps in gamma mode too, so there will be tiny difference around horizon
        // #define SKYBOX_COLOR_IN_TARGET_COLOR_SPACE 0

    
        // uncomment this line and change SKYBOX_SUNDISK_SIMPLE to override material settings
        // #define SKYBOX_SUNDISK SKYBOX_SUNDISK_SIMPLE



        struct appdata_t
        {
            float4 vertex : POSITION;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        struct v2f
        {
            float4  pos             : SV_POSITION;
            half3   rayDir          : TEXCOORD0;
            // calculate sky colors in vprog
            half3   groundColor     : TEXCOORD1;
            half3   skyColor        : TEXCOORD2;
            half3   sunColor        : TEXCOORD3;
            UNITY_VERTEX_OUTPUT_STEREO
        };


        float scale(float inCos)
        {
            float x = 1.0 - inCos;
            return 0.25 * exp(-0.00287 + x*(0.459 + x*(3.83 + x*(-6.80 + x*5.25))));
        }

        v2f vert (appdata_t v)
        {
            v2f OUT;
            UNITY_SETUP_INSTANCE_ID(v);
            UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);
            OUT.pos = UnityObjectToClipPos(v.vertex);

          

            float3 cameraPos = float3(0,kInnerRadius + kCameraHeight,0);    // The camera's current position

            // Get the ray from the camera to the vertex and its length (which is the far point of the ray passing through the atmosphere)
            float3 eyeRay = normalize(mul((float3x3)unity_ObjectToWorld, v.vertex.xyz));

            float far = 0.0;
            half3 cIn, cOut;

            if(eyeRay.y >= 0.0)
            {
                // Sky
                // Calculate the length of the "atmosphere"
                far = sqrt(kOuterRadius2 + kInnerRadius2 * eyeRay.y * eyeRay.y - kInnerRadius2) - kInnerRadius * eyeRay.y;

                float3 pos = cameraPos + far * eyeRay;

                // Finally, scale the Mie and Rayleigh colors and set up the varying variables for the pixel shader
                cIn = half3(1.0,1.0,1.0);
                cOut = half3(1.0,1.0,1.0);
            }
            else
            {
                // Ground
                far = (-kCameraHeight) / (min(-0.001, eyeRay.y));

                float3 pos = cameraPos + far * eyeRay;

                // Calculate the ray's starting position, then calculate its scattering offset
                float depth = exp((-kCameraHeight) * (1.0/kScaleDepth));
                float cameraAngle = dot(-eyeRay, pos);
                float lightAngle = dot(_WorldSpaceLightPos0.xyz, pos);
                float cameraScale = scale(cameraAngle);
                float lightScale = scale(lightAngle);
                float cameraOffset = depth*cameraScale;
                float temp = (lightScale + cameraScale);

           
                cIn = half3(0.0,0.0,0.0);
                cOut = clamp(0.0,0.0,0.0);
            }
            OUT.rayDir          = half3(-eyeRay);
     
            // if we want to calculate color in vprog:
            // 1. in case of linear: multiply by _Exposure in here (even in case of lerp it will be common multiplier, so we can skip mul in fshader)
            // 2. in case of gamma and SKYBOX_COLOR_IN_TARGET_COLOR_SPACE: do sqrt right away instead of doing that in fshader

            OUT.groundColor = _Exposure *_GroundColor;
            OUT.skyColor    = _Exposure * _SkyTint;
       
            OUT.sunColor    =  _LightColor0.xyz;

            return OUT;
        }

        // Calculates the sun shape
        half calcSunAttenuation(half3 lightPos, half3 ray)
        {
            half3 delta = lightPos - ray;
            half dist = length(delta);
            half spot = step(dist, _SunSize);

            return spot;
    
        }
      

        half4 frag (v2f IN) : SV_Target
        {
            half3 col = half3(0.0, 0.0, 0.0);

            half3 ray = IN.rayDir.xyz;
            half y = ray.y / SKY_GROUND_THRESHOLD;
     
            // if we did precalculte color in vprog: just do lerp between them
            col = lerp(IN.skyColor, IN.groundColor, saturate(y));
            if(y < 0.0)
            {
                col += IN.sunColor * calcSunAttenuation(_WorldSpaceLightPos0.xyz, -ray);
            }
            return half4(col,1.0);

        }
        ENDCG
    }
}


Fallback Off
CustomEditor "SkyboxProceduralShaderGUI"
}
