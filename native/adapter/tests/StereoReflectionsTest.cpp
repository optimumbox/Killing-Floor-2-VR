#include "StereoReflections.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

using Microsoft::WRL::ComPtr;
using kf2vr::adapter::StereoReflections;

namespace {
int failures=0;
void Test(bool ok,const char* name) { std::printf("%s %s\n",ok?"PASS":"FAIL",name); if (!ok) ++failures; }

constexpr UINT W=64, H=48, Mips=5;
struct Scene {
    std::vector<float> normal, specular;   // RGBA per pixel
    std::vector<std::vector<float>> depth; // per mip
};
// A floor at y=-50 under a wall at distance wall; camera space is world space.
Scene MakeScene(float wall,unsigned seed) {
    Scene s; s.normal.resize(W*H*4); s.specular.resize(W*H*4);
    std::vector<float> d(W*H);
    for (UINT y=0;y<H;++y) for (UINT x=0;x<W;++x) {
        const float cx=(x+0.0f)/W*2-1, cy=1-(y+0.0f)/H*2;
        float z=wall; float n[3]{0.5f,0.5f,0.0f};
        if (cy<0 && -50.0f/cy<wall) { z=-50.0f/cy; n[0]=0.5f; n[1]=1.0f; n[2]=0.5f; }
        (void)cx;
        const UINT i=y*W+x;
        d[i]=100.0f/z;
        seed=seed*1664525u+1013904223u;
        const float noise=(seed>>8)/16777216.0f;
        s.normal[i*4+0]=n[0]; s.normal[i*4+1]=n[1]; s.normal[i*4+2]=n[2]; s.normal[i*4+3]=noise<0.1f?0.1f:0.9f;
        s.specular[i*4+0]=0.5f+0.5f*noise; s.specular[i*4+1]=0; s.specular[i*4+2]=0; s.specular[i*4+3]=noise;
    }
    s.depth.push_back(d);
    for (UINT m=1;m<Mips;++m) {
        const UINT pw=W>>(m-1), w=W>>m, h=H>>m; const auto& p=s.depth.back(); std::vector<float> c(w*h);
        for (UINT y=0;y<h;++y) for (UINT x=0;x<w;++x)
            c[y*w+x]=std::max({p[2*y*pw+2*x],p[2*y*pw+2*x+1],p[(2*y+1)*pw+2*x],p[(2*y+1)*pw+2*x+1]});
        s.depth.push_back(c);
    }
    return s;
}
// Side by side: a | b.
Scene Pair(const Scene& a,const Scene& b) {
    Scene s;
    const auto join=[](const std::vector<float>& l,const std::vector<float>& r,UINT w,UINT h,UINT c) {
        std::vector<float> o(2*w*h*c);
        for (UINT y=0;y<h;++y) {
            std::copy_n(&l[y*w*c],w*c,&o[y*2*w*c]); std::copy_n(&r[y*w*c],w*c,&o[y*2*w*c+w*c]);
        }
        return o;
    };
    s.normal=join(a.normal,b.normal,W,H,4); s.specular=join(a.specular,b.specular,W,H,4);
    for (UINT m=0;m<Mips;++m) s.depth.push_back(join(a.depth[m],b.depth[m],W>>m,H>>m,1));
    return s;
}

struct Gpu {
    ComPtr<ID3D11Device> device; ComPtr<ID3D11DeviceContext> context;
    bool Create() {
        for (auto type:{D3D_DRIVER_TYPE_HARDWARE,D3D_DRIVER_TYPE_WARP})
            if (SUCCEEDED(D3D11CreateDevice(nullptr,type,nullptr,0,nullptr,0,D3D11_SDK_VERSION,&device,nullptr,&context))) return true;
        return false;
    }
    ComPtr<ID3D11ShaderResourceView> Texture(UINT w,UINT h,DXGI_FORMAT f,UINT mips,const std::vector<const float*>& data,UINT channels) {
        D3D11_TEXTURE2D_DESC d{}; d.Width=w; d.Height=h; d.MipLevels=mips; d.ArraySize=1; d.Format=f; d.SampleDesc={1,0};
        d.Usage=D3D11_USAGE_DEFAULT; d.BindFlags=D3D11_BIND_SHADER_RESOURCE;
        std::vector<D3D11_SUBRESOURCE_DATA> init(mips);
        for (UINT m=0;m<mips;++m) init[m]={data[m],(w>>m)*channels*4u,0};
        ComPtr<ID3D11Texture2D> t; ComPtr<ID3D11ShaderResourceView> v;
        device->CreateTexture2D(&d,init.data(),&t); device->CreateShaderResourceView(t.Get(),nullptr,&v);
        return v;
    }
    ComPtr<ID3D11Buffer> Constants(const void* data,UINT size) {
        D3D11_BUFFER_DESC d{}; d.ByteWidth=size; d.Usage=D3D11_USAGE_DEFAULT; d.BindFlags=D3D11_BIND_CONSTANT_BUFFER;
        D3D11_SUBRESOURCE_DATA init{data,0,0}; ComPtr<ID3D11Buffer> b; device->CreateBuffer(&d,&init,&b); return b;
    }
    // Binds the game's slots for a scene of width sceneW and returns the
    // output texture (cleared to 7).
    ComPtr<ID3D11Texture2D> Bind(const Scene& s,UINT sceneW,ComPtr<ID3D11UnorderedAccessView>& uav,std::vector<ComPtr<IUnknown>>& keep) {
        std::vector<const float*> depth; for (const auto& m:s.depth) depth.push_back(m.data());
        auto normal=Texture(sceneW,H,DXGI_FORMAT_R32G32B32A32_FLOAT,1,{s.normal.data()},4);
        auto specular=Texture(sceneW,H,DXGI_FORMAT_R32G32B32A32_FLOAT,1,{s.specular.data()},4);
        auto depthView=Texture(sceneW,H,DXGI_FORMAT_R32_FLOAT,Mips,depth,1);
        ID3D11ShaderResourceView* views[3]{normal.Get(),specular.Get(),depthView.Get()};
        context->CSSetShaderResources(0,3,views);
        D3D11_SAMPLER_DESC sd{}; sd.Filter=D3D11_FILTER_MIN_MAG_MIP_POINT;
        sd.AddressU=sd.AddressV=sd.AddressW=D3D11_TEXTURE_ADDRESS_CLAMP; sd.MaxLOD=D3D11_FLOAT32_MAX;
        ComPtr<ID3D11SamplerState> sampler; device->CreateSamplerState(&sd,&sampler);
        ID3D11SamplerState* samplers[3]{sampler.Get(),sampler.Get(),sampler.Get()};
        context->CSSetSamplers(0,3,samplers);
        float c8[14][4]{};
        c8[0][2]=0.01f; c8[0][3]=0.0f;                              // MinZ_MaxZRatio: depth 100/z
        c8[7][0]=1; c8[8][1]=1; c8[9][3]=1; c8[10][2]=100;          // ViewProjection
        c8[11][0]=1; c8[12][1]=1; c8[13][2]=1;                      // ScreenToWorld
        int c10[8]{}; float size[2]{static_cast<float>(sceneW),static_cast<float>(H)};
        std::memcpy(c10,size,8); c10[4]=Mips;
        auto b8=Constants(c8,sizeof(c8)), b10=Constants(c10,sizeof(c10));
        ID3D11Buffer* b8p=b8.Get(); ID3D11Buffer* b10p=b10.Get();
        context->CSSetConstantBuffers(8,1,&b8p); context->CSSetConstantBuffers(10,1,&b10p);
        D3D11_TEXTURE2D_DESC d{}; d.Width=sceneW; d.Height=H; d.MipLevels=1; d.ArraySize=1; d.Format=DXGI_FORMAT_R32G32B32A32_FLOAT;
        d.SampleDesc={1,0}; d.Usage=D3D11_USAGE_DEFAULT; d.BindFlags=D3D11_BIND_UNORDERED_ACCESS;
        ComPtr<ID3D11Texture2D> out; device->CreateTexture2D(&d,nullptr,&out);
        device->CreateUnorderedAccessView(out.Get(),nullptr,&uav);
        const float seven[4]{7,7,7,7}; context->ClearUnorderedAccessViewFloat(uav.Get(),seven);
        ID3D11UnorderedAccessView* u=uav.Get(); context->CSSetUnorderedAccessViews(0,1,&u,nullptr);
        keep={normal,specular,depthView,sampler,b8,b10};
        return out;
    }
    std::vector<float> Read(ID3D11Texture2D* t) {
        D3D11_TEXTURE2D_DESC d{}; t->GetDesc(&d);
        d.Usage=D3D11_USAGE_STAGING; d.BindFlags=0; d.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
        ComPtr<ID3D11Texture2D> s; device->CreateTexture2D(&d,nullptr,&s); context->CopyResource(s.Get(),t);
        D3D11_MAPPED_SUBRESOURCE m{}; context->Map(s.Get(),0,D3D11_MAP_READ,0,&m);
        std::vector<float> o(d.Width*d.Height*4);
        for (UINT y=0;y<d.Height;++y) std::memcpy(&o[y*d.Width*4],static_cast<const char*>(m.pData)+y*m.RowPitch,d.Width*16);
        context->Unmap(s.Get(),0); return o;
    }
};
void STDMETHODCALLTYPE Forward(ID3D11DeviceContext* c,UINT x,UINT y,UINT z) { c->Dispatch(x,y,z); }

std::vector<float> RunMine(Gpu& g,StereoReflections& r,const Scene& s,UINT sceneW,const float eye[4]) {
    ComPtr<ID3D11UnorderedAccessView> uav; std::vector<ComPtr<IUnknown>> keep;
    auto out=g.Bind(s,sceneW,uav,keep);
    r.Dispatch(g.context.Get(),eye,&Forward);
    return g.Read(out.Get());
}

// The game's own shader from the global shader cache, when a path is given.
ComPtr<ID3D11ComputeShader> GameShader(ID3D11Device* device) {
    char path[1024]{}; if (!GetEnvironmentVariableA("KF2VR_GLOBAL_SHADER_CACHE",path,sizeof(path))) return nullptr;

    std::ifstream f(path,std::ios::binary); std::string data((std::istreambuf_iterator<char>(f)),{});
    for (size_t i=data.find("DXBC");i!=std::string::npos;i=data.find("DXBC",i+4)) {
        if (i+28>data.size()) break;
        UINT size=0; std::memcpy(&size,&data[i+24],4);
        if (size<32 || i+size>data.size()) continue;
        const std::string blob=data.substr(i,size);
        if (blob.find("SSRConstants")==std::string::npos || blob.find("ReflectionTexOut")==std::string::npos) continue;
        ComPtr<ID3D11ComputeShader> cs;
        if (SUCCEEDED(device->CreateComputeShader(blob.data(),blob.size(),nullptr,&cs))) return cs;
    }
    return nullptr;
}
}

