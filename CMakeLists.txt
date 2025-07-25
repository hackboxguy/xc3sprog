# Project
project(xc3sprog)
set(xc3sprog_VERSION_MAJOR 0)
set(xc3sprog_VERSION_MINOR 0)

SET(CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}")
set(CMAKE_CXX_FLAGS "-g -Wall")
cmake_minimum_required(VERSION 3.12)

# Suppress developer warnings (specifically for PkgConfig naming issues)
set(CMAKE_SUPPRESS_DEVELOPER_WARNINGS ON CACHE BOOL "Suppress developer warnings" FORCE)

# Rest of your CMakeLists.txt content remains the same...
if(${WIN32})
set(USE_STATIC_FTDI ON)
IF( ${CMAKE_COMPILER_IS_GNUCXX} )
 # link libstdc++ and others statically
 add_definitions( -D__USE_MINGW_ANSI_STDIO )
 SET (CMAKE_EXE_LINKER_FLAGS    "-static-libstdc++ -static-libgcc")
ENDIF( ${CMAKE_COMPILER_IS_GNUCXX} )
endif(${WIN32})

option(USE_FTD2XX "Use FTDI libFTD2XX instead of free libftdi" ON)

find_package(libftdi)
include_directories(${LIBFTDI_INCLUDE_DIR})

if(USE_FTD2XX)
  find_package(libFTD2XX)
endif(USE_FTD2XX)

if(LIBFTD2XX_FOUND)
  include_directories(${LIBFTD2XX_INCLUDE_DIR})
  add_definitions( -DUSE_FTD2XX )
else(LIBFTD2XX_FOUND)
  set(LIBFTD2XX_LIBRARIES "")
endif(LIBFTD2XX_FOUND)

if(EXISTS ${PROJECT_SOURCE_DIR}/.git)
  set(VERSION_STRING "${xc3sprog_VERSION_MAJOR}.${xc3sprog_VERSION_MINOR}-git")
else(EXISTS ${PROJECT_SOURCE_DIR}/.git)
  FIND_PACKAGE(Subversion)
  IF(Subversion_FOUND AND EXISTS ${PROJECT_SOURCE_DIR}/.svn)
    Subversion_WC_INFO(${PROJECT_SOURCE_DIR} Project)
    set(VERSION_STRING "${xc3sprog_VERSION_MAJOR}.${xc3sprog_VERSION_MINOR}-svn${Project_WC_REVISION}")
  ELSE(Subversion_FOUND AND EXISTS ${PROJECT_SOURCE_DIR}/.svn)
    set(VERSION_STRING "unknown")
  ENDIF(Subversion_FOUND AND EXISTS ${PROJECT_SOURCE_DIR}/.svn)
endif(EXISTS ${PROJECT_SOURCE_DIR}/.git)

# Create suffix to eventually install inlib64
IF(CMAKE_SIZEOF_VOID_P EQUAL 4)
    SET(LIB_SUFFIX "")
    SET(PACK_ARCH ".x86")
  ELSE(CMAKE_SIZEOF_VOID_P EQUAL 8)
    SET(LIB_SUFFIX 64)
    SET(PACK_ARCH .x86_64)
endif(CMAKE_SIZEOF_VOID_P EQUAL 4)

# Package information
set(CPACK_PACKAGE_VERSION              ${VERSION_STRING})
set(CPACK_PACKAGE_CONTACT              "Uwe Bonnes <bon@elektron.ikp.physik.tu-darmstadt.de>")
set(CPACK_PACKAGE_DESCRIPTION          "JTAG Progarmming tools")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY  ${CPACK_PACKAGE_DESCRIPTION}
                                       )
# Package settings
if(${UNIX})
  set(CPACK_GENERATOR                    "DEB;RPM")
  set(CPACK_CMAKE_GENERATOR              "Unix Makefiles")
  set(CPACK_PACKAGE_NAME                 ${PROJECT_NAME})
  set(CPACK_PACKAGE_FILE_NAME            ${PROJECT_NAME}-${VERSION_STRING}${PACK_ARCH})
