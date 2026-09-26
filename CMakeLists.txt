cmake_minimum_required(VERSION 3.16)
project(cardgame_tools LANGUAGES CXX)

add_executable(rrespack tools/rrespack.cpp)
target_compile_features(rrespack PRIVATE cxx_std_17)
if(MSVC)
  target_compile_options(rrespack PRIVATE /W4 /permissive-)
else()
  target_compile_options(rrespack PRIVATE -Wall -Wextra -Wpedantic)
endif()

