package logger

import "core:fmt"

info :: proc(args: ..any, sep := " "){
    fmt.println(args, sep)
}

debug :: proc(args: ..any, sep := " "){
    fmt.println(args, sep)
}

trace :: proc(args: ..any, sep := " "){
    fmt.println(args, sep)
}

warning :: proc(args: ..any, sep := " "){
    fmt.println(args, sep)
}

error :: proc(args: ..any, sep := " "){
    fmt.eprintln(args, sep)
}

fatal :: proc(args: ..any, sep := " "){
    fmt.eprintln(args, sep)
}