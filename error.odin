package main

import "core:fmt"

errorf_line :: proc(line: u32, format: string, args: ..any) {
   fmt.printf("Error: line {}: ", line)
   fmt.printfln(format, ..args)
}

errorf_none :: proc(format: string, args: ..any) {
   fmt.printf("Error: ")
   fmt.printfln(format, ..args)
}

errorf_pos :: proc(pos: Token_Pos, format: string, args: ..any) {
   fmt.printf("Error: line {}, column {}: ", pos.line, pos.column)
   fmt.printfln(format, ..args)
}

expect_message :: proc(pos: Token_Pos, expected: Token_Type, got: Token_Type) {
   errorf_pos(pos, "Expected {} token, got: {}", expected, got)
}

infof :: proc(format: string, args: ..any) {
   fmt.printfln(format, ..args)
}
