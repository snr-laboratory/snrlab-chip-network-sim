cmake_minimum_required(VERSION 3.20)
project(chip_network_sim C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
find_package(Threads REQUIRED)

# External messaging dependency used by the active simulator runtime.
# Users normally do not edit this unless their local NNG install location changes.
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

# Core active-simulator runtime library and executables.
# This section builds the shared runtime pieces used by all supported LArPix-like RTL targets.
# Users usually do not edit this unless they are changing the simulator runtime itself.
add_library(larpixsim_common
  sim_core/src/protocol.c
  sim_core/src/trace.c
)
target_include_directories(larpixsim_common PUBLIC sim_core/include)
target_link_libraries(larpixsim_common PUBLIC nng_local)
set_target_properties(larpixsim_common PROPERTIES POSITION_INDEPENDENT_CODE ON)

add_executable(trace_collector_larpix sim_core/src/trace_collector_larpix.c)
target_include_directories(trace_collector_larpix PRIVATE sim_core/include)
target_link_libraries(trace_collector_larpix PRIVATE larpixsim_common)

add_executable(fpga_larpix sim_core/src/fpga_larpix.cpp)
target_include_directories(fpga_larpix PRIVATE sim_core/include)
target_link_libraries(fpga_larpix PRIVATE larpixsim_common Threads::Threads)

add_executable(orchestrator_larpix sim_core/src/orchestrator_larpix.c)
target_include_directories(orchestrator_larpix PRIVATE sim_core/include)
target_link_libraries(orchestrator_larpix PRIVATE larpixsim_common)

set(LARPIX_RUNTIME_TARGETS fpga_larpix trace_collector_larpix orchestrator_larpix)
set_target_properties(${LARPIX_RUNTIME_TARGETS} PROPERTIES
  BUILD_RPATH "${CMAKE_SOURCE_DIR}/nng/build"
  INSTALL_RPATH "${CMAKE_SOURCE_DIR}/nng/build"
)

# RTL source roots for the currently supported LArPix-like designs.
# USER-EDIT SECTION:
# If you add a new RTL tree, add a new path variable here.
set(LARPIX_RTL_V1_DIR ${CMAKE_SOURCE_DIR}/rtl/v3b/src)
set(LARPIX_RTL_V2_DIR ${CMAKE_SOURCE_DIR}/rtl/v3b_v2/src)
set(LARPIX_RTL_V3C_DIR ${CMAKE_SOURCE_DIR}/rtl/v3c/src)
set(LARPIX_RTL_V3C2_DIR ${CMAKE_SOURCE_DIR}/rtl/v3c2/src)
set(LARPIX_RTL_MSG_DIR ${CMAKE_SOURCE_DIR}/rtl/msg_rtl/src)

# Helper that enumerates the expected SystemVerilog sources for a LArPix-like digital_core RTL.
# Users only need to edit this if a new RTL variant has a different file list or naming scheme.
function(set_larpix_digital_core_sv_sources out_var rtl_dir)
  set(_sources
    ${rtl_dir}/async2sync.sv
    ${rtl_dir}/channel_ctrl.sv
    ${rtl_dir}/comms_ctrl.sv
    ${rtl_dir}/config_regfile.sv
    ${rtl_dir}/digital_core.sv
    ${rtl_dir}/digital_monitor.sv
    ${rtl_dir}/event_router.sv
    ${rtl_dir}/external_interface.sv
    ${rtl_dir}/fifo_latch.sv
    ${rtl_dir}/gate_negedge_clk.sv
    ${rtl_dir}/gate_posedge_clk.sv
    ${rtl_dir}/hydra_ctrl.sv
    ${rtl_dir}/periodic_pulser.sv
    ${rtl_dir}/priority_fifo_arbiter.sv
    ${rtl_dir}/reset_sync.sv
    ${rtl_dir}/sar_adc_cdc.sv
    ${rtl_dir}/timestamp_gen.sv
    ${rtl_dir}/uart.sv
    ${rtl_dir}/uart_rx.sv
    ${rtl_dir}/uart_tx.sv
  )
  if(EXISTS "${rtl_dir}/msg_logic.sv")
    list(APPEND _sources ${rtl_dir}/msg_logic.sv)
  endif()
  if(EXISTS "${rtl_dir}/msg_generator.sv")
    list(APPEND _sources ${rtl_dir}/msg_generator.sv)
  endif()
  set(${out_var} ${_sources} PARENT_SCOPE)
endfunction()

set_larpix_digital_core_sv_sources(LARPIX_DIGITAL_CORE_SV_SOURCES ${LARPIX_RTL_V1_DIR})
set_larpix_digital_core_sv_sources(LARPIX_DIGITAL_CORE_SV_SOURCES_V2 ${LARPIX_RTL_V2_DIR})
set_larpix_digital_core_sv_sources(LARPIX_DIGITAL_CORE_SV_SOURCES_V3C ${LARPIX_RTL_V3C_DIR})
set_larpix_digital_core_sv_sources(LARPIX_DIGITAL_CORE_SV_SOURCES_V3C2 ${LARPIX_RTL_V3C2_DIR})
set_larpix_digital_core_sv_sources(LARPIX_DIGITAL_CORE_SV_SOURCES_MSG ${LARPIX_RTL_MSG_DIR})

# Verilator discovery.
# USER-EDIT SECTION:
# Update VERILATOR_SEARCH_HINTS if Verilator lives somewhere else on the user's machine.
set(VERILATOR_SEARCH_HINTS
  /home/lxusers/y/ymei/OpenICEDA/bin
)
find_program(VERILATOR_BIN
  NAMES verilator
  HINTS ${VERILATOR_SEARCH_HINTS}
  DOC "Path to the Verilator executable"
)
if(VERILATOR_BIN)
  # Helper that builds one RTL-backed chip executable by combining:
  # - the chosen RTL source tree
  # - the shared analog model
  # - the shared cosim backend
  # - the shared chip runtime
  #
  # USER-EDIT SECTION:
  # If a new LArPix-like RTL still uses top-module digital_core and the same runtime contract,
  # users typically only need to add one more add_larpix_chip_target(...) call below.
  # If the RTL needs a different top module, different include files, or a different runtime contract,
  # this function is one of the places that would need editing.
  function(add_larpix_chip_target target_name output_name mdir_var bin_var rtl_include_dir sv_sources)
    set(${mdir_var} "${CMAKE_BINARY_DIR}/verilated_${output_name}" PARENT_SCOPE)
    set(${bin_var} "${CMAKE_BINARY_DIR}/${output_name}" PARENT_SCOPE)
    set(_mdir "${CMAKE_BINARY_DIR}/verilated_${output_name}")
    set(_bin "${CMAKE_BINARY_DIR}/${output_name}")
    add_custom_command(
      OUTPUT "${_bin}"
      COMMAND ${CMAKE_COMMAND} -E make_directory "${_mdir}"
      COMMAND ${VERILATOR_BIN}
        --cc
        --exe
        --build
        --build-jobs 0
        --Wno-fatal
        --sv
        --top-module digital_core
        --prefix Vdigital_core
        --Mdir "${_mdir}"
        -I${rtl_include_dir}
        -CFLAGS "-I${CMAKE_SOURCE_DIR}/sim_core/include -I${CMAKE_SOURCE_DIR}/nng/include -std=c++17 -pthread"
        -LDFLAGS "-L${CMAKE_SOURCE_DIR}/nng/build -lnng -pthread -Wl,-rpath,${CMAKE_SOURCE_DIR}/nng/build"
        ${sv_sources}
        "${CMAKE_SOURCE_DIR}/sim_core/src/analog_core_model.cpp"
        "${CMAKE_SOURCE_DIR}/sim_core/src/larpix_cosim_backend.cpp"
        "${CMAKE_SOURCE_DIR}/sim_core/src/chip_larpix.cpp"
        "${CMAKE_SOURCE_DIR}/sim_core/src/trace.c"
        -o ${output_name}
      COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${_mdir}/${output_name}"
        "${_bin}"
      DEPENDS
        ${sv_sources}
        "${rtl_include_dir}/config_regfile_assign.sv"
        "${rtl_include_dir}/larpix_constants.sv"
        "${rtl_include_dir}/priority_onehot.sv"
        "${CMAKE_SOURCE_DIR}/sim_core/src/analog_core_model.cpp"
        "${CMAKE_SOURCE_DIR}/sim_core/src/analog_core_model.h"
        "${CMAKE_SOURCE_DIR}/sim_core/src/larpix_cosim_backend.cpp"
        "${CMAKE_SOURCE_DIR}/sim_core/src/chip_larpix.cpp"
        "${CMAKE_SOURCE_DIR}/sim_core/src/trace.c"
        "${CMAKE_SOURCE_DIR}/sim_core/include/larpixsim/backend.h"
        "${CMAKE_SOURCE_DIR}/sim_core/include/chipsim/protocol.h"
        "${CMAKE_SOURCE_DIR}/sim_core/include/chipsim/trace.h"
      VERBATIM
    )
    add_custom_target(${target_name} DEPENDS "${_bin}")
  endfunction()

  # Concrete RTL-backed chip targets available in this branch.
  # USER-EDIT SECTION:
  # Add or remove target lines here when enabling or retiring specific RTL variants.
  add_larpix_chip_target(chip_larpix_v3b_build chip_larpix_v3b LARPIX_CHIP_MDIR LARPIX_CHIP_BIN "${LARPIX_RTL_V1_DIR}" "${LARPIX_DIGITAL_CORE_SV_SOURCES}")
  add_larpix_chip_target(chip_larpix_v3b_v2_build chip_larpix_v3b_v2 LARPIX_CHIP_V2_MDIR LARPIX_CHIP_V2_BIN "${LARPIX_RTL_V2_DIR}" "${LARPIX_DIGITAL_CORE_SV_SOURCES_V2}")
  add_larpix_chip_target(chip_larpix_v3c_build chip_larpix_v3c LARPIX_CHIP_V3C_MDIR LARPIX_CHIP_V3C_BIN "${LARPIX_RTL_V3C_DIR}" "${LARPIX_DIGITAL_CORE_SV_SOURCES_V3C}")
  add_larpix_chip_target(chip_larpix_v3c2_build chip_larpix_v3c2 LARPIX_CHIP_V3C2_MDIR LARPIX_CHIP_V3C2_BIN "${LARPIX_RTL_V3C2_DIR}" "${LARPIX_DIGITAL_CORE_SV_SOURCES_V3C2}")
  add_larpix_chip_target(chip_larpix_msg_rtl_build chip_larpix_msg_rtl LARPIX_CHIP_MSG_MDIR LARPIX_CHIP_MSG_BIN "${LARPIX_RTL_MSG_DIR}" "${LARPIX_DIGITAL_CORE_SV_SOURCES_MSG}")
else()
  # Build remains usable for non-Verilated pieces even if Verilator is absent.
  message(WARNING "verilator not found; RTL-backed chip_larpix_<variant> targets will not be available")
endif()
