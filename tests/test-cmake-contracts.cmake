include("${BUILDER_ROOT}/cmake/LogosModule.cmake")

if(MODE STREQUAL "standard")
    # Isolate the pre-discovery contract. Real Qt configure/build is covered by
    # qml-integration; an old standard must fail before find_package is reached.
    macro(find_package)
        message(STATUS "REACHED_QT_DISCOVERY")
    endmacro()
    macro(qt_standard_project_setup)
    endmacro()
    logos_find_qt()
    if(NOT CMAKE_CXX_STANDARD EQUAL EXPECTED_STANDARD OR NOT CMAKE_CXX_STANDARD_REQUIRED)
        message(FATAL_ERROR "C++ standard not preserved/defaulted as required")
    endif()
    message(STATUS "STANDARD_OK=${CMAKE_CXX_STANDARD}")
elseif(MODE STREQUAL "rep")
    string(ASCII 239 187 191 UTF8_BOM)
    set(CASES
        "class Actual\n{\n}\n"
        "// class Legacy\nclass Actual\n{\n}\n"
        "/*\nclass Legacy\n*/\nclass Actual\n{\n}\n"
        "/** class Legacy ***/\n\tclass Actual\r\n{\n}\n"
        "// /* class Legacy\nclass Actual\n{\n}\n"
        "// /* class Legacy\nclass Actual\n{\n}\n/* later comment */\n"
        "/* // class Legacy\nclass Hidden\n*/\nclass Actual\n{\n}\n"
        "/* class Legacy */ class Actual\n{\n}\n"
        "#include \"class Legacy\"\n  class Actual\n{\n}\n"
        "class Actual\n{\n}\nclass Second\n{\n}\n"
        "${UTF8_BOM}class Actual\n{\n}\n"
        "${UTF8_BOM}/* class Legacy */ class Actual\n{\n}\n"
    )
    foreach(CONTENTS IN LISTS CASES)
        file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/probe.rep" "${CONTENTS}")
        _logos_parse_rep_class("${CMAKE_CURRENT_BINARY_DIR}/probe.rep" CLASS_NAME)
        if(NOT CLASS_NAME STREQUAL "Actual")
            message(FATAL_ERROR "Expected Actual, got ${CLASS_NAME}")
        endif()
    endforeach()
    message(STATUS "REP_CASES_OK")
elseif(MODE STREQUAL "rep-missing")
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/probe.rep" "// class Legacy\n/*\nclass Hidden\n*/\n")
    _logos_parse_rep_class("${CMAKE_CURRENT_BINARY_DIR}/probe.rep" CLASS_NAME)
    message(FATAL_ERROR "MISSING_CLASS_ACCEPTED")
else()
    message(FATAL_ERROR "Unknown test mode")
endif()
