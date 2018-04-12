CC = gcc
CFLAGS = -c -Wall -O3 -Iinclude
LD = $(CC)
LDFLAGS = -lm -lglfw

TARGET = mandel-gl
OBJECTS = $(patsubst %.c, %.o, $(wildcard src/*.c))

all: $(TARGET)

$(TARGET): $(OBJECTS)
	$(LD) -o $@ $^ $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) $^ -o $@

clean:
	rm -rf $(TARGET) $(OBJECTS)
