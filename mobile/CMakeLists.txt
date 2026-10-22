# Deadlines for Android. Build the .apk with build_apk.ps1; try changes on the PC with preview.py.
cmake_minimum_required(VERSION 3.21)
project(Deadlines VERSION 1.0 LANGUAGES CXX)

find_package(Qt6 6.12 REQUIRED COMPONENTS Gui Network Qml Quick)
qt_standard_project_setup(REQUIRES 6.12)

qt_add_executable(deadlines main.cpp)

qt_add_qml_module(deadlines
    URI Deadlines
    VERSION 1.0
    QML_FILES Main.qml logic.js
    RESOURCES fonts/NunitoRounded-Regular.ttf fonts/NunitoRounded-Bold.ttf
)

set_target_properties(deadlines PROPERTIES
    QT_ANDROID_PACKAGE_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/android"   # manifest, icon, theme
    QT_ANDROID_PACKAGE_NAME "com.deadlinesapp.deadlines"
    QT_ANDROID_APP_NAME "Deadlines"
    QT_ANDROID_VERSION_NAME "${PROJECT_VERSION}"
    QT_ANDROID_VERSION_CODE 1   # raise by one for every release, or phones won't take the update
)

# Network: Canvas sync downloads over https (QML's XMLHttpRequest uses it).
target_link_libraries(deadlines PRIVATE Qt6::Gui Qt6::Network Qt6::Qml Qt6::Quick)

# https on Android needs OpenSSL inside the app (Qt for Android has no other TLS backend).
# OPENSSL_ROOT_DIR holds <abi>/libcrypto_3.so and libssl_3.so (from KDAB's android_openssl).
if(ANDROID AND OPENSSL_ROOT_DIR)
    file(TO_CMAKE_PATH "${OPENSSL_ROOT_DIR}" openssl_dir)   # Windows backslashes would be read as escapes
    set_property(TARGET deadlines APPEND PROPERTY QT_ANDROID_EXTRA_LIBS
        "${openssl_dir}/${CMAKE_ANDROID_ARCH_ABI}/libcrypto_3.so"
        "${openssl_dir}/${CMAKE_ANDROID_ARCH_ABI}/libssl_3.so")
endif()
