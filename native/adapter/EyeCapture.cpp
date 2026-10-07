#include "EyeCapture.h"

#include <objbase.h>
#include <wincodec.h>
#include <wrl/client.h>
#include <cstring>
#include <memory>
#include <thread>
#include <vector>

namespace kf2vr::adapter {
namespace {
using Microsoft::WRL::ComPtr;

struct Image {
    std::wstring path;
    unsigned width=0, height=0;
    bool bgra=false;
    std::vector<std::uint8_t> pixels; // Tightly packed, 4 bytes per pixel.
};

void WritePng(std::unique_ptr<Image> image) {
    const HRESULT init=CoInitializeEx(nullptr,COINIT_MULTITHREADED);
    {
        ComPtr<IWICImagingFactory> factory;
        ComPtr<IWICStream> stream;
        ComPtr<IWICBitmapEncoder> encoder;
        ComPtr<IWICBitmapFrameEncode> frame;
        WICPixelFormatGUID format=image->bgra ? GUID_WICPixelFormat32bppBGRA : GUID_WICPixelFormat32bppRGBA;
        if (SUCCEEDED(CoCreateInstance(CLSID_WICImagingFactory,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&factory))) &&
            SUCCEEDED(factory->CreateStream(&stream)) &&
            SUCCEEDED(stream->InitializeFromFilename(image->path.c_str(),GENERIC_WRITE)) &&
            SUCCEEDED(factory->CreateEncoder(GUID_ContainerFormatPng,nullptr,&encoder)) &&
            SUCCEEDED(encoder->Initialize(stream.Get(),WICBitmapEncoderNoCache)) &&
            SUCCEEDED(encoder->CreateNewFrame(&frame,nullptr)) &&
            SUCCEEDED(frame->Initialize(nullptr)) &&
            SUCCEEDED(frame->SetSize(image->width,image->height)) &&
            SUCCEEDED(frame->SetPixelFormat(&format))) {
            const UINT stride=image->width*4;
            if (SUCCEEDED(frame->WritePixels(image->height,stride,stride*image->height,image->pixels.data())))
                if (SUCCEEDED(frame->Commit())) encoder->Commit();
        }
    }
    if (SUCCEEDED(init)) CoUninitialize();
}
} // namespace

bool CaptureTexturePng(ID3D11Device* device, ID3D11DeviceContext* context,
                       ID3D11Texture2D* texture, const std::wstring& path, std::string& error) {
    if (!device || !context || !texture) { error="capture input missing"; return false; }
    D3D11_TEXTURE2D_DESC d{}; texture->GetDesc(&d);
    bool bgra=false;
    switch (d.Format) {
    case DXGI_FORMAT_R8G8B8A8_TYPELESS: case DXGI_FORMAT_R8G8B8A8_UNORM: case DXGI_FORMAT_R8G8B8A8_UNORM_SRGB: break;
    case DXGI_FORMAT_B8G8R8A8_TYPELESS: case DXGI_FORMAT_B8G8R8A8_UNORM: case DXGI_FORMAT_B8G8R8A8_UNORM_SRGB:
    case DXGI_FORMAT_B8G8R8X8_TYPELESS: case DXGI_FORMAT_B8G8R8X8_UNORM: case DXGI_FORMAT_B8G8R8X8_UNORM_SRGB:
        bgra=true; break;
    default: error="capture format unsupported"; return false;
    }
    if (d.SampleDesc.Count!=1 || !d.Width || !d.Height) { error="capture texture unsupported"; return false; }
    D3D11_TEXTURE2D_DESC s=d;
    s.MipLevels=1; s.ArraySize=1; s.Usage=D3D11_USAGE_STAGING; s.BindFlags=0;
    s.CPUAccessFlags=D3D11_CPU_ACCESS_READ; s.MiscFlags=0;
    ComPtr<ID3D11Texture2D> staging;
    if (FAILED(device->CreateTexture2D(&s,nullptr,&staging))) { error="capture staging texture failed"; return false; }
    context->CopySubresourceRegion(staging.Get(),0,0,0,0,texture,0,nullptr);
    D3D11_MAPPED_SUBRESOURCE map{};
    if (FAILED(context->Map(staging.Get(),0,D3D11_MAP_READ,0,&map))) { error="capture map failed"; return false; }
    auto image=std::make_unique<Image>();
    image->path=path; image->width=d.Width; image->height=d.Height; image->bgra=bgra;
    image->pixels.resize(static_cast<std::size_t>(d.Width)*d.Height*4);
    for (unsigned y=0;y<d.Height;++y) {
        auto* row=image->pixels.data()+static_cast<std::size_t>(y)*d.Width*4;
        std::memcpy(row,static_cast<const std::uint8_t*>(map.pData)+static_cast<std::size_t>(y)*map.RowPitch,d.Width*4);
        for (unsigned x=0;x<d.Width;++x) row[x*4+3]=255; // Opaque: alpha holds render data, not coverage.
    }
    context->Unmap(staging.Get(),0);
    std::thread(WritePng,std::move(image)).detach();
    return true;
}
} // namespace kf2vr::adapter
