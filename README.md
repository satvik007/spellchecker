# spellchecker

Implementing https://norvig.com/spell-correct.html in rust, go and zig.

## Rust

`cargo test --release -- --nocapture`
rustc 1.75.0 (82e1608df 2023-12-21)

147 words per second

## Go

`go test -v`
go version go1.21.4 linux/amd64

92 words per second

## Zig

`zig test src/main.zig -O ReleaseFast`
0.12.0-dev.2341+92211135f

44.44444444444444 words per second

(Zig here is slower, please help me figure out why!)
