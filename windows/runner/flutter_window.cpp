#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <cmath>
#include <optional>
#include <shobjidl.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

// 16x16 green status overlay for the Windows taskbar button.
HICON CreateGreenOverlayIcon() {
  const int size = 16;
  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = size;
  bmi.bmiHeader.biHeight = -size;  // top-down
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;

  void* bits = nullptr;
  HDC screen = GetDC(nullptr);
  HBITMAP color = CreateDIBSection(screen, &bmi, DIB_RGB_COLORS, &bits, nullptr, 0);
  ReleaseDC(nullptr, screen);
  if (!color || !bits) {
    return nullptr;
  }

  auto* pixels = static_cast<UINT32*>(bits);
  const float cx = (size - 1) * 0.5f;
  const float cy = (size - 1) * 0.5f;
  const float outer_r = size * 0.48f;
  const float inner_r = size * 0.34f;
  for (int y = 0; y < size; ++y) {
    for (int x = 0; x < size; ++x) {
      const float dx = x - cx;
      const float dy = y - cy;
      const float d = sqrtf(dx * dx + dy * dy);
      UINT32 px = 0x00000000;
      if (d <= outer_r) {
        // White ring, green fill — readable on light and dark taskbars.
        if (d >= inner_r) {
          px = 0xFFFFFFFFu;
        } else {
          px = 0xFF34C759u;  // system-like green
        }
      }
      pixels[y * size + x] = px;
    }
  }

  ICONINFO info = {};
  info.fIcon = TRUE;
  info.hbmColor = color;
  info.hbmMask = CreateBitmap(size, size, 1, 1, nullptr);
  HICON icon = CreateIconIndirect(&info);
  DeleteObject(info.hbmMask);
  DeleteObject(color);
  return icon;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {
  if (overlay_icon_) {
    DestroyIcon(overlay_icon_);
    overlay_icon_ = nullptr;
  }
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  RegisterDesktopStatusChannel();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    // this->Show(); window_manager hidden at launch
    "";
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::RegisterDesktopStatusChannel() {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "com.hiddify.app/desktop_status",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "setConnected") {
          bool connected = false;
          if (const auto* args =
                  std::get_if<flutter::EncodableMap>(call.arguments())) {
            auto it = args->find(flutter::EncodableValue("connected"));
            if (it != args->end()) {
              if (const auto* flag = std::get_if<bool>(&it->second)) {
                connected = *flag;
              }
            }
          }
          SetTaskbarConnectedOverlay(connected);
          result->Success();
          return;
        }
        result->NotImplemented();
      });

  // Channel keeps itself alive via the engine messenger; release local unique_ptr
  // ownership after installing the handler by leaking intentionally into engine.
  channel.release();
}

void FlutterWindow::SetTaskbarConnectedOverlay(bool connected) {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }

  ITaskbarList3* taskbar = nullptr;
  if (FAILED(CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                              IID_PPV_ARGS(&taskbar))) ||
      !taskbar) {
    return;
  }
  taskbar->HrInit();

  if (connected) {
    if (!overlay_icon_) {
      overlay_icon_ = CreateGreenOverlayIcon();
    }
    if (overlay_icon_) {
      taskbar->SetOverlayIcon(hwnd, overlay_icon_, L"Connected");
    }
  } else {
    taskbar->SetOverlayIcon(hwnd, nullptr, L"");
  }
  taskbar->Release();
}

void FlutterWindow::OnDestroy() {
  SetTaskbarConnectedOverlay(false);
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
