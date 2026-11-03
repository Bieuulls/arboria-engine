# CMake generated Testfile for 
# Source directory: D:/ARBORIA_ENGINE/ARBORIA_MASTER_REPAIR/OFICIAL_FINAL_CLEAR/native/renderer
# Build directory: D:/ARBORIA_ENGINE/ARBORIA_MASTER_REPAIR/OFICIAL_FINAL_CLEAR/native/renderer/build_ubsan
# 
# This file includes the relevant testing commands required for 
# testing this directory and lists subdirectories to be tested as well.
add_test(arboria_native_core "D:/ARBORIA_ENGINE/ARBORIA_MASTER_REPAIR/OFICIAL_FINAL_CLEAR/native/renderer/build_ubsan/test_native_core.exe" "D:/ARBORIA_ENGINE/ARBORIA_MASTER_REPAIR/OFICIAL_FINAL_CLEAR/native/renderer/../../assets/dense_rock.vgmesh")
set_tests_properties(arboria_native_core PROPERTIES  WORKING_DIRECTORY "D:/ARBORIA_ENGINE/ARBORIA_MASTER_REPAIR/OFICIAL_FINAL_CLEAR/native/renderer" _BACKTRACE_TRIPLES "D:/ARBORIA_ENGINE/ARBORIA_MASTER_REPAIR/OFICIAL_FINAL_CLEAR/native/renderer/CMakeLists.txt;97;add_test;D:/ARBORIA_ENGINE/ARBORIA_MASTER_REPAIR/OFICIAL_FINAL_CLEAR/native/renderer/CMakeLists.txt;0;")
add_test(arboria_native_advanced "D:/ARBORIA_ENGINE/ARBORIA_MASTER_REPAIR/OFICIAL_FINAL_CLEAR/native/renderer/build_ubsan/test_native_advanced.exe")
set_tests_properties(arboria_native_advanced PROPERTIES  WORKING_DIRECTORY "D:/ARBORIA_ENGINE/ARBORIA_MASTER_REPAIR/OFICIAL_FINAL_CLEAR/native/renderer" _BACKTRACE_TRIPLES "D:/ARBORIA_ENGINE/ARBORIA_MASTER_REPAIR/OFICIAL_FINAL_CLEAR/native/renderer/CMakeLists.txt;101;add_test;D:/ARBORIA_ENGINE/ARBORIA_MASTER_REPAIR/OFICIAL_FINAL_CLEAR/native/renderer/CMakeLists.txt;0;")
