#!/usr/bin/env python3
"""Does Mesa (freedreno) import a dma-buf as an EGLImage here? (7 Kasım, libcamera GPU ISP)

Allocates a buffer from a dma-heap (or udmabuf), then calls eglCreateImageKHR exactly as
libcamera's egl.cpp does (surfaceless display, linear modifier) and prints eglGetError().
Usage: doas python3 egl-dmabuf-dene.py [heap-adi]   (default: system)
"""
import ctypes as C
import fcntl
import os
import struct
import sys

egl = C.CDLL("libEGL.so.1")
egl.eglGetPlatformDisplay.restype = C.c_void_p
egl.eglGetPlatformDisplay.argtypes = [C.c_uint, C.c_void_p, C.c_void_p]
egl.eglInitialize.argtypes = [C.c_void_p, C.c_void_p, C.c_void_p]
egl.eglGetProcAddress.restype = C.c_void_p
egl.eglGetProcAddress.argtypes = [C.c_char_p]
egl.eglQueryString.restype = C.c_char_p
egl.eglQueryString.argtypes = [C.c_void_p, C.c_int]
egl.eglGetError.restype = C.c_int

EGL_PLATFORM_SURFACELESS_MESA = 0x31DD
EGL_LINUX_DMA_BUF_EXT = 0x3270
A = dict(W=0x3057, H=0x3056, FOURCC=0x3271, FD=0x3272, OFF=0x3273, PITCH=0x3274,
         MODLO=0x3443, MODHI=0x3444, NONE=0x3038)
R8, ARGB = 0x20203852, 0x34325241
HATA = {0x3000: "SUCCESS", 0x3003: "BAD_ALLOC", 0x3004: "BAD_ATTRIBUTE", 0x3008: "BAD_DISPLAY",
        0x300C: "BAD_PARAMETER", 0x3009: "BAD_MATCH", 0x3006: "BAD_CONTEXT"}

d = egl.eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, None, None)
maj, mnr = C.c_int(), C.c_int()
print("init", egl.eglInitialize(d, C.byref(maj), C.byref(mnr)), maj.value, mnr.value)
print("vendor", egl.eglQueryString(d, 0x3053))
create = C.CFUNCTYPE(C.c_void_p, C.c_void_p, C.c_void_p, C.c_uint, C.c_void_p,
                     C.POINTER(C.c_int))(egl.eglGetProcAddress(b"eglCreateImageKHR"))


def ayir(boyut, heap):
    if heap == "udmabuf":
        mfd = os.memfd_create("t", os.MFD_ALLOW_SEALING)
        os.ftruncate(mfd, boyut)
        fcntl.fcntl(mfd, 1033, 8)  # F_ADD_SEALS, F_SEAL_SHRINK
        u = os.open("/dev/udmabuf", os.O_RDWR)
        req = struct.pack("IIQQ", mfd, 1, 0, boyut)  # flags UDMABUF_FLAGS_CLOEXEC
        return fcntl.ioctl(u, 0x40187542, req) if False else fcntl.ioctl(u, (1 << 30) | (24 << 16) | (ord("u") << 8) | 0x42, bytearray(req), False)
    h = os.open(f"/dev/dma_heap/{heap}", os.O_RDWR)
    b = bytearray(struct.pack("QIIQ", boyut, 0, 0o2000002, 0))  # len, fd, fd_flags O_RDWR|O_CLOEXEC, heap_flags
    fcntl.ioctl(h, (3 << 30) | (24 << 16) | (ord("H") << 8) | 0, b)
    return struct.unpack_from("QI", b, 0)[1]


heap = sys.argv[1] if len(sys.argv) > 1 else "system"


def boya_oku(heap):
    """Clear an imported ARGB dma-buf to a colour on the GPU, then read it back on the CPU."""
    import mmap
    gl = C.CDLL("libGLESv2.so.2")
    egl.eglBindAPI(0x30A0)  # EGL_OPENGL_ES_API
    egl.eglCreateContext.restype = C.c_void_p
    egl.eglCreateContext.argtypes = [C.c_void_p, C.c_void_p, C.c_void_p, C.POINTER(C.c_int)]
    egl.eglMakeCurrent.argtypes = [C.c_void_p, C.c_void_p, C.c_void_p, C.c_void_p]
    ctx = egl.eglCreateContext(d, None, None, (C.c_int * 3)(0x3098, 2, 0x3038))
    print("bağlam", bool(ctx), egl.eglMakeCurrent(d, None, None, ctx))
    w, h = 256, 64
    fd = ayir(w * 4 * h, heap)
    at = [A["W"], w, A["H"], h, A["FOURCC"], ARGB, A["FD"], fd, A["OFF"], 0, A["PITCH"], w * 4,
          A["MODLO"], 0, A["MODHI"], 0, A["NONE"]]
    img = create(d, None, EGL_LINUX_DMA_BUF_EXT, None, (C.c_int * len(at))(*at))
    tex, fbo = C.c_uint(), C.c_uint()
    gl.glGenTextures(1, C.byref(tex))
    gl.glBindTexture(0x0DE1, tex)
    target = C.CFUNCTYPE(None, C.c_uint, C.c_void_p)(egl.eglGetProcAddress(b"glEGLImageTargetTexture2DOES"))
    target(0x0DE1, img)
    gl.glGenFramebuffers(1, C.byref(fbo))
    gl.glBindFramebuffer(0x8D40, fbo)
    gl.glFramebufferTexture2D(0x8D40, 0x8CE0, 0x0DE1, tex, 0)
    print("fbo durumu", hex(gl.glCheckFramebufferStatus(0x8D40)), "gl hata", hex(gl.glGetError()))
    gl.glClearColor.argtypes = [C.c_float] * 4
    gl.glClearColor(1.0, 0.5, 0.25, 1.0)
    gl.glClear(0x4000)
    gl.glFinish()
    m = mmap.mmap(fd, w * 4 * h)
    sync = (1 << 30) | (8 << 16) | (ord("b") << 8) | 0
    fcntl.ioctl(fd, sync, struct.pack("Q", 1 | 4))  # START | READ
    print("CPU okuması (BGRA):", list(m[:8]), "sıfır olmayan bayt:", sum(1 for x in m[:4096] if x))
    fcntl.ioctl(fd, sync, struct.pack("Q", 2 | 4))  # END | READ
    print("gl hata", hex(gl.glGetError()))


if len(sys.argv) > 2 and sys.argv[2] == "boya":
    boya_oku(heap)
    sys.exit(0)
for ad, w, h, fourcc, pitch in (("giriş R8", 1632, 972, R8, 1632), ("çıkış ARGB", 1152, 864, ARGB, 1152 * 4)):
    fd = ayir(pitch * h, heap)
    for mod in (True, False):
        at = [A["W"], w, A["H"], h, A["FOURCC"], fourcc, A["FD"], fd, A["OFF"], 0, A["PITCH"], pitch]
        if mod:
            at += [A["MODLO"], 0, A["MODHI"], 0]
        at += [A["NONE"]]
        arr = (C.c_int * len(at))(*at)
        img = create(d, None, EGL_LINUX_DMA_BUF_EXT, None, arr)
        e = egl.eglGetError()
        print(f"{heap} {ad} {w}x{h} pitch {pitch} modifier={'0' if mod else 'yok'}: "
              f"{'OK' if img else 'BAŞARISIZ'} ({HATA.get(e, hex(e))})")
