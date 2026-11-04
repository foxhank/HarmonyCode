// N-API bridge to hiSH's prebuilt QEMU (libqemu-system-aarch64.so).
// Adapted from hiSH (https://github.com/harmoninux/hiSH, MIT License): QEMU runs on its own thread,
// and the guest's serial console is a unix socket that we read and write as raw bytes.
//
// QEMU keeps global state, so a VM can be started once per process.

#include "napi/native_api.h"
#include "hilog/log.h"

#include <arpa/inet.h>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <dlfcn.h>
#include <mutex>
#include <netinet/in.h>
#include <poll.h>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <thread>
#include <unistd.h>
#include <vector>

#define HLOGI(...) OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN_HISH, LOG_TAG_HISH, __VA_ARGS__)
#define HLOGE(...) OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN_HISH, LOG_TAG_HISH, __VA_ARGS__)

namespace {

constexpr unsigned int LOG_DOMAIN_HISH = 0x3301;
constexpr const char *LOG_TAG_HISH = "HiSH";
constexpr const char *QEMU_JIT_LIB = "libqemu-system-aarch64.so";
constexpr const char *QEMU_TCI_LIB = "libqemu-system-aarch64-tci.so";
constexpr const char *QEMU_ENTRY = "qemu_system_entry";
constexpr int SOCKET_POLL_MS = 50;
constexpr int SOCKET_WAIT_MS = 30000;
constexpr int READ_POLL_MS = 200;
constexpr size_t READ_CHUNK = 4096;

using QemuEntry = int (*)(int, const char **);

struct Chunk {
    std::vector<uint8_t> bytes;
};

std::atomic<bool> g_started{false};
std::atomic<bool> g_qemuRunning{false};
std::mutex g_fdMutex;
int g_serialFd = -1;

std::string GetString(napi_env env, napi_value value)
{
    size_t size = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &size) != napi_ok) {
        return "";
    }
    std::string out(size, '\0');
    napi_get_value_string_utf8(env, value, &out[0], size + 1, &size);
    return out;
}

bool GetBool(napi_env env, napi_value value, bool fallback)
{
    bool out = fallback;
    napi_valuetype type;
    if (napi_typeof(env, value, &type) == napi_ok && type == napi_boolean) {
        napi_get_value_bool(env, value, &out);
    }
    return out;
}

napi_value MakeString(napi_env env, const std::string &s)
{
    napi_value v = nullptr;
    napi_create_string_utf8(env, s.c_str(), s.size(), &v);
    return v;
}

napi_value MakeBool(napi_env env, bool b)
{
    napi_value v = nullptr;
    napi_get_boolean(env, b, &v);
    return v;
}

/** Loads QEMU once. Without JIT the interpreter (TCI) build is preferred when it is bundled. */
QemuEntry LoadQemu(bool useJit, std::string &error)
{
    static void *handle = nullptr;
    static QemuEntry entry = nullptr;
    if (entry != nullptr) {
        return entry;
    }
    if (!useJit) {
        handle = dlopen(QEMU_TCI_LIB, RTLD_LAZY);
    }
    if (handle == nullptr) {
        handle = dlopen(QEMU_JIT_LIB, RTLD_LAZY);
    }
    if (handle == nullptr) {
        const char *e = dlerror();
        error = e != nullptr ? e : "dlopen failed";
        return nullptr;
    }
    entry = reinterpret_cast<QemuEntry>(dlsym(handle, QEMU_ENTRY));
    if (entry == nullptr) {
        error = std::string("missing symbol ") + QEMU_ENTRY;
    }
    return entry;
}

void CallOutput(napi_env env, napi_value cb, void *, void *data)
{
    auto *chunk = static_cast<Chunk *>(data);
    if (env != nullptr && cb != nullptr) {
        void *buf = nullptr;
        napi_value ab = nullptr;
        if (napi_create_arraybuffer(env, chunk->bytes.size(), &buf, &ab) == napi_ok) {
            memcpy(buf, chunk->bytes.data(), chunk->bytes.size());
            napi_value undefined = nullptr;
            napi_get_undefined(env, &undefined);
            napi_call_function(env, undefined, cb, 1, &ab, nullptr);
        }
    }
    delete chunk;
}

