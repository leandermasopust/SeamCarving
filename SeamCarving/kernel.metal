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

    float4 seam(sampler s, constant int seam[100000], float width, float height) {
        float onePixelWidth = 1./width;
        float onePixelHeight = 1./height;
        int currentRow = round(s.coord().y / onePixelHeight);
        int currentColumn = round(s.coord().x / onePixelWidth);
        if(currentColumn == seam[currentRow]) return float4(float3(1.),0.);
        return s.sample(s.coord());
    }

    float4 filterSeam(sampler s, constant int seam[100000], float width, float height) {
        float onePixelWidth = 1./width;
        float onePixelHeight = 1./height;
        int currentRow = round(s.coord().y / onePixelHeight);
        int currentColumn = round(s.coord().x / onePixelWidth);
        if(currentColumn > (seam[currentRow]+1) && (seam[currentRow] != 0)) return float4(float3(1.),1.);
        return s.sample(s.coord());
    }

}}
