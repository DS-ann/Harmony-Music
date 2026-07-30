#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <sddl.h>

#include <cstdlib>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

// auth0_flutter reads this value while a Windows browser login is pending.
// This generated plugin header is present after `flutter pub get`.
#include "../flutter/ephemeral/.plugin_symlinks/auth0_flutter/windows/plugin_startup_url_lock.h"

namespace {

constexpr wchar_t kSingleInstanceMutex[] =
    L"harmony_music_single_instance_mutex";
constexpr wchar_t kRedirectPipeName[] =
    L"\\\\.\\pipe\\harmony_music_auth0_callback";
constexpr wchar_t kCallbackPrefix[] = L"harmonymusic://callback";
constexpr wchar_t kProtocolRegistryKey[] =
    L"Software\\Classes\\harmonymusic";
constexpr wchar_t kProtocolCommandRegistryKey[] =
    L"Software\\Classes\\harmonymusic\\shell\\open\\command";

bool HasRegisteredProtocolHandler() {
  DWORD value_size = 0;
  const LSTATUS status =
      RegGetValueW(HKEY_CURRENT_USER, kProtocolCommandRegistryKey, nullptr,
                   RRF_RT_REG_SZ, nullptr, nullptr, &value_size);
  return status == ERROR_SUCCESS && value_size > sizeof(wchar_t);
}

std::wstring CurrentExecutablePath() {
  std::vector<wchar_t> buffer(MAX_PATH);
  while (true) {
    const DWORD length = GetModuleFileNameW(
        nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0) {
      return {};
    }
    if (length < buffer.size() - 1) {
      return std::wstring(buffer.data(), length);
    }
    buffer.resize(buffer.size() * 2);
  }
}

bool SetDefaultRegistryString(HKEY key, const std::wstring& value) {
  const auto* bytes = reinterpret_cast<const BYTE*>(value.c_str());
  const DWORD byte_count =
      static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t));
  return RegSetValueExW(key, nullptr, 0, REG_SZ, bytes, byte_count) ==
         ERROR_SUCCESS;
}

void RegisterProtocolHandlerIfMissing() {
  // The installer owns the normal association. Preserve it when present so a
  // local Debug build never hijacks callbacks from an installed Release app.
  if (HasRegisteredProtocolHandler()) {
    return;
  }

  const std::wstring executable = CurrentExecutablePath();
  if (executable.empty()) {
    return;
  }

  HKEY protocol_key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kProtocolRegistryKey, 0, nullptr, 0,
                      KEY_SET_VALUE, nullptr, &protocol_key, nullptr) !=
      ERROR_SUCCESS) {
    return;
  }
  const bool protocol_name_written =
      SetDefaultRegistryString(protocol_key, L"URL:Harmony Music Protocol");
  const wchar_t empty_value[] = L"";
  const bool url_protocol_written =
      RegSetValueExW(protocol_key, L"URL Protocol", 0, REG_SZ,
                     reinterpret_cast<const BYTE*>(empty_value),
                     sizeof(empty_value)) == ERROR_SUCCESS;
  RegCloseKey(protocol_key);
  if (!protocol_name_written || !url_protocol_written) {
    return;
  }

  HKEY command_key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kProtocolCommandRegistryKey, 0,
                      nullptr, 0, KEY_SET_VALUE, nullptr, &command_key,
                      nullptr) != ERROR_SUCCESS) {
    return;
  }
  const std::wstring command = L"\"" + executable + L"\" \"%1\"";
  SetDefaultRegistryString(command_key, command);
  RegCloseKey(command_key);
}

// Give the callback pipe read/write access only to the signed-in Windows user.
// A protocol activation is untrusted input, so the runner also checks its exact
// prefix before exposing it to auth0_flutter.
PSECURITY_DESCRIPTOR BuildCurrentUserSecurityDescriptor() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
    return nullptr;
  }

  DWORD token_user_size = 0;
  GetTokenInformation(token, TokenUser, nullptr, 0, &token_user_size);
  if (GetLastError() != ERROR_INSUFFICIENT_BUFFER) {
    CloseHandle(token);
    return nullptr;
  }

  std::vector<BYTE> token_user_buffer(token_user_size);
  auto* token_user = reinterpret_cast<PTOKEN_USER>(token_user_buffer.data());
  if (!GetTokenInformation(token, TokenUser, token_user, token_user_size,
                           &token_user_size)) {
    CloseHandle(token);
    return nullptr;
  }
  CloseHandle(token);

  LPWSTR sid = nullptr;
  if (!ConvertSidToStringSidW(token_user->User.Sid, &sid)) {
    return nullptr;
  }

  std::wstring descriptor = L"D:(A;;GRGW;;;";
  descriptor += sid;
  descriptor += L")";
  LocalFree(sid);

  PSECURITY_DESCRIPTOR security_descriptor = nullptr;
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
          descriptor.c_str(), SDDL_REVISION_1, &security_descriptor, nullptr)) {
    return nullptr;
  }
  return security_descriptor;
}