endif(${UNIX})

if(${WIN32})
  set(CPACK_GENERATOR                    "NSIS")
  set(CPACK_CMAKE_GENERATOR              "MinGW Makefiles")
  set(CPACK_PACKAGE_NAME                 "${PROJECT_NAME}")
  set(CPACK_PACKAGE_VENDOR               "")
  set(CPACK_PACKAGE_INSTALL_DIRECTORY    "libftdi")
  set(CPACK_PACKAGE_FILE_NAME            "${PROJECT_NAME}-${VERSION_STRING}-win32")
  set(CPACK_NSIS_DISPLAY_NAME            "libftdi")
  set(CPACK_NSIS_MODIFY_PATH             "ON")
endif(${WIN32})

set(CPACK_RESOURCE_FILE_LICENSE        ${CMAKE_SOURCE_DIR}/LICENSE)

set(CPACK_SOURCE_GENERATOR             TGZ)
set(CPACK_SOURCE_IGNORE_FILES          "\\\\.svn" "build*")
set(CPACK_SOURCE_PACKAGE_FILE_NAME     ${CPACK_PACKAGE_FILE_NAME})

# Subdirectories
if(${UNIX})
  set(CPACK_SET_DESTDIR "ON")
endif(${UNIX})

#link libusb dynamic at runtime on windows at at compile time else
#this circumvents a problem with Debian
set (CONDITIONAL_FILES)
set (CONDITIONAL_LIBS)
if("${CMAKE_SYSTEM_NAME}" STREQUAL "Windows")
   set (CONDITIONAL_FILES ${CONDITIONAL_FILES} "libusb_dyn.c")
else("${CMAKE_SYSTEM_NAME}" STREQUAL "Windows")
   find_package(libusb)
   include_directories(${LIBUSB_INCLUDE_DIR})
   set(CONDITIONAL_LIBS ${CONDITIONAL_LIBS} ${LIBUSB_LIBRARIES})
endif("${CMAKE_SYSTEM_NAME}" STREQUAL "Windows")

if(NOT "${CMAKE_SYSTEM_NAME}" STREQUAL "Darwin")
        set (CONDITIONAL_FILES ${CONDITIONAL_FILES} "ioparport.cpp")
endif(NOT "${CMAKE_SYSTEM_NAME}" STREQUAL "Darwin")

set (LIBUSRP_INCLUDE_DIR "fallback/")
include_directories(${LIBUSRP_INCLUDE_DIR})


include_directories(${CMAKE_SOURCE_DIR})

#add_executable(debug debug.cpp iobase.cpp ioparport.cpp iodebug.cpp)

add_executable(bitparse bitrev.cpp bitfile.cpp bitparse.cpp)
add_executable(jedecparse  jedecparse.cpp jedecfile.cpp)
add_executable(srecparse  srecparse.cpp srecfile.cpp)
add_executable(avrfuseparse  avrfuseparse.cpp avrfusefile.cpp)

ADD_CUSTOM_COMMAND(OUTPUT devices.h
    COMMAND ${CMAKE_COMMAND} -DDEVLIST_DIR=${CMAKE_SOURCE_DIR} -P ${CMAKE_SOURCE_DIR}/devlist.cmk
    DEPENDS devlist.txt
)

ADD_CUSTOM_COMMAND(OUTPUT cables.h
    COMMAND ${CMAKE_COMMAND} -DCABLELIST_DIR=${CMAKE_SOURCE_DIR} -P ${CMAKE_SOURCE_DIR}/cablelist.cmk
    DEPENDS cablelist.txt
)

INCLUDE_DIRECTORIES(BEFORE ${CMAKE_CURRENT_BINARY_DIR})