void CallExit(napi_env env, napi_value cb, void *, void *data)
{
    auto *code = static_cast<int *>(data);
    if (env != nullptr && cb != nullptr) {
        napi_value arg = nullptr;
        napi_create_int32(env, *code, &arg);
        napi_value undefined = nullptr;
        napi_get_undefined(env, &undefined);
        napi_call_function(env, undefined, cb, 1, &arg, nullptr);
    }
    delete code;
}

/** Waits for QEMU to create the serial socket, then connects. Returns -1 on failure. */
int ConnectSerial(const std::string &path)
{
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    if (path.size() >= sizeof(addr.sun_path)) {
        HLOGE("serial socket path too long: %{public}s", path.c_str());
        return -1;
    }
    strncpy(addr.sun_path, path.c_str(), sizeof(addr.sun_path) - 1);

    for (int waited = 0; waited < SOCKET_WAIT_MS && g_qemuRunning.load(); waited += SOCKET_POLL_MS) {
        if (access(path.c_str(), F_OK) == 0) {
            int fd = socket(AF_UNIX, SOCK_STREAM, 0);
            if (fd < 0) {
                HLOGE("socket() failed: %{public}d", errno);
                return -1;
            }
            if (connect(fd, reinterpret_cast<struct sockaddr *>(&addr), sizeof(addr)) == 0) {
                return fd;
            }
            close(fd);
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(SOCKET_POLL_MS));
    }
    HLOGE("serial socket not available: %{public}s", path.c_str());
    return -1;
}

void SerialReader(std::string path, napi_threadsafe_function onOutput)
{
    int fd = ConnectSerial(path);
    if (fd >= 0) {
        {
            std::lock_guard<std::mutex> lock(g_fdMutex);
            g_serialFd = fd;
        }
        uint8_t buf[READ_CHUNK];
        while (true) {
            struct pollfd pfd = {fd, POLLIN, 0};
            int ready = poll(&pfd, 1, READ_POLL_MS);
            if (ready < 0 && errno != EINTR) {
                break;
            }
            if (ready <= 0) {
                continue;
            }
            ssize_t n = read(fd, buf, sizeof(buf));
            if (n <= 0) {
                break;
            }
            auto *chunk = new Chunk{std::vector<uint8_t>(buf, buf + n)};
            if (napi_call_threadsafe_function(onOutput, chunk, napi_tsfn_blocking) != napi_ok) {
                delete chunk;
                break;
            }
        }
        std::lock_guard<std::mutex> lock(g_fdMutex);
        close(fd);
        g_serialFd = -1;
    }
    napi_release_threadsafe_function(onOutput, napi_tsfn_release);
    HLOGI("serial reader finished");
}

void QemuThread(QemuEntry entry, std::vector<std::string> args, napi_threadsafe_function onExit)
{
    std::vector<const char *> argv;
    argv.reserve(args.size() + 1);
    for (const auto &a : args) {
        argv.push_back(a.c_str());
    }
    argv.push_back(nullptr);
    int code = entry(static_cast<int>(args.size()), argv.data());
    g_qemuRunning.store(false);
    HLOGI("qemu exited: %{public}d", code);
    napi_call_threadsafe_function(onExit, new int(code), napi_tsfn_blocking);
    napi_release_threadsafe_function(onExit, napi_tsfn_release);
}

napi_threadsafe_function MakeTsfn(napi_env env, napi_value fn, const char *name, napi_threadsafe_function_call_js cb)
{
    napi_value resource = MakeString(env, name);
    napi_threadsafe_function tsfn = nullptr;
    if (napi_create_threadsafe_function(env, fn, nullptr, resource, 0, 1, nullptr, nullptr, nullptr, cb, &tsfn) !=
        napi_ok) {
        return nullptr;
    }
    napi_unref_threadsafe_function(env, tsfn);
    return tsfn;
}

