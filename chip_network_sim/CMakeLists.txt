cmake_minimum_required(VERSION 3.20)
project(chip_network_sim C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
find_package(Threads REQUIRED)

set(NNG_ROOT "" CACHE PATH "Path to an external nng checkout or install root")
set(LARPIX_RTL_DIR "" CACHE PATH "Path to an external LArPix RTL src directory")
set(VERILATOR_SEARCH_HINTS
  /home/lxusers/y/ymei/OpenICEDA/bin
)

if(NOT NNG_ROOT)
  message(FATAL_ERROR "NNG_ROOT must point to an external nng tree with include/ and build/ artifacts.")
endif()
if(NOT EXISTS "${NNG_ROOT}/include/nng/nng.h")
  message(FATAL_ERROR "Expected nng headers at ${NNG_ROOT}/include/nng/nng.h.")
endif()

file(GLOB NNG_LIBRARY_CANDIDATES
  "${NNG_ROOT}/build/libnng.so"
  "${NNG_ROOT}/build/libnng.so.*"
)
list(LENGTH NNG_LIBRARY_CANDIDATES NNG_LIBRARY_CANDIDATE_COUNT)
if(NNG_LIBRARY_CANDIDATE_COUNT EQUAL 0)
  message(FATAL_ERROR "Expected an nng shared library under ${NNG_ROOT}/build.")
endif()
list(GET NNG_LIBRARY_CANDIDATES 0 NNG_LIBRARY_PATH)
get_filename_component(NNG_LIBRARY_DIR "${NNG_LIBRARY_PATH}" DIRECTORY)

add_library(nng_local SHARED IMPORTED GLOBAL)
set_target_properties(nng_local PROPERTIES
  IMPORTED_LOCATION "${NNG_LIBRARY_PATH}"
  INTERFACE_INCLUDE_DIRECTORIES "${NNG_ROOT}/include"
)

# Public-facing repo path: LArPix network simulator only.
add_library(larpixsim_common
  larpix_network_sim/src/protocol.c
  larpix_network_sim/src/trace.c
)
target_include_directories(larpixsim_common PUBLIC larpix_network_sim/include)
target_link_libraries(larpixsim_common PUBLIC nng_local)
set_target_properties(larpixsim_common PROPERTIES POSITION_INDEPENDENT_CODE ON)

add_executable(trace_collector_larpix larpix_network_sim/src/trace_collector_larpix.c)
target_include_directories(trace_collector_larpix PRIVATE larpix_network_sim/include)
target_link_libraries(trace_collector_larpix PRIVATE larpixsim_common)

add_executable(fpga_larpix larpix_network_sim/src/fpga_larpix.cpp)
target_include_directories(fpga_larpix PRIVATE larpix_network_sim/include)
target_link_libraries(fpga_larpix PRIVATE larpixsim_common Threads::Threads)

add_executable(orchestrator_larpix larpix_network_sim/src/orchestrator_larpix.c)
target_include_directories(orchestrator_larpix PRIVATE larpix_network_sim/include)
target_link_libraries(orchestrator_larpix PRIVATE larpixsim_common)

set(LARPIX_RUNTIME_TARGETS fpga_larpix trace_collector_larpix orchestrator_larpix)
set_target_properties(${LARPIX_RUNTIME_TARGETS} PROPERTIES
  BUILD_RPATH "${NNG_LIBRARY_DIR}"
  INSTALL_RPATH "${NNG_LIBRARY_DIR}"
)

set(LARPIX_RTL_REQUIRED_FILES
  async2sync.sv
  channel_ctrl.sv
  comms_ctrl.sv
  config_regfile.sv
  config_regfile_assign.sv
  digital_core.sv
  digital_monitor.sv
  event_router.sv
  external_interface.sv
  fifo_latch.sv
  gate_negedge_clk.sv
  gate_posedge_clk.sv
  hydra_ctrl.sv
  larpix_constants.sv
  periodic_pulser.sv
  priority_fifo_arbiter.sv
  priority_onehot.sv
  reset_sync.sv
  sar_adc_cdc.sv
  timestamp_gen.sv
  uart.sv
  uart_rx.sv
  uart_tx.sv
)

set(LARPIX_DIGITAL_CORE_SV_BASENAMES
  async2sync.sv
  channel_ctrl.sv
  comms_ctrl.sv
  config_regfile.sv
  digital_core.sv
  digital_monitor.sv
  event_router.sv
  external_interface.sv
  fifo_latch.sv
  gate_negedge_clk.sv
  gate_posedge_clk.sv
  hydra_ctrl.sv
  periodic_pulser.sv
  priority_fifo_arbiter.sv
  reset_sync.sv
  sar_adc_cdc.sv
  timestamp_gen.sv
  uart.sv
  uart_rx.sv
  uart_tx.sv
)

if(LARPIX_RTL_DIR)
  foreach(rtl_file IN LISTS LARPIX_RTL_REQUIRED_FILES)
    if(NOT EXISTS "${LARPIX_RTL_DIR}/${rtl_file}")
      message(FATAL_ERROR "Missing required RTL file: ${LARPIX_RTL_DIR}/${rtl_file}")
    endif()
  endforeach()

  set(LARPIX_DIGITAL_CORE_SV_SOURCES)
  foreach(rtl_file IN LISTS LARPIX_DIGITAL_CORE_SV_BASENAMES)
    list(APPEND LARPIX_DIGITAL_CORE_SV_SOURCES "${LARPIX_RTL_DIR}/${rtl_file}")
  endforeach()
endif()

find_program(VERILATOR_BIN
  NAMES verilator
  HINTS ${VERILATOR_SEARCH_HINTS}
  DOC "Path to the Verilator executable"
)
if(VERILATOR_BIN AND LARPIX_RTL_DIR)
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
      -I${LARPIX_RTL_DIR}
      -CFLAGS "-I${CMAKE_SOURCE_DIR}/larpix_network_sim/include -I${NNG_ROOT}/include -std=c++17 -pthread"
      -LDFLAGS "-L${NNG_LIBRARY_DIR} -lnng -pthread -Wl,-rpath,${NNG_LIBRARY_DIR}"
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
      "${LARPIX_RTL_DIR}/config_regfile_assign.sv"
      "${LARPIX_RTL_DIR}/larpix_constants.sv"
      "${LARPIX_RTL_DIR}/priority_onehot.sv"
    VERBATIM
  )
  add_custom_target(chip_larpix_build DEPENDS "${LARPIX_CHIP_BIN}")
elseif(VERILATOR_BIN)
  message(STATUS "LARPIX_RTL_DIR not set; chip_larpix_build will not be generated.")
else()
  message(WARNING "verilator not found; chip_larpix target will not be available")
endif()
