CC = gcc
CCFLAGS = -Wall -O3 -Iinclude -lm -lglfw
EMCC = emcc
EMCCFLAGS = -Wall -O3 -Iinclude -s USE_GLFW=3 -s MAX_WEBGL_VERSION=2 --preload-file shaders/ --preload-file textures/

SRC = $(wildcard src/*.c)
OBJ = $(patsubst %.c, %.o, $(SRC))

NAME = mandel-gl
BIN = $(NAME)
WEB_HTML = $(NAME).html
WEB_JS = $(NAME).js
WEB_WASM = $(NAME).wasm
WEB_DATA = $(NAME).data

.PHONY: all bin web clean

all: bin web
bin: $(BIN)
web: $(WEB_HTML)

$(BIN): $(SRC)
	$(CC) $(CCFLAGS) -o $@ $^

$(WEB_HTML): $(SRC)
	$(EMCC) $(EMCCFLAGS) -o $@ $^

clean:
	rm -rf $(OBJ) $(BIN) $(WEB_HTML) $(WEB_JS) $(WEB_WASM) $(WEB_DATA)
