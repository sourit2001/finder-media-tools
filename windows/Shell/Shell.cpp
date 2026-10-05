#include <windows.h>
#include <shobjidl.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <wrl.h>
#include <atomic>
#include <string>
#include <vector>
#include <algorithm>
#include <cwctype>
#include <new>

using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Make;
using Microsoft::WRL::RuntimeClass;
using Microsoft::WRL::RuntimeClassFlags;
using Microsoft::WRL::ClassicCom;
static HMODULE moduleHandle;
static std::atomic<long> objects{0};
static const CLSID CommandId = {0x731ba7e4, 0xa1cc, 0x4378, {0xb7,0xb5,0xb9,0x75,0x55,0x60,0xda,0x12}};

struct Counted { Counted() { ++objects; } ~Counted() { --objects; } };

static HRESULT Selection(IShellItemArray* items, std::vector<std::wstring>& paths, bool& onlyVideo, bool& onlyAudio) {
    if (!items) return E_INVALIDARG;
    DWORD count = 0;
    HRESULT hr = items->GetCount(&count);
    if (FAILED(hr)) return hr;
    if (count == 0 || count > 1000) return E_INVALIDARG;
    onlyVideo = onlyAudio = true;
    for (DWORD i = 0; i < count; ++i) {
        ComPtr<IShellItem> item;
        if (FAILED(hr = items->GetItemAt(i, &item))) return hr;
        PWSTR raw = nullptr;
        if (FAILED(hr = item->GetDisplayName(SIGDN_FILESYSPATH, &raw))) return hr;
        std::wstring path(raw);
        CoTaskMemFree(raw);
        std::wstring ext(PathFindExtensionW(path.c_str()));
        std::transform(ext.begin(), ext.end(), ext.begin(), [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
        const bool video = ext == L".mp4" || ext == L".mov" || ext == L".m4v" || ext == L".mkv" || ext == L".webm" || ext == L".avi";
        const bool audio = ext == L".mp3" || ext == L".m4a" || ext == L".aac" || ext == L".wav" || ext == L".flac" || ext == L".ogg" || ext == L".oga" || ext == L".opus" || ext == L".aif" || ext == L".aiff";
        SFGAOF attributes = 0;
        if (FAILED(hr = item->GetAttributes(SFGAO_FOLDER | SFGAO_FILESYSTEM, &attributes))) return hr;
        if (!video && !audio) return E_INVALIDARG;
        if ((attributes & SFGAO_FOLDER) || !(attributes & SFGAO_FILESYSTEM)) return E_INVALIDARG;
        if (path.find_first_of(L"\r\n") != std::wstring::npos) return E_INVALIDARG;
        onlyVideo &= video; onlyAudio &= audio;
        paths.push_back(std::move(path));
    }
    return S_OK;
}

class Command;
class CommandEnumerator : public RuntimeClass<RuntimeClassFlags<ClassicCom>, IEnumExplorerCommand>, private Counted {
    std::vector<ComPtr<IExplorerCommand>> commands;
    size_t cursor = 0;
public:
    CommandEnumerator(std::vector<ComPtr<IExplorerCommand>> entries, size_t position = 0) : commands(std::move(entries)), cursor(position) {}
    IFACEMETHODIMP Next(ULONG count, IExplorerCommand** result, ULONG* fetched) override {
        if (!result || (!fetched && count != 1)) return E_POINTER;
        ULONG completed = 0;
        while (completed < count && cursor < commands.size()) {
            result[completed] = commands[cursor++].Get();
            result[completed++]->AddRef();
        }
        if (fetched) *fetched = completed;
        return completed == count ? S_OK : S_FALSE;
    }
    IFACEMETHODIMP Skip(ULONG count) override {
        const size_t available = commands.size() - cursor;
        cursor += std::min(static_cast<size_t>(count), available);
        return count <= available ? S_OK : S_FALSE;
    }
    IFACEMETHODIMP Reset() override { cursor = 0; return S_OK; }
    IFACEMETHODIMP Clone(IEnumExplorerCommand** result) override {
        if (!result) return E_POINTER;
        auto copy = Make<CommandEnumerator>(commands, cursor);
        return copy ? copy.CopyTo(result) : E_OUTOFMEMORY;
    }
};

class Command : public RuntimeClass<RuntimeClassFlags<ClassicCom>, IExplorerCommand>, private Counted {
    std::wstring format;
public:
    explicit Command(std::wstring outputFormat = L"") : format(std::move(outputFormat)) {}
    IFACEMETHODIMP GetTitle(IShellItemArray* items, PWSTR* title) override {
        if (!title) return E_POINTER;
        if (!format.empty()) {
            std::wstring upper = format;
            std::transform(upper.begin(), upper.end(), upper.begin(), [](wchar_t c) { return static_cast<wchar_t>(std::towupper(c)); });
            return SHStrDupW(upper.c_str(), title);
        }
        // Keep the app name visible; Windows may group app commands into a flyout.
        std::vector<std::wstring> paths; bool video = false, audio = false;
        Selection(items, paths, video, audio);
        return SHStrDupW(video ? L"ConvertRight - Extract Audio As" : audio ? L"ConvertRight - Convert Audio To" : L"ConvertRight - Convert to Audio", title);
    }
    IFACEMETHODIMP GetIcon(IShellItemArray*, PWSTR* icon) override { if (!icon) return E_POINTER; *icon = nullptr; return E_NOTIMPL; }
    IFACEMETHODIMP GetToolTip(IShellItemArray*, PWSTR* tip) override { if (!tip) return E_POINTER; *tip = nullptr; return E_NOTIMPL; }
    IFACEMETHODIMP GetCanonicalName(GUID* name) override {
        if (!name) return E_POINTER;
        *name = CommandId;
        name->Data1 += format == L"mp3" ? 1 : format == L"m4a" ? 2 : format == L"wav" ? 3 : 0;
        return S_OK;
    }
    IFACEMETHODIMP GetState(IShellItemArray* items, BOOL, EXPCMDSTATE* state) override {
        if (!state) return E_POINTER;
        std::vector<std::wstring> paths; bool video, audio;
        *state = SUCCEEDED(Selection(items, paths, video, audio)) ? ECS_ENABLED : ECS_HIDDEN;
        return S_OK;
    }
    IFACEMETHODIMP GetFlags(EXPCMDFLAGS* flags) override { if (!flags) return E_POINTER; *flags = format.empty() ? ECF_HASSUBCOMMANDS : ECF_DEFAULT; return S_OK; }
    IFACEMETHODIMP EnumSubCommands(IEnumExplorerCommand** result) override {
        if (!result) return E_POINTER;
        *result = nullptr;
        if (!format.empty()) return E_NOTIMPL;
        std::vector<ComPtr<IExplorerCommand>> children;
        for (const auto* outputFormat : {L"mp3", L"m4a", L"wav"}) {
            auto child = Make<Command>(std::wstring(outputFormat));
            if (!child) return E_OUTOFMEMORY;
            ComPtr<IExplorerCommand> command;
            HRESULT hr = child.As(&command);
            if (FAILED(hr)) return hr;
            children.push_back(std::move(command));
        }
        auto enumerator = Make<CommandEnumerator>(std::move(children));
        return enumerator ? enumerator.CopyTo(result) : E_OUTOFMEMORY;
    }
    IFACEMETHODIMP Invoke(IShellItemArray* items, IBindCtx*) override {
        if (format.empty()) return E_NOTIMPL;
        std::vector<std::wstring> paths; bool video, audio;
        HRESULT hr = Selection(items, paths, video, audio);
        if (FAILED(hr)) return hr;
        PWSTR local = nullptr;
        if (FAILED(hr = SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local))) return hr;
        std::wstring directory = std::wstring(local) + L"\\ConvertRight";
        CoTaskMemFree(local);
        if (!CreateDirectoryW(directory.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) return HRESULT_FROM_WIN32(GetLastError());
        directory += L"\\Requests";
        if (!CreateDirectoryW(directory.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) return HRESULT_FROM_WIN32(GetLastError());
        GUID id; if (FAILED(hr = CoCreateGuid(&id))) return hr;
        wchar_t guid[40]; StringFromGUID2(id, guid, 40);
        const std::wstring request = directory + L"\\" + guid + L".request";
        HANDLE file = CreateFileW(request.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (file == INVALID_HANDLE_VALUE) return HRESULT_FROM_WIN32(GetLastError());
        std::wstring content = L"\xFEFF" + format + L"\r\n";
        for (const auto& path : paths) content += path + L"\r\n";
        const DWORD bytes = static_cast<DWORD>(content.size() * sizeof(wchar_t));
        DWORD written = 0;
        const BOOL saved = WriteFile(file, content.data(), bytes, &written, nullptr);
        const DWORD writeError = saved ? ERROR_WRITE_FAULT : GetLastError();
        CloseHandle(file);
        if (!saved || written != bytes) { DeleteFileW(request.c_str()); return HRESULT_FROM_WIN32(writeError); }
        wchar_t modulePath[32768];
        const DWORD length = GetModuleFileNameW(moduleHandle, modulePath, 32768);
        if (length == 0 || length >= 32768) { DeleteFileW(request.c_str()); return E_FAIL; }
        const std::wstring dll(modulePath, length);
        const std::wstring executable = dll.substr(0, dll.find_last_of(L"\\/") + 1) + L"ConvertRight.exe";
        std::wstring arguments = L"\"" + executable + L"\" --request \"" + request + L"\"";
        STARTUPINFOW startup{}; startup.cb = sizeof(startup);
        PROCESS_INFORMATION process{};
        if (!CreateProcessW(executable.c_str(), arguments.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process)) {
            const DWORD error = GetLastError(); DeleteFileW(request.c_str()); return HRESULT_FROM_WIN32(error);
        }
        CloseHandle(process.hThread); CloseHandle(process.hProcess);
        return S_OK;
    }
};

class Factory : public RuntimeClass<RuntimeClassFlags<ClassicCom>, IClassFactory>, private Counted {
public:
    IFACEMETHODIMP CreateInstance(IUnknown* outer, REFIID iid, void** result) override {
        if (!result) return E_POINTER;
        *result = nullptr;
        if (outer) return CLASS_E_NOAGGREGATION;
        auto command = Make<Command>();
        return command ? command->QueryInterface(iid, result) : E_OUTOFMEMORY;
    }
    IFACEMETHODIMP LockServer(BOOL lock) override { if (lock) ++objects; else --objects; return S_OK; }
};

extern "C" HRESULT __stdcall DllGetClassObject(REFCLSID clsid, REFIID iid, void** result) {
    if (!result) return E_POINTER;
    *result = nullptr;
    if (clsid != CommandId) return CLASS_E_CLASSNOTAVAILABLE;
    try {
        auto factory = Make<Factory>();
        return factory ? factory->QueryInterface(iid, result) : E_OUTOFMEMORY;
    } catch (const std::bad_alloc&) { return E_OUTOFMEMORY; }
}
extern "C" HRESULT __stdcall DllCanUnloadNow() { return objects == 0 ? S_OK : S_FALSE; }
BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) { moduleHandle = instance; DisableThreadLibraryCalls(instance); }
    return TRUE;
}
