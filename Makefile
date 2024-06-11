.PHONY: all clean

all:
	zig build

clean:
	rm -f zig-out/