int main() {
    Gpu g; if (!g.Create()) { std::printf("SKIP no D3D11 device\n"); return 0; }
    StereoReflections reflections;
    Test(reflections.Ready(g.device.Get()),"stereo reflections shader compiles");
    const Scene eyeScene=MakeScene(300.0f,1), other=MakeScene(180.0f,2);
    const float whole[4]{0,0,static_cast<float>(W),static_cast<float>(H)};
    const auto alone=RunMine(g,reflections,eyeScene,W,whole);
    int hits=0; for (UINT i=0;i<W*H;++i) if (alone[i*4+2]>0) ++hits;
    std::printf("hits=%d of %u\n",hits,W*H);
    Test(hits>static_cast<int>(W*H/20),"the test scene produces reflections");

    // The right eye of a two-eye buffer matches the same eye rendered alone,
    // with its hit UV in the two-eye buffer; the left half is not touched.
    const Scene pair=Pair(other,eyeScene);
    const float right[4]{static_cast<float>(W),0,static_cast<float>(W),static_cast<float>(H)};
    const auto stereo=RunMine(g,reflections,pair,2*W,right);
    int mismatches=0, touched=0;
    for (UINT y=0;y<H;++y) for (UINT x=0;x<W;++x) {
        const float* a=&alone[(y*W+x)*4]; const float* b=&stereo[(y*2*W+W+x)*4];
        const float u=a[3]>0 ? (a[0]*W+W)/(2*W) : 0.0f;
        if (std::fabs(b[0]-u)>1e-4f || std::fabs(b[1]-a[1])>1e-4f || std::fabs(b[2]-a[2])>1e-4f || std::fabs(b[3]-a[3])>1e-4f) ++mismatches;
        const float* l=&stereo[(y*2*W+x)*4]; if (l[0]!=7 || l[1]!=7 || l[2]!=7 || l[3]!=7) ++touched;
    }
    std::printf("right-eye mismatches=%d\n",mismatches);
    Test(mismatches<=static_cast<int>(W*H/200),"right eye matches the eye traced alone");
    Test(touched==0,"right-eye dispatch leaves the left eye alone");
    const float left[4]{0,0,static_cast<float>(W),static_cast<float>(H)};
    const auto leftRun=RunMine(g,reflections,Pair(eyeScene,other),2*W,left);
    mismatches=0; touched=0;
    for (UINT y=0;y<H;++y) for (UINT x=0;x<W;++x) {
        const float* a=&alone[(y*W+x)*4]; const float* b=&leftRun[(y*2*W+x)*4];
        const float u=a[3]>0 ? a[0]*W/(2*W) : 0.0f;
        if (std::fabs(b[0]-u)>1e-4f || std::fabs(b[1]-a[1])>1e-4f || std::fabs(b[2]-a[2])>1e-4f || std::fabs(b[3]-a[3])>1e-4f) ++mismatches;
        const float* r=&leftRun[(y*2*W+W+x)*4]; if (r[0]!=7) ++touched;
    }
    std::printf("left-eye mismatches=%d\n",mismatches);
    Test(mismatches<=static_cast<int>(W*H/200),"left eye matches the eye traced alone");
    Test(touched==0,"left-eye dispatch leaves the right eye alone");

    // With the whole buffer as the eye, the translation equals KF2's shader.
    if (auto game=GameShader(g.device.Get())) {
        ComPtr<ID3D11UnorderedAccessView> uav; std::vector<ComPtr<IUnknown>> keep;
        auto out=g.Bind(eyeScene,W,uav,keep);
        g.context->CSSetShader(game.Get(),nullptr,0);
        g.context->Dispatch((W+31)/32,(H+31)/32,1);
        const auto theirs=g.Read(out.Get());
        float worst=0; for (size_t i=0;i<theirs.size();++i) worst=std::max(worst,std::fabs(theirs[i]-alone[i]));
        std::printf("game shader max difference=%g\n",worst);
        Test(worst<1e-4f,"translation matches KF2's shader");
    } else std::printf("SKIP KF2 shader comparison (set KF2VR_GLOBAL_SHADER_CACHE)\n");
    return failures?1:0;
}