add_library(xc3sproglib  STATIC iogpiomatrixcreator.cpp iogpiomatrixvoice.cpp iogpiodpi.cpp ioftdi.cpp
                        iofx2.cpp devicedb.cpp jtag.cpp jedecfile.cpp bitfile.cpp
                        iobase.cpp  progalgxc95x.cpp utilities.cpp
                        progalgxcf.cpp progalgxcfp.cpp progalgxc3s.cpp
                        progalgavr.cpp progalgxc2c.cpp  mapfile_xc2c.cpp
                        ioxpc.cpp progalgspiflash.cpp bitrev.cpp
                        cabledb.cpp pdioverjtag.cpp xmega_pdi_nvm.cpp
                        ${CONDITIONAL_FILES} devices.h cables.h)


set(GPIO_LIBS ${GPIO_LIBS} gpiod)

add_executable(xc2c_warp xc2c_warp.cpp)
target_link_libraries(xc2c_warp xc3sproglib ${CONDITIONAL_LIBS} ${GPIO_LIBS})

add_executable(detectchain detectchain.cpp cables.h devices.h)
target_link_libraries(detectchain xc3sproglib ${LIBFTDI_LIBRARIES} ${LIBFTD2XX_LIBRARIES} ${CONDITIONAL_LIBS} ${GPIO_LIBS})

add_executable(xc3sprog xc3sprog.cpp javr.cpp srecfile.cpp progalgavr.cpp
                        devices.h)
target_link_libraries(xc3sprog xc3sproglib ${LIBFTDI_LIBRARIES}  ${LIBFTD2XX_LIBRARIES} ${CONDITIONAL_LIBS}  ${GPIO_LIBS})

add_executable(readdna readdna.cpp devices.h)
target_link_libraries(readdna xc3sproglib ${LIBFTDI_LIBRARIES}  ${LIBFTD2XX_LIBRARIES} ${CONDITIONAL_LIBS}  ${GPIO_LIBS})




install(TARGETS xc3sprog DESTINATION bin)
install(TARGETS xc2c_warp DESTINATION bin)
install(TARGETS readdna DESTINATION bin)
install(TARGETS bitparse DESTINATION bin)
install(TARGETS jedecparse DESTINATION bin)
install(TARGETS srecparse DESTINATION bin)
install(TARGETS detectchain DESTINATION bin)

# Install bscan_spi .bit files to share directory (following FHS)
file(GLOB BSCAN_BIT_FILES "${CMAKE_SOURCE_DIR}/bscan_spi/*.bit")
if(BSCAN_BIT_FILES)
    install(FILES ${BSCAN_BIT_FILES} DESTINATION share/xc3sprog/bscan_spi)
endif()

# Optionally install compressed .bit files too
file(GLOB BSCAN_BIT_GZ_FILES "${CMAKE_SOURCE_DIR}/bscan_spi/*.bit.gz")
if(BSCAN_BIT_GZ_FILES)
    install(FILES ${BSCAN_BIT_GZ_FILES} DESTINATION share/xc3sprog/bscan_spi)
endif()

# Install bscan_spi README for reference
if(EXISTS "${CMAKE_SOURCE_DIR}/bscan_spi/README.txt")
    install(FILES "${CMAKE_SOURCE_DIR}/bscan_spi/README.txt" 
            DESTINATION share/xc3sprog/bscan_spi)
endif()

# Install the fpga-jtag-flasher wrapper script
if(EXISTS "${CMAKE_SOURCE_DIR}/fpga-jtag-flasher.sh.in")
    # Configure the script template with install paths
    configure_file("${CMAKE_SOURCE_DIR}/fpga-jtag-flasher.sh.in"
                   "${CMAKE_BINARY_DIR}/fpga-jtag-flasher.sh"
                   @ONLY)
    install(PROGRAMS "${CMAKE_BINARY_DIR}/fpga-jtag-flasher.sh" 
            DESTINATION bin)
endif()
add_subdirectory(packages)
include(CPack)


SET_DIRECTORY_PROPERTIES(PROPERTIES ADDITIONAL_MAKE_CLEAN_FILES "${GENERATED_FILES}")
