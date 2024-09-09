include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(chess_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(chess_setup_options)
  option(chess_ENABLE_HARDENING "Enable hardening" ON)
  option(chess_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    chess_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    chess_ENABLE_HARDENING
    OFF)

  chess_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR chess_PACKAGING_MAINTAINER_MODE)
    option(chess_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(chess_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(chess_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(chess_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(chess_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(chess_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(chess_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(chess_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(chess_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(chess_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(chess_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(chess_ENABLE_PCH "Enable precompiled headers" OFF)
    option(chess_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(chess_ENABLE_IPO "Enable IPO/LTO" ON)
    option(chess_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(chess_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(chess_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(chess_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(chess_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(chess_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(chess_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(chess_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(chess_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(chess_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(chess_ENABLE_PCH "Enable precompiled headers" OFF)
    option(chess_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      chess_ENABLE_IPO
      chess_WARNINGS_AS_ERRORS
      chess_ENABLE_USER_LINKER
      chess_ENABLE_SANITIZER_ADDRESS
      chess_ENABLE_SANITIZER_LEAK
      chess_ENABLE_SANITIZER_UNDEFINED
      chess_ENABLE_SANITIZER_THREAD
      chess_ENABLE_SANITIZER_MEMORY
      chess_ENABLE_UNITY_BUILD
      chess_ENABLE_CLANG_TIDY
      chess_ENABLE_CPPCHECK
      chess_ENABLE_COVERAGE
      chess_ENABLE_PCH
      chess_ENABLE_CACHE)
  endif()

  chess_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (chess_ENABLE_SANITIZER_ADDRESS OR chess_ENABLE_SANITIZER_THREAD OR chess_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(chess_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(chess_global_options)
  if(chess_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    chess_enable_ipo()
  endif()

  chess_supports_sanitizers()

  if(chess_ENABLE_HARDENING AND chess_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR chess_ENABLE_SANITIZER_UNDEFINED
       OR chess_ENABLE_SANITIZER_ADDRESS
       OR chess_ENABLE_SANITIZER_THREAD
       OR chess_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${chess_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${chess_ENABLE_SANITIZER_UNDEFINED}")
    chess_enable_hardening(chess_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(chess_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(chess_warnings INTERFACE)
  add_library(chess_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  chess_set_project_warnings(
    chess_warnings
    ${chess_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(chess_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    chess_configure_linker(chess_options)
  endif()

  include(cmake/Sanitizers.cmake)
  chess_enable_sanitizers(
    chess_options
    ${chess_ENABLE_SANITIZER_ADDRESS}
    ${chess_ENABLE_SANITIZER_LEAK}
    ${chess_ENABLE_SANITIZER_UNDEFINED}
    ${chess_ENABLE_SANITIZER_THREAD}
    ${chess_ENABLE_SANITIZER_MEMORY})

  set_target_properties(chess_options PROPERTIES UNITY_BUILD ${chess_ENABLE_UNITY_BUILD})

  if(chess_ENABLE_PCH)
    target_precompile_headers(
      chess_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(chess_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    chess_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(chess_ENABLE_CLANG_TIDY)
    chess_enable_clang_tidy(chess_options ${chess_WARNINGS_AS_ERRORS})
  endif()

  if(chess_ENABLE_CPPCHECK)
    chess_enable_cppcheck(${chess_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(chess_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    chess_enable_coverage(chess_options)
  endif()

  if(chess_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(chess_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(chess_ENABLE_HARDENING AND NOT chess_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR chess_ENABLE_SANITIZER_UNDEFINED
       OR chess_ENABLE_SANITIZER_ADDRESS
       OR chess_ENABLE_SANITIZER_THREAD
       OR chess_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    chess_enable_hardening(chess_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
