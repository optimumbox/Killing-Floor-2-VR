#pragma once
#include <d3d11.h>
#include <cstdint>
#include <string>

namespace kf2vr::adapter {
// Diagnostic: copies a colour texture to CPU memory on the render thread and
// writes it as an opaque PNG on a worker thread (COM/WIC never touch the
// render thread). Each call stalls for one GPU readback; use sparingly.
bool CaptureTexturePng(ID3D11Device* device, ID3D11DeviceContext* context,
                       ID3D11Texture2D* texture, const std::wstring& path, std::string& error);
}
