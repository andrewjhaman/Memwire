
#import "Windows";

psapi :: #system_library "psapi";

PROCESS_VM_READ :: 0x0010;
PROCESS_QUERY_INFORMATION :: 0x0400;


EnumProcesses :: (lpidProcess : *DWORD, cb : DWORD, lpcbNeeded : *DWORD) -> BOOL #foreign psapi;
EnumProcessModules :: (hProcess : HANDLE, lphModule : *HMODULE, cb : DWORD, lpcbNeeded : *DWORD) -> BOOL #foreign psapi;

GetModuleBaseNameW :: (hProcess : HANDLE, hModule : HMODULE, lpBaseName : LPSTR, nSize : DWORD) -> DWORD #foreign psapi;
