"""A child process under a Windows pseudoconsole (ConPTY), stdlib ctypes only: its C runtime sees a console, so its
stdout is not block-buffered. strip_vt turns a line of the console's output (VT sequences) back into its text."""
import ctypes, os, re, subprocess, threading
from ctypes import wintypes as w

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
HPCON = w.HANDLE


class COORD(ctypes.Structure):
    _fields_ = [("X", w.SHORT), ("Y", w.SHORT)]


class STARTUPINFOW(ctypes.Structure):
    _fields_ = [("cb", w.DWORD), ("lpReserved", w.LPWSTR), ("lpDesktop", w.LPWSTR), ("lpTitle", w.LPWSTR),
                ("dwX", w.DWORD), ("dwY", w.DWORD), ("dwXSize", w.DWORD), ("dwYSize", w.DWORD),
                ("dwXCountChars", w.DWORD), ("dwYCountChars", w.DWORD), ("dwFillAttribute", w.DWORD),
                ("dwFlags", w.DWORD), ("wShowWindow", w.WORD), ("cbReserved2", w.WORD),
                ("lpReserved2", ctypes.c_void_p), ("hStdInput", w.HANDLE), ("hStdOutput", w.HANDLE),
                ("hStdError", w.HANDLE)]


class STARTUPINFOEXW(ctypes.Structure):
    _fields_ = [("StartupInfo", STARTUPINFOW), ("lpAttributeList", ctypes.c_void_p)]


class PROCESS_INFORMATION(ctypes.Structure):
    _fields_ = [("hProcess", w.HANDLE), ("hThread", w.HANDLE), ("dwProcessId", w.DWORD), ("dwThreadId", w.DWORD)]


k32.CreatePseudoConsole.argtypes = [COORD, w.HANDLE, w.HANDLE, w.DWORD, ctypes.POINTER(HPCON)]
k32.CreatePseudoConsole.restype = ctypes.c_long
k32.ClosePseudoConsole.argtypes = [HPCON]
k32.CreatePipe.argtypes = [ctypes.POINTER(w.HANDLE), ctypes.POINTER(w.HANDLE), ctypes.c_void_p, w.DWORD]
k32.InitializeProcThreadAttributeList.argtypes = [ctypes.c_void_p, w.DWORD, w.DWORD, ctypes.POINTER(ctypes.c_size_t)]
k32.UpdateProcThreadAttribute.argtypes = [ctypes.c_void_p, w.DWORD, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t,
                                          ctypes.c_void_p, ctypes.c_void_p]
k32.CreateProcessW.argtypes = [w.LPCWSTR, w.LPWSTR, ctypes.c_void_p, ctypes.c_void_p, w.BOOL, w.DWORD,
                               ctypes.c_void_p, w.LPCWSTR, ctypes.c_void_p, ctypes.POINTER(PROCESS_INFORMATION)]
k32.ReadFile.argtypes = [w.HANDLE, ctypes.c_void_p, w.DWORD, ctypes.POINTER(w.DWORD), ctypes.c_void_p]
k32.WaitForSingleObject.argtypes = [w.HANDLE, w.DWORD]
k32.GetExitCodeProcess.argtypes = [w.HANDLE, ctypes.POINTER(w.DWORD)]
k32.TerminateProcess.argtypes = [w.HANDLE, w.UINT]
k32.CloseHandle.argtypes = [w.HANDLE]

PSEUDOCONSOLE = 0x00020016
EXTENDED_STARTUPINFO_PRESENT, CREATE_UNICODE_ENVIRONMENT = 0x80000, 0x400
# The console's output, token by token: a control sequence (CSI: parameters, final byte), an OSC string, other
# escapes, a carriage return, or a run of text.
TOKEN_RE = re.compile(rb"\x1b\[([0-?]*)[ -/]*([@-~])|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[()][0-9A-Za-z]|"
                      rb"\x1b[=>78DEHMc]|(\r)|([^\x1b\r]+)|\x1b")


