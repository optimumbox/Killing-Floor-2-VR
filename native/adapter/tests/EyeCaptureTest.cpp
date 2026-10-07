#include "../EyeCapture.h"

#include <windows.h>
#include <wrl/client.h>
#include <cstdio>
#include <string>
#include <vector>

using Microsoft::WRL::ComPtr;

int main() {
    ComPtr<ID3D11Device> device; ComPtr<ID3D11DeviceContext> context;
    if (FAILED(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_WARP,nullptr,0,nullptr,0,D3D11_SDK_VERSION,&device,nullptr,&context))) {
        std::printf("FAIL: device\n"); return 1;
    }
    const unsigned w=64,h=32;
    std::vector<unsigned> pixels(w*h);
    for (unsigned y=0;y<h;++y) for (unsigned x=0;x<w;++x) pixels[y*w+x]=x<w/2 ? 0x000000ffu : 0x0000ff00u; // alpha 0
    D3D11_TEXTURE2D_DESC d{}; d.Width=w; d.Height=h; d.MipLevels=1; d.ArraySize=1; d.SampleDesc={1,0};
    d.Format=DXGI_FORMAT_R8G8B8A8_TYPELESS; d.Usage=D3D11_USAGE_DEFAULT; d.BindFlags=D3D11_BIND_SHADER_RESOURCE;
    D3D11_SUBRESOURCE_DATA init{pixels.data(),w*4,0};
    ComPtr<ID3D11Texture2D> texture;
    if (FAILED(device->CreateTexture2D(&d,&init,&texture))) { std::printf("FAIL: texture\n"); return 1; }
    wchar_t temp[MAX_PATH]{}; GetTempPathW(MAX_PATH,temp);
    const std::wstring path=std::wstring(temp)+L"kf2vr-eye-capture-test.png";
    DeleteFileW(path.c_str());
    std::string error;
    if (!kf2vr::adapter::CaptureTexturePng(device.Get(),context.Get(),texture.Get(),path,error)) {
        std::printf("FAIL: capture %s\n",error.c_str()); return 1;
    }
    // The PNG is written on a worker thread.
    for (int i=0;i<100;++i) {
        WIN32_FILE_ATTRIBUTE_DATA a{};
        if (GetFileAttributesExW(path.c_str(),GetFileExInfoStandard,&a) && a.nFileSizeLow>60) {
            Sleep(100);
            FILE* f=nullptr; _wfopen_s(&f,path.c_str(),L"rb");
            unsigned char sig[8]{};
            const bool png=f && std::fread(sig,1,8,f)==8 && sig[0]==0x89 && sig[1]=='P' && sig[2]=='N' && sig[3]=='G';
            if (f) std::fclose(f);
            std::printf("%s eye capture png=%d size=%lu\n",png?"PASS":"FAIL",png?1:0,a.nFileSizeLow);
            DeleteFileW(path.c_str());
            return png ? 0 : 1;
        }
        Sleep(50);
    }
    std::printf("FAIL: png not written\n");
    return 1;
}
