# CMakeLists.txt for libwebsockets Android integration
# Include this in your React Native module's CMakeLists.txt

cmake_minimum_required(VERSION 3.22)

# Get the directory where this file is located
get_filename_component(LWS_DIR ${CMAKE_CURRENT_LIST_FILE} DIRECTORY)

# Create imported library
add_library(libwebsockets STATIC IMPORTED)

# Set library path based on ABI
set_target_properties(libwebsockets PROPERTIES
    IMPORTED_LOCATION "${LWS_DIR}/${ANDROID_ABI}/lib/libwebsockets.a"
)

# Set include directories
target_include_directories(libwebsockets INTERFACE
    "${LWS_DIR}/${ANDROID_ABI}/include"
)

# Export as alias for easier use
add_library(websockets::websockets ALIAS libwebsockets)
