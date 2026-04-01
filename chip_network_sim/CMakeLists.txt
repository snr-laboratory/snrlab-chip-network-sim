cmake_minimum_required(VERSION 3.20)
project(chip_network_sim C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
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

# Legacy simulator targets are only built if their original sources are present.
if(EXISTS "${CMAKE_SOURCE_DIR}/src/protocol.c" AND EXISTS "${CMAKE_SOURCE_DIR}/src/trace.c")
  set(CHIPSIM_COMMON_SOURCES
    src/protocol.c
    src/trace.c
  )
  if(EXISTS "${CMAKE_SOURCE_DIR}/src/fifo.c")
    list(APPEND CHIPSIM_COMMON_SOURCES src/fifo.c)
  endif()

  add_library(chipsim_common ${CHIPSIM_COMMON_SOURCES})
  target_include_directories(chipsim_common PUBLIC include)
  target_link_libraries(chipsim_common PUBLIC nng_local)
  set_target_properties(chipsim_common PROPERTIES POSITION_INDEPENDENT_CODE ON)

  if(EXISTS "${CMAKE_SOURCE_DIR}/src/chip.c")
    add_executable(chip src/chip.c)
    target_link_libraries(chip PRIVATE chipsim_common Threads::Threads)
  endif()

  if(EXISTS "${CMAKE_SOURCE_DIR}/src/orchestrator.c")
    add_executable(orchestrator src/orchestrator.c)
    target_link_libraries(orchestrator PRIVATE chipsim_common)
  endif()

  if(EXISTS "${CMAKE_SOURCE_DIR}/src/fifo.c")
    enable_testing()
    add_executable(test_fifo tests/test_fifo.c)
    target_link_libraries(test_fifo PRIVATE chipsim_common)
    add_test(NAME fifo COMMAND test_fifo)
  endif()
endif()

# LArPix-specific runtime path: should only depend on larpix_network_sim + larpix_v3b RTL.
add_library(larpixsim_common
  larpix_network_sim/src/protocol.c
  larpix_network_sim/src/trace.c
)
target_include_directories(larpixsim_common PUBLIC larpix_network_sim/include)
target_link_libraries(larpixsim_common PUBLIC nng_local)
set_target_properties(larpixsim_common PROPERTIES POSITION_INDEPENDENT_CODE ON)

add_executable(fpga_larpix larpix_network_sim/src/fpga_larpix.cpp)
target_include_directories(fpga_larpix PRIVATE larpix_network_sim/include)
target_link_libraries(fpga_larpix PRIVATE larpixsim_common Threads::Threads)

add_executable(orchestrator_larpix larpix_network_sim/src/orchestrator_larpix.c)
target_include_directories(orchestrator_larpix PRIVATE larpix_network_sim/include)
target_link_libraries(orchestrator_larpix PRIVATE larpixsim_common)

set(LARPIX_RUNTIME_TARGETS fpga_larpix orchestrator_larpix)
if(TARGET chip)
  list(APPEND LARPIX_RUNTIME_TARGETS chip)
endif()
if(TARGET orchestrator)
  list(APPEND LARPIX_RUNTIME_TARGETS orchestrator)
endif()
set_target_properties(${LARPIX_RUNTIME_TARGETS} PROPERTIES
  BUILD_RPATH "${CMAKE_SOURCE_DIR}/nng/build"
  INSTALL_RPATH "${CMAKE_SOURCE_DIR}/nng/build"
)

set(LARPIX_DIGITAL_CORE_SV_SOURCES
  ${CMAKE_SOURCE_DIR}/larpix_network_sim/larpix_v3b_rtl/src/async2sync.sv
  ${CMAKE_SOURCE_DIR}/larpix_network_sim/larpix_v3b_rtl/src/channel_ctrl.sv
  ${CMAKE_SOURCE_DIR}/larpix_network_sim/larpix_v3b_rtl/src/comms_ctrl.sv
  ${CMAKE_SOURCE_DIR}/larpix_network_sim/larpix_v3b_rtl/src/config_regfile.sv
  ${CMAKE_SOURCE_DIR}/larpix_network_sim/larpix_v3b_rtl/src/digital_core.sv
  ${CMAKE_SOURCE_DIR}/larpix_network_sim/larpix_v3b_rtl/src/digital_monitor.sv
  ${CMAKE_SOURCE_DIR}/larpix_network_sim/larpix_v3b_rtl/src/event_router.sv
  ${CMAKE_SOURCE_DIR}/larpix_network_sim/larpix_v3b_rtl/src/external_interface.sv
  ${CMAKE_SOURCE_DIR}/larpix_network_sim/larpix_v3b_rtl/src/fifo_latch.sv
  ${CMAKE_SOURCE_DIR}/larpix_network_sim/larpix_v3b_rtl/src/gate_negedge_clk.sv
  ${CMAKE_SOURCE_DIR}/larpix_network_sim/larpix_v3b_rtl/src/gate_posedge_clk.sv
  ${CMAKE_SOURCE_DIR}/larpix_network_sim/larpix_v3b_rtl/src/hydra_ctrl.sv
  ${CMAKE_SOURCE_DIR}/larpix_network_sim/larpix_v3b_rtl/src/periodic_pulser.sv
  ${CMAKE_SOURCE_DIR}/larpix_network_sim/larpix_v3b_rtl/src/priority_fifo_arbiter.sv
  ${CMAKE_SOURCE_DIR}/larpix_network_sim/larpix_v3b_rtl/src/reset_sync.sv
  ${CMAKE_SOURCE_DIR}/larpix_network_sim/larpix_v3b_rtl/src/sar_adc_cdc.sv
  ${CMAKE_SOURCE_DIR}/larpix_network_sim/larpix_v3b_rtl/src/timestamp_gen.sv
  ${CMAKE_SOURCE_DIR}/larpix_network_sim/larpix_v3b_rtl/src/uart.sv
  ${CMAKE_SOURCE_DIR}/larpix_network_sim/larpix_v3b_rtl/src/uart_rx.sv
  ${CMAKE_SOURCE_DIR}/larpix_network_sim/larpix_v3b_rtl/src/uart_tx.sv
)

find_program(VERILATOR_BIN verilator)
if(VERILATOR_BIN)
  if(EXISTS "${CMAKE_SOURCE_DIR}/rtl/chip_fifo_router.sv" AND EXISTS "${CMAKE_SOURCE_DIR}/src/chip_rtl.cpp" AND EXISTS "${CMAKE_SOURCE_DIR}/src/trace.c")
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
        "${CMAKE_SOURCE_DIR}/src/trace.c"
        -o chip_rtl
      COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CHIPSIM_RTL_MDIR}/chip_rtl"
        "${CHIPSIM_RTL_BIN}"
      DEPENDS
        "${CMAKE_SOURCE_DIR}/rtl/chip_fifo_router.sv"
        "${CMAKE_SOURCE_DIR}/src/chip_rtl.cpp"
        "${CMAKE_SOURCE_DIR}/include/chipsim/protocol.h"
        "${CMAKE_SOURCE_DIR}/include/chipsim/trace.h"
        "${CMAKE_SOURCE_DIR}/src/trace.c"
      VERBATIM
    )
    add_custom_target(chip_rtl_build ALL DEPENDS "${CHIPSIM_RTL_BIN}")
  endif()

  set(LARPIX_CHIP_MDIR "${CMAKE_BINARY_DIR}/verilated_larpix_chip")
  set(LARPIX_CHIP_BIN "${CMAKE_BINARY_DIR}/chip_larpix")
  add_custom_command(
    OUTPUT "${LARPIX_CHIP_BIN}"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${LARPIX_CHIP_MDIR}"
    COMMAND ${VERILATOR_BIN}
      --cc
      --exe
      --build
      --build-jobs 0
      --Wno-fatal
      --sv
      --top-module digital_core
      --prefix Vdigital_core
      --Mdir "${LARPIX_CHIP_MDIR}"
      -I${CMAKE_SOURCE_DIR}/larpix_network_sim/larpix_v3b_rtl/src
      -CFLAGS "-I${CMAKE_SOURCE_DIR}/larpix_network_sim/include -I${CMAKE_SOURCE_DIR}/nng/include -std=c++17 -pthread"
      -LDFLAGS "-L${CMAKE_SOURCE_DIR}/nng/build -lnng -pthread -Wl,-rpath,${CMAKE_SOURCE_DIR}/nng/build"
      ${LARPIX_DIGITAL_CORE_SV_SOURCES}
      "${CMAKE_SOURCE_DIR}/larpix_network_sim/src/analog_core_model.cpp"
      "${CMAKE_SOURCE_DIR}/larpix_network_sim/src/larpix_cosim_backend.cpp"
      "${CMAKE_SOURCE_DIR}/larpix_network_sim/src/chip_larpix.cpp"
      "${CMAKE_SOURCE_DIR}/larpix_network_sim/src/trace.c"
      -o chip_larpix
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      "${LARPIX_CHIP_MDIR}/chip_larpix"
      "${LARPIX_CHIP_BIN}"
    DEPENDS
      ${LARPIX_DIGITAL_CORE_SV_SOURCES}
      "${CMAKE_SOURCE_DIR}/larpix_network_sim/src/analog_core_model.cpp"
      "${CMAKE_SOURCE_DIR}/larpix_network_sim/src/analog_core_model.h"
      "${CMAKE_SOURCE_DIR}/larpix_network_sim/src/larpix_cosim_backend.cpp"
      "${CMAKE_SOURCE_DIR}/larpix_network_sim/src/chip_larpix.cpp"
      "${CMAKE_SOURCE_DIR}/larpix_network_sim/src/trace.c"
      "${CMAKE_SOURCE_DIR}/larpix_network_sim/include/larpixsim/backend.h"
      "${CMAKE_SOURCE_DIR}/larpix_network_sim/include/chipsim/protocol.h"
      "${CMAKE_SOURCE_DIR}/larpix_network_sim/include/chipsim/trace.h"
    VERBATIM
  )
  add_custom_target(chip_larpix_build DEPENDS "${LARPIX_CHIP_BIN}")
else()
  message(WARNING "verilator not found; chip_rtl/chip_larpix targets will not be available")
endif()
