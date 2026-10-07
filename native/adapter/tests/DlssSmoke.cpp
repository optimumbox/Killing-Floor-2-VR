// Manual GPU check (needs an NVIDIA RTX GPU): kf2vr_dlss_smoke <dir with nvngx_dlss.dll>
// Runs every DLSS mode through DlssUpscaler at the Index's 2688x2688 eye size.
#include "../Dlss.h"

#include <d3d11.h>
#include <wrl/client.h>
#include <cstdio>
#include <string>
#include <vector>

using Microsoft::WRL::ComPtr;
using namespace kf2vr::adapter;
namespace pinned=kf2vr::adapter::pinned;

namespace {
pinned::NativeMatrix4 Identity() { pinned::NativeMatrix4 m{}; for (int i=0;i<4;++i) m.m[i][i]=1; return m; }
pinned::NativeMatrix4 Projection() {
    pinned::NativeMatrix4 p{};
    p.m[0][0]=1; p.m[1][1]=1; p.m[2][2]=1.0001f; p.m[2][3]=1; p.m[3][2]=-10.001f;
    return p;
}
}

int wmain(int argc, wchar_t** argv) {
    const std::wstring ngx=argc>1 ? argv[1] : L".";
    ComPtr<ID3D11Device> device; ComPtr<ID3D11DeviceContext> context;
    D3D_FEATURE_LEVEL level=D3D_FEATURE_LEVEL_11_1;
    if (FAILED(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,0,&level,1,D3D11_SDK_VERSION,&device,nullptr,&context))) {
        std::printf("FAIL: D3D11CreateDevice\n"); return 1;
    }
    const unsigned output=2688;
    int failures=0;
    for (float sharpness:{0.0f,0.5f})
    for (DlssMode mode:{DlssMode::Dlaa,DlssMode::Quality,DlssMode::Balanced,DlssMode::Performance,DlssMode::UltraPerformance}) {
        DlssUpscaler dlss;
        wchar_t temp[MAX_PATH]{}; GetTempPathW(MAX_PATH,temp);
        dlss.Configure(mode,ngx,temp);
        dlss.SetSharpness(sharpness);
        const unsigned render=DlssRenderExtent(output,mode);
        D3D11_TEXTURE2D_DESC d{}; d.MipLevels=1; d.ArraySize=1; d.SampleDesc={1,0}; d.Usage=D3D11_USAGE_DEFAULT;
        // Colour like the swapchain: sRGB-viewable typeless storage.
        d.Width=render; d.Height=render; d.Format=DXGI_FORMAT_R8G8B8A8_TYPELESS; d.BindFlags=D3D11_BIND_RENDER_TARGET;
        std::vector<unsigned> pixels(render*render);
        for (unsigned y=0;y<render;++y) for (unsigned x=0;x<render;++x)
            pixels[y*render+x]=0xff000000u|((x*255/render)<<0)|((y*255/render)<<8)|(((x/32+y/32)&1)?0x800000u:0);
        D3D11_SUBRESOURCE_DATA init{pixels.data(),render*4,0};
        ComPtr<ID3D11Texture2D> color,depth,out,staging;
        if (FAILED(device->CreateTexture2D(&d,&init,&color))) { std::printf("FAIL: colour\n"); return 1; }
        // Depth like KF2's scene depth: D24S8 typeless, depth-stencil + SRV.
        d.Format=DXGI_FORMAT_R24G8_TYPELESS; d.BindFlags=D3D11_BIND_DEPTH_STENCIL|D3D11_BIND_SHADER_RESOURCE;
        if (FAILED(device->CreateTexture2D(&d,nullptr,&depth))) { std::printf("FAIL: depth\n"); return 1; }
        ComPtr<ID3D11DepthStencilView> dsv; D3D11_DEPTH_STENCIL_VIEW_DESC dv{}; dv.Format=DXGI_FORMAT_D24_UNORM_S8_UINT;
        dv.ViewDimension=D3D11_DSV_DIMENSION_TEXTURE2D;
        device->CreateDepthStencilView(depth.Get(),&dv,&dsv);
        context->ClearDepthStencilView(dsv.Get(),D3D11_CLEAR_DEPTH|D3D11_CLEAR_STENCIL,0.9f,0);
        d.Width=output; d.Height=output; d.Format=DXGI_FORMAT_R8G8B8A8_UNORM;
        d.BindFlags=D3D11_BIND_SHADER_RESOURCE|D3D11_BIND_UNORDERED_ACCESS;
        if (FAILED(device->CreateTexture2D(&d,nullptr,&out))) { std::printf("FAIL: output\n"); return 1; }
        bool ok=true; std::string error;
        for (std::uint32_t frame=1;frame<=12 && ok;++frame) {
            for (unsigned eye=0;eye<2 && ok;++eye) {
                DlssEyeInput input;
                input.view=Identity(); input.view.m[3][0]=-0.01f*frame; // small camera motion
                input.projection=Projection();
                input.jitter=DlssJitterForPhase(frame,render,output);
                input.renderWidth=render; input.renderHeight=render; input.valid=true;
                ok=dlss.Evaluate(device.Get(),context.Get(),eye,color.Get(),depth.Get(),out.Get(),input,error);
            }
        }
        unsigned center=0;
        if (ok) {
            d.Usage=D3D11_USAGE_STAGING; d.BindFlags=0; d.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
            device->CreateTexture2D(&d,nullptr,&staging);
            context->CopyResource(staging.Get(),out.Get());
            D3D11_MAPPED_SUBRESOURCE map{};
            if (SUCCEEDED(context->Map(staging.Get(),0,D3D11_MAP_READ,0,&map))) {
                center=static_cast<const unsigned*>(map.pData)[(output/2)*(map.RowPitch/4)+output/2];
                context->Unmap(staging.Get(),0);
            }
        }
        const bool image=ok && (center&0x00ffffffu)!=0;
        std::printf("sharp=%.1f %-17s render=%4ux%-4u output=%ux%u evaluate=%s centre=0x%08x %s\n",sharpness,DlssModeName(mode),render,render,
            output,output,ok?"ok":error.c_str(),center,image?"PASS":"FAIL");
        if (!image) ++failures;
        dlss.Shutdown();
    }
    // Single-pass stereo: both eyes side by side in one colour/depth target.
    // Left half solid red, right half solid green; each eye must upscale its own half.
    {
        DlssUpscaler dlss;
        wchar_t temp[MAX_PATH]{}; GetTempPathW(MAX_PATH,temp);
        dlss.Configure(DlssMode::Quality,ngx,temp);
        const unsigned render=DlssRenderExtent(output,DlssMode::Quality), wide=render*2;
        D3D11_TEXTURE2D_DESC d{}; d.MipLevels=1; d.ArraySize=1; d.SampleDesc={1,0}; d.Usage=D3D11_USAGE_DEFAULT;
        d.Width=wide; d.Height=render; d.Format=DXGI_FORMAT_R8G8B8A8_TYPELESS; d.BindFlags=D3D11_BIND_RENDER_TARGET;
        std::vector<unsigned> pixels(wide*render);
        for (unsigned y=0;y<render;++y) for (unsigned x=0;x<wide;++x) pixels[y*wide+x]=x<render ? 0xff0000ffu : 0xff00ff00u;
        D3D11_SUBRESOURCE_DATA init{pixels.data(),wide*4,0};
        ComPtr<ID3D11Texture2D> color,depth,staging;
        ComPtr<ID3D11Texture2D> outs[2];
        bool ok=SUCCEEDED(device->CreateTexture2D(&d,&init,&color));
        d.Format=DXGI_FORMAT_R24G8_TYPELESS; d.BindFlags=D3D11_BIND_DEPTH_STENCIL|D3D11_BIND_SHADER_RESOURCE;
        ok=ok && SUCCEEDED(device->CreateTexture2D(&d,nullptr,&depth));
        d.Width=output; d.Height=output; d.Format=DXGI_FORMAT_R8G8B8A8_UNORM;
        d.BindFlags=D3D11_BIND_SHADER_RESOURCE|D3D11_BIND_UNORDERED_ACCESS;
        for (auto& o:outs) ok=ok && SUCCEEDED(device->CreateTexture2D(&d,nullptr,&o));
        std::string error;
        for (std::uint32_t frame=1;frame<=8 && ok;++frame)
            for (unsigned eye=0;eye<2 && ok;++eye) {
                DlssEyeInput input;
                input.view=Identity(); input.projection=Projection();
                input.jitter=DlssJitterForPhase(frame,render,output);
                input.renderX=eye*render; input.renderWidth=render; input.renderHeight=render; input.valid=true;
                ok=dlss.Evaluate(device.Get(),context.Get(),eye,color.Get(),depth.Get(),outs[eye].Get(),input,error);
            }
        unsigned centre[2]{};
        if (ok) {
            d.Usage=D3D11_USAGE_STAGING; d.BindFlags=0; d.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
            device->CreateTexture2D(&d,nullptr,&staging);
            for (unsigned eye=0;eye<2;++eye) {
                context->CopyResource(staging.Get(),outs[eye].Get());
                D3D11_MAPPED_SUBRESOURCE map{};
                if (SUCCEEDED(context->Map(staging.Get(),0,D3D11_MAP_READ,0,&map))) {
                    centre[eye]=static_cast<const unsigned*>(map.pData)[(output/2)*(map.RowPitch/4)+output/2];
                    context->Unmap(staging.Get(),0);
                }
            }
        }
        // R8G8B8A8 little-endian: red is the low byte, green the next.
        const bool leftRed=(centre[0]&0xff)>200 && ((centre[0]>>8)&0xff)<50;
        const bool rightGreen=((centre[1]>>8)&0xff)>200 && (centre[1]&0xff)<50;
        const bool pass=ok && leftRed && rightGreen;
        std::printf("single-pass pair Quality render=%ux%u (x2) left=0x%08x right=0x%08x %s %s\n",render,render,
            centre[0],centre[1],ok?"":error.c_str(),pass?"PASS":"FAIL");
        if (!pass) ++failures;
        dlss.Shutdown();
    }
    return failures ? 1 : 0;
}