class ConPty:
    """Popen-like: pid, poll(), wait(timeout), kill(), returncode; read() gives output bytes (b"" at the end)."""

    def __init__(self, argv, cwd, env, cols=32000, rows=50):
        hin_r, hin_w, hout_r, hout_w = w.HANDLE(), w.HANDLE(), w.HANDLE(), w.HANDLE()
        if not k32.CreatePipe(ctypes.byref(hin_r), ctypes.byref(hin_w), None, 0) or \
                not k32.CreatePipe(ctypes.byref(hout_r), ctypes.byref(hout_w), None, 0):
            raise ctypes.WinError(ctypes.get_last_error())
        self.hpc = HPCON()
        hr = k32.CreatePseudoConsole(COORD(cols, rows), hin_r, hout_w, 0, ctypes.byref(self.hpc))
        if hr != 0:
            raise OSError(f"CreatePseudoConsole failed: 0x{hr & 0xffffffff:08x}")
        size = ctypes.c_size_t()
        k32.InitializeProcThreadAttributeList(None, 1, 0, ctypes.byref(size))
        self._attrs = ctypes.create_string_buffer(size.value)
        if not k32.InitializeProcThreadAttributeList(self._attrs, 1, 0, ctypes.byref(size)) or \
                not k32.UpdateProcThreadAttribute(self._attrs, 0, PSEUDOCONSOLE, self.hpc, ctypes.sizeof(HPCON),
                                                  None, None):
            raise ctypes.WinError(ctypes.get_last_error())
        si = STARTUPINFOEXW()
        si.StartupInfo.cb = ctypes.sizeof(STARTUPINFOEXW)
        # Null standard handles, so the child takes the pseudoconsole's rather than this process's (a pipe here).
        si.StartupInfo.dwFlags = 0x100          # STARTF_USESTDHANDLES
        si.lpAttributeList = ctypes.cast(self._attrs, ctypes.c_void_p)
        block = "".join(f"{k}={v}\0" for k, v in env.items()) + "\0"
        envbuf = ctypes.create_unicode_buffer(block, len(block))
        pi = PROCESS_INFORMATION()
        cmdline = ctypes.create_unicode_buffer(subprocess.list2cmdline([str(a) for a in argv]))
        if not k32.CreateProcessW(None, cmdline, None, None, False,
                                  EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
                                  envbuf, str(cwd), ctypes.byref(si), ctypes.byref(pi)):
            raise ctypes.WinError(ctypes.get_last_error())
        k32.CloseHandle(pi.hThread)
        k32.CloseHandle(hin_r)
        k32.CloseHandle(hout_w)
        self.hproc, self.pid, self.returncode = pi.hProcess, pi.dwProcessId, None
        self.hin_w, self.hout_r = hin_w, hout_r
        self._closed = False

    def read(self, n=65536):
        buf = ctypes.create_string_buffer(n)
        got = w.DWORD()
        if not k32.ReadFile(self.hout_r, buf, n, ctypes.byref(got), None) or got.value == 0:
            return b""
        return buf.raw[:got.value]

    def poll(self):
        if self.returncode is None and k32.WaitForSingleObject(self.hproc, 0) == 0:
            code = w.DWORD()
            k32.GetExitCodeProcess(self.hproc, ctypes.byref(code))
            self.returncode = ctypes.c_int32(code.value).value
            self._close_console()
        return self.returncode

    def wait(self, timeout=None):
        ms = 0xFFFFFFFF if timeout is None else int(timeout * 1000)
        if k32.WaitForSingleObject(self.hproc, ms) != 0:
            raise subprocess.TimeoutExpired("conpty", timeout)
        return self.poll()

    def kill(self):
        if self.poll() is None:
            k32.TerminateProcess(self.hproc, 1)

    def _close_console(self):
        # Closing the pseudoconsole ends the output pipe once its last output is flushed (the reader sees EOF).
        if not self._closed:
            self._closed = True
            threading.Thread(target=k32.ClosePseudoConsole, args=(self.hpc,), daemon=True).start()
            k32.CloseHandle(self.hin_w)


def strip_vt(data):
    """The text of one line of the console's output (the bytes between two newlines), as the console would show it.
    The console paints rather than copies: a run of spaces comes as a cursor-forward, a line written in pieces (the
    C runtime writes a console unbuffered, each `<<` on its own) can be painted again from its start with a cursor
    move, and blanks are erased with erase sequences. So the line is replayed on one row: text overwrites at the
    cursor column, CUF/CHA/CUP/CR move it, ECH/EL erase; every other sequence is dropped. Trailing blanks go."""
    row, col = bytearray(), 0

    def put(text):
        nonlocal col
        if col > len(row):
            row.extend(b" " * (col - len(row)))
        row[col:col + len(text)] = text
        col += len(text)

    for m in TOKEN_RE.finditer(data):
        params, final, cr, text = m.group(1), m.group(2), m.group(3), m.group(4)
        if text is not None:
            put(text)
        elif cr is not None:
            col = 0
        elif final is not None:
            nums = [int(p) if p.isdigit() else 0 for p in params.split(b";")] if params else []
            n = nums[0] if nums and nums[0] > 0 else 1
            if final == b"C":                      # cursor forward
                col += n
            elif final == b"D":                    # cursor back
                col = max(0, col - n)
            elif final == b"G":                    # cursor to column n
                col = n - 1
            elif final in (b"H", b"f"):            # cursor to row;column: the column only (one row is replayed)
                col = (nums[1] if len(nums) > 1 and nums[1] > 0 else 1) - 1
            elif final == b"X":                    # erase n characters from the cursor, which stays
                end = min(len(row), col + n)
                row[col:end] = b" " * max(0, end - col)
            elif final == b"K":                    # erase in line: 0 to the end, 1 to the start, 2 all
                mode = nums[0] if nums else 0
                if mode == 0:
                    del row[col:]
                elif mode == 1:
                    row[:col] = b" " * min(col, len(row))
                else:
                    row[:] = b""
    return bytes(row).rstrip(b" ")
