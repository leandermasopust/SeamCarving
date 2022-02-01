#include <metal_stdlib>
using namespace metal;
#include <CoreImage/CoreImage.h>

extern "C" { namespace coreimage {

    float4 energyMap(sampler s, float width, float height) {
        float onePixelWidth = 1./width;
        float4 col = s.sample(s.coord());
        float4 colX = s.sample(s.coord() + float2(onePixelWidth,0.0));
        float4 colNegX = s.sample(s.coord() - float2(onePixelWidth,0.0));
        float3 diffX = (pow(col - colX,2)).rgb;
        float3 diffNegX = (pow(col - colNegX,2)).rgb;
        return float4(float3(sqrt(diffX.x + diffX.y + diffX.z + diffNegX.x + diffNegX.y + diffNegX.z)),1.);
    }
}}
