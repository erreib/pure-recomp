# Zstandard's decoder, for the ZIM images of HD texture packs (D-024, task 099): the framework's pack loader
# (host/gpu/texture_pack.cpp, patch 0033-zim-textures) inflates their zstd payloads with ZSTD_decompress. The pinned
# release below is downloaded once into the build directory, its SHA-256 checked, and only the decoder's C sources
# (lib/common/*.c, lib/decompress/*.c) are compiled, into the static library pure_zstd_decoder: no programs, no shared
# library, no compressor, no legacy formats, and ZSTD_DISABLE_ASM=1 so the x86-64 Huffman decoder in assembly
# (huf_decompress_amd64.S) is not needed and no assembler runs on any preset. No system zstd is used: the rig has none
# and the bundles carry nothing of the machine. zstd is BSD-3-Clause (or GPLv2, its COPYING); the notice is in
# packaging/THIRD_PARTY_NOTICES.md. The download follows the framework's cmake/FFmpeg.cmake.
set(PURE_ZSTD_VERSION 1.5.7)
set(PURE_ZSTD_URL "https://github.com/facebook/zstd/releases/download/v${PURE_ZSTD_VERSION}/zstd-${PURE_ZSTD_VERSION}.tar.gz")
set(PURE_ZSTD_SHA256 eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3)

set(_pure_zstd_downloads "${CMAKE_BINARY_DIR}/_deps/downloads")
set(_pure_zstd_root "${CMAKE_BINARY_DIR}/_deps/zstd")
set(_pure_zstd_src "${_pure_zstd_root}/zstd-${PURE_ZSTD_VERSION}")
set(_pure_zstd_stamp_file "${_pure_zstd_root}/pure.stamp")
set(_pure_zstd_stamp "${PURE_ZSTD_VERSION} ${PURE_ZSTD_SHA256}\n")

# Extracted once per build directory, again only when the pin changes; downloaded only when _deps/downloads holds no
# copy with the pinned SHA-256 (put it there by hand on a machine without the network).
set(_pure_zstd_extracted "")
if(EXISTS "${_pure_zstd_stamp_file}")
    file(READ "${_pure_zstd_stamp_file}" _pure_zstd_extracted)
endif()
if(NOT _pure_zstd_extracted STREQUAL _pure_zstd_stamp)
    set(_pure_zstd_archive "${_pure_zstd_downloads}/zstd-${PURE_ZSTD_VERSION}.tar.gz")
    set(_pure_zstd_have "")
    if(EXISTS "${_pure_zstd_archive}")
        file(SHA256 "${_pure_zstd_archive}" _pure_zstd_have)
    endif()
    if(NOT _pure_zstd_have STREQUAL PURE_ZSTD_SHA256)
        message(STATUS "pure: downloading ${PURE_ZSTD_URL}")
        file(DOWNLOAD "${PURE_ZSTD_URL}" "${_pure_zstd_archive}.part" STATUS _pure_zstd_status TLS_VERIFY ON)
        list(GET _pure_zstd_status 0 _pure_zstd_code)
        if(NOT _pure_zstd_code EQUAL 0)
            file(REMOVE "${_pure_zstd_archive}.part")
            message(FATAL_ERROR "pure: could not download ${PURE_ZSTD_URL}: ${_pure_zstd_status}\n"
                "Put zstd-${PURE_ZSTD_VERSION}.tar.gz in ${_pure_zstd_downloads} by hand.")
        endif()
        file(SHA256 "${_pure_zstd_archive}.part" _pure_zstd_have)
        if(NOT _pure_zstd_have STREQUAL PURE_ZSTD_SHA256)
            file(REMOVE "${_pure_zstd_archive}.part")
            message(FATAL_ERROR "pure: ${PURE_ZSTD_URL} has SHA-256 ${_pure_zstd_have}, expected ${PURE_ZSTD_SHA256}")
        endif()
        file(RENAME "${_pure_zstd_archive}.part" "${_pure_zstd_archive}")
    endif()
    file(REMOVE_RECURSE "${_pure_zstd_src}")
    file(ARCHIVE_EXTRACT INPUT "${_pure_zstd_archive}" DESTINATION "${_pure_zstd_root}"
        PATTERNS "zstd-${PURE_ZSTD_VERSION}/LICENSE" "zstd-${PURE_ZSTD_VERSION}/COPYING"
                 "zstd-${PURE_ZSTD_VERSION}/lib/*")
    file(WRITE "${_pure_zstd_stamp_file}" "${_pure_zstd_stamp}")
endif()

file(GLOB _pure_zstd_sources "${_pure_zstd_src}/lib/common/*.c" "${_pure_zstd_src}/lib/decompress/*.c")
if(NOT _pure_zstd_sources)
    message(FATAL_ERROR "pure: no zstd decoder sources in ${_pure_zstd_src}/lib; remove ${_pure_zstd_stamp_file} "
        "and configure again")
endif()
add_library(pure_zstd_decoder STATIC ${_pure_zstd_sources})
# zstd.h for the loader; lib/common for the sources' own includes.
target_include_directories(pure_zstd_decoder SYSTEM PUBLIC "${_pure_zstd_src}/lib")
target_include_directories(pure_zstd_decoder PRIVATE "${_pure_zstd_src}/lib/common")
# ZSTD_DISABLE_ASM: the C Huffman decoder on every target. XXH_NAMESPACE (zstd's own build sets it too) keeps its
# xxHash symbols apart from any other copy.
target_compile_definitions(pure_zstd_decoder PRIVATE ZSTD_DISABLE_ASM=1 XXH_NAMESPACE=ZSTD_)
# Its warnings are upstream's.
if(MSVC)
    target_compile_options(pure_zstd_decoder PRIVATE /w)
else()
    target_compile_options(pure_zstd_decoder PRIVATE -w)
endif()
