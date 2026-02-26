cmake_minimum_required(VERSION 3.20)
project(chip_network_sim C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
find_package(Threads REQUIRED)

if(NOT EXISTS "${CMAKE_SOURCE_DIR}/nng/include/nng/nng.h")
  message(FATAL_ERROR "Expected nng headers at nng/include/nng/nng.h.")
endif()
if(NOT EXISTS "${CMAKE_SOURCE_DIR}/nng/build/libnng.so")
  message(FATAL_ERROR "Expected nng shared library at nng/build/libnng.so.")
endif()

add_library(nng_local SHARED IMPORTED GLOBAL)
set_target_properties(nng_local PROPERTIES
  IMPORTED_LOCATION "${CMAKE_SOURCE_DIR}/nng/build/libnng.so"
  INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_SOURCE_DIR}/nng/include"
)

add_library(chipsim_common
  src/fifo.c
  src/protocol.c
)
target_include_directories(chipsim_common PUBLIC include)
target_link_libraries(chipsim_common PUBLIC nng_local)
set_target_properties(chipsim_common PROPERTIES
  POSITION_INDEPENDENT_CODE ON
)

add_executable(chip src/chip.c)
target_link_libraries(chip PRIVATE chipsim_common Threads::Threads)

add_executable(orchestrator src/orchestrator.c)
target_link_libraries(orchestrator PRIVATE chipsim_common)

# Let runtime find local nng shared library without env setup.
set_target_properties(chip orchestrator PROPERTIES
  BUILD_RPATH "${CMAKE_SOURCE_DIR}/nng/build"
  INSTALL_RPATH "${CMAKE_SOURCE_DIR}/nng/build"
)

enable_testing()

add_executable(test_fifo tests/test_fifo.c)
target_link_libraries(test_fifo PRIVATE chipsim_common)
add_test(NAME fifo COMMAND test_fifo)

find_program(VERILATOR_BIN verilator)
if(VERILATOR_BIN)
  set(CHIPSIM_RTL_MDIR "${CMAKE_BINARY_DIR}/verilated_chip")
  set(CHIPSIM_RTL_BIN "${CMAKE_BINARY_DIR}/chip_rtl")
  add_custom_command(
    OUTPUT "${CHIPSIM_RTL_BIN}"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${CHIPSIM_RTL_MDIR}"
    COMMAND ${VERILATOR_BIN}
      --cc
      --exe
      --build
      --build-jobs 0
      --Wno-fatal
      --top-module chip_fifo_router
      --prefix Vchip_fifo_router
      --Mdir "${CHIPSIM_RTL_MDIR}"
      -CFLAGS "-I${CMAKE_SOURCE_DIR}/include -I${CMAKE_SOURCE_DIR}/nng/include -std=c++17 -pthread"
      -LDFLAGS "-L${CMAKE_SOURCE_DIR}/nng/build -lnng -pthread -Wl,-rpath,${CMAKE_SOURCE_DIR}/nng/build"
      "${CMAKE_SOURCE_DIR}/rtl/chip_fifo_router.sv"
      "${CMAKE_SOURCE_DIR}/src/chip_rtl.cpp"
      -o chip_rtl
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      "${CHIPSIM_RTL_MDIR}/chip_rtl"
      "${CHIPSIM_RTL_BIN}"
    DEPENDS
      "${CMAKE_SOURCE_DIR}/rtl/chip_fifo_router.sv"
      "${CMAKE_SOURCE_DIR}/src/chip_rtl.cpp"
      "${CMAKE_SOURCE_DIR}/include/chipsim/protocol.h"
    VERBATIM
  )
  add_custom_target(chip_rtl_build ALL DEPENDS "${CHIPSIM_RTL_BIN}")
else()
  message(WARNING "verilator not found; chip_rtl target will not be available")
endif()