bool IsHarmonyCallback(const std::wstring& uri) {
  const size_t prefix_length = wcslen(kCallbackPrefix);
  return uri.size() >= prefix_length &&
         uri.compare(0, prefix_length, kCallbackPrefix) == 0;
}

void BringExistingWindowToFront() {
  const HWND window = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr);
  if (window != nullptr) {
    ShowWindow(window, SW_RESTORE);
    SetForegroundWindow(window);
  }
}

void ForwardToFirstInstance(const wchar_t* uri) {
  if (!WaitNamedPipeW(kRedirectPipeName, 2000)) {
    return;
  }

  HANDLE pipe = CreateFileW(kRedirectPipeName, GENERIC_WRITE, 0, nullptr,
                            OPEN_EXISTING, 0, nullptr);
  if (pipe == INVALID_HANDLE_VALUE && GetLastError() == ERROR_PIPE_BUSY &&
      WaitNamedPipeW(kRedirectPipeName, 2000)) {
    pipe = CreateFileW(kRedirectPipeName, GENERIC_WRITE, 0, nullptr,
                       OPEN_EXISTING, 0, nullptr);
  }

  if (pipe != INVALID_HANDLE_VALUE) {
    DWORD written = 0;
    const DWORD length =
        static_cast<DWORD>((wcslen(uri) + 1) * sizeof(wchar_t));
    WriteFile(pipe, uri, length, &written, nullptr);
    CloseHandle(pipe);
  }
}

void StartCallbackPipeServer() {
  std::thread([] {
    while (true) {
      PSECURITY_DESCRIPTOR security_descriptor =
          BuildCurrentUserSecurityDescriptor();
      if (security_descriptor == nullptr) {
        return;
      }

      SECURITY_ATTRIBUTES attributes = {};
      attributes.nLength = sizeof(attributes);
      attributes.lpSecurityDescriptor = security_descriptor;

      HANDLE pipe = CreateNamedPipeW(
          kRedirectPipeName, PIPE_ACCESS_INBOUND,
          PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT, 1, 0, 0, 0,
          &attributes);
      LocalFree(security_descriptor);
      if (pipe == INVALID_HANDLE_VALUE) {
        return;
      }

      const BOOL connected = ConnectNamedPipe(pipe, nullptr);
      if (connected || GetLastError() == ERROR_PIPE_CONNECTED) {
        wchar_t buffer[2048] = {};
        DWORD read = 0;
        const BOOL read_ok =
            ReadFile(pipe, buffer, sizeof(buffer) - sizeof(wchar_t), &read,
                     nullptr);
        if (read_ok && read % sizeof(wchar_t) == 0) {
          buffer[read / sizeof(wchar_t)] = L'\0';
          const std::wstring callback(buffer);
          if (IsHarmonyCallback(callback)) {
            auth0_flutter::WriteLockGuard lock(
                auth0_flutter::GetPluginUrlRwLock());
            if (lock.IsValid()) {
              SetEnvironmentVariableW(L"PLUGIN_STARTUP_URL", buffer);
            }
            BringExistingWindowToFront();
          }
        }
      }
      DisconnectNamedPipe(pipe);
      CloseHandle(pipe);
    }
  }).detach();
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  RegisterProtocolHandlerIfMissing();

  int argument_count = 0;
  LPWSTR* arguments = CommandLineToArgvW(GetCommandLineW(), &argument_count);
  std::wstring startup_uri;
  if (arguments != nullptr && argument_count > 1) {
    startup_uri = arguments[1];
  }
  if (arguments != nullptr) {
    LocalFree(arguments);
  }

  HANDLE mutex = CreateMutexW(nullptr, TRUE, kSingleInstanceMutex);
  const bool already_running = mutex != nullptr &&
                               GetLastError() == ERROR_ALREADY_EXISTS;
  if (already_running) {
    BringExistingWindowToFront();
    if (IsHarmonyCallback(startup_uri)) {
      ForwardToFirstInstance(startup_uri.c_str());
    }
    CloseHandle(mutex);
    return EXIT_SUCCESS;
  }

  if (IsHarmonyCallback(startup_uri)) {
    SetEnvironmentVariableW(L"PLUGIN_STARTUP_URL", startup_uri.c_str());
  } else {
    SetEnvironmentVariableW(L"PLUGIN_STARTUP_URL", L"");
  }
  StartCallbackPipeServer();

  flutter::DartProject project(L"data");
  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Harmony Music", origin, size)) {
    CloseHandle(mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  MSG message;
  while (::GetMessage(&message, nullptr, 0, 0)) {
    ::TranslateMessage(&message);
    ::DispatchMessage(&message);
  }

  CloseHandle(mutex);
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