/** isAvailable(useJit: boolean): boolean */
napi_value IsAvailable(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    std::string error;
    bool ok = LoadQemu(argc > 0 ? GetBool(env, argv[0], true) : true, error) != nullptr;
    if (!ok) {
        HLOGE("QEMU unavailable: %{public}s", error.c_str());
    }
    return MakeBool(env, ok);
}

/** startVm(args, serialSocket, useJit, onOutput, onExit): string — '' when started, else the reason. */
napi_value StartVm(napi_env env, napi_callback_info info)
{
    size_t argc = 5;
    napi_value argv[5] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 5) {
        return MakeString(env, "startVm: expected 5 arguments");
    }
    bool isArray = false;
    napi_is_array(env, argv[0], &isArray);
    if (!isArray) {
        return MakeString(env, "startVm: args must be an array");
    }
    uint32_t count = 0;
    napi_get_array_length(env, argv[0], &count);
    std::vector<std::string> args;
    for (uint32_t i = 0; i < count; i++) {
        napi_value item = nullptr;
        napi_get_element(env, argv[0], i, &item);
        args.push_back(GetString(env, item));
    }
    std::string socketPath = GetString(env, argv[1]);
    bool useJit = GetBool(env, argv[2], true);

    bool expected = false;
    if (!g_started.compare_exchange_strong(expected, true)) {
        return MakeString(env, "a VM was already started in this process");
    }
    std::string error;
    QemuEntry entry = LoadQemu(useJit, error);
    if (entry == nullptr) {
        g_started.store(false);
        return MakeString(env, error);
    }
    napi_threadsafe_function onOutput = MakeTsfn(env, argv[3], "hish_output", CallOutput);
    napi_threadsafe_function onExit = MakeTsfn(env, argv[4], "hish_exit", CallExit);
    if (onOutput == nullptr || onExit == nullptr) {
        g_started.store(false);
        return MakeString(env, "startVm: invalid callbacks");
    }
    g_qemuRunning.store(true);
    std::thread(QemuThread, entry, args, onExit).detach();
    std::thread(SerialReader, socketPath, onOutput).detach();
    return MakeString(env, "");
}

/** write(text: string): number — bytes written, or -1 when the console isn't connected. */
napi_value Write(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    std::string data = argc > 0 ? GetString(env, argv[0]) : "";
    int written = 0;
    {
        std::lock_guard<std::mutex> lock(g_fdMutex);
        if (g_serialFd < 0) {
            written = -1;
        } else {
            while (written < static_cast<int>(data.size())) {
                ssize_t n = write(g_serialFd, data.data() + written, data.size() - written);
                if (n < 0) {
                    if (errno == EINTR) {
                        continue;
                    }
                    HLOGE("serial write failed: %{public}d", errno);
                    break;
                }
                written += static_cast<int>(n);
            }
        }
    }
    napi_value result = nullptr;
    napi_create_int32(env, written, &result);
    return result;
}

/** isPortFree(port: number): boolean — true when 127.0.0.1:port can be bound. */
napi_value IsPortFree(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t port = -1;
    if (argc < 1 || napi_get_value_int32(env, argv[0], &port) != napi_ok || port <= 0 || port > 65535) {
        return MakeBool(env, false);
    }
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        return MakeBool(env, false);
    }
    int reuse = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons(static_cast<uint16_t>(port));
    bool free = bind(fd, reinterpret_cast<struct sockaddr *>(&addr), sizeof(addr)) == 0;
    close(fd);
    return MakeBool(env, free);
}

} // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"isAvailable", nullptr, IsAvailable, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startVm", nullptr, StartVm, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"write", nullptr, Write, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isPortFree", nullptr, IsPortFree, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module g_hishModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "hish",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterHishModule(void)
{
    napi_module_register(&g_hishModule);
}
