#include "IMediaProvider.h"

#ifdef PLATFORM_WINDOWS
#include "WindowsMediaProvider.h"
#elif defined(PLATFORM_MACOS)
#include "MacOSMediaProvider.h"
#elif defined(PLATFORM_LINUX)
#include "LinuxMediaProvider.h"
#endif

std::shared_ptr<IMediaProvider> IMediaProvider::create() {
#ifdef PLATFORM_WINDOWS
    return std::make_shared<WindowsMediaProvider>();
#elif defined(PLATFORM_MACOS)
    return std::make_shared<MacOSMediaProvider>();
#elif defined(PLATFORM_LINUX)
    return std::make_shared<LinuxMediaProvider>();
#else
    return nullptr;
#endif
} 