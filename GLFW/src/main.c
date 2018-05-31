#include <math.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include <glad/glad.h>
#include <GLFW/glfw3.h>

//Limit position and scale:
#define MIN_POSITION -3.0
#define MAX_POSITION 3.0

#define MIN_SCALE 75.0
#define MAX_SCALE 100000000.0

#define MIN_ITERATIONS 2
#define MAX_ITERATIONS 1000

//Do we currently debug?
//Uncomment for OpenGL error checking!
//#define DEBUG

//The vertex data (pretty simple):
#define VERTEX_DATA_POSITION_ATTRIBUTE 0

//Scale factors:
#define MOUSE_WHEEL_FACTOR 0.25

//Macros:
#define MIN(a, b) (((a) < (b)) ? (a) : (b))
#define MAX(a, b) (((a) > (b)) ? (a) : (b))

#define CLAMPED_POSITION(v) (MIN(MAX((v), MIN_POSITION), MAX_POSITION))
#define CLAMPED_SCALE(v) (MIN(MAX((v), MIN_SCALE), MAX_SCALE))

typedef struct _vertex_data_t_
{
	GLfloat x;
	GLfloat y;
} vertex_data_t;

//The shader program:
typedef struct _shader_program_t_
{
	GLuint handle;
	GLint gaussian_position_uniform;
	GLint gaussian_half_frame_uniform;
	GLint iterations_uniform;
} shader_program_t;

//The user info:
typedef struct _user_info_t
{
	//The shader program and the uniforms:
	shader_program_t shader_program;

	//The hue texture handles:
	GLuint hue_texture_handles[4];

	//The current window size:
	int window_size[2];

	//The current cursor position:
	double cursor_position[2];

	//Are we panning?
	int is_panning;

	//The current position in the Gaussian plane:
	double position[2];

	//The current scale:
	double scale;

	//The current interations:
	int iterations;
} user_info_t;

//Pre-define the callbacks:
void error_callback(int error, const char* description);
void framebuffer_size_callback(GLFWwindow* window, int width, int height);
void window_size_callback(GLFWwindow* window, int width, int height);
void key_callback(GLFWwindow* window, int key, int scancode, int action, int mods);
void mouse_button_callback(GLFWwindow* window, int button, int action, int mods);
void cursor_pos_callback(GLFWwindow* window, double xoffset, double yoffset);
void scroll_callback(GLFWwindow* window, double xoffset, double yoffset);

//Read all bytes from a given file path.
//The resulting pointer must be freed!
int read_all_bytes(const char* file_path, int insert_trailing_zero, uint8_t** ptr)
{
	//Try to open the file:
	FILE* file = fopen(file_path, "rb");

	if (!file)
	{
		fprintf(stderr, "Failed to open file: %s\n", file_path);
		exit(EXIT_FAILURE);
	}

	//Seek the end:
	if (fseek(file, 0, SEEK_END))
	{
		fprintf(stderr, "Failed to seek end of file: %s\n", file_path);
		exit(EXIT_FAILURE);
	}

	//Get the file length:
	int file_length = ftell(file);
	int buffer_length;

	//Do we have to insert a trailing zero?
	if (insert_trailing_zero)
	{
		buffer_length = file_length + 1;
	}
	else
	{
		buffer_length = file_length;
	}

	//Rewind the file to the start:
	rewind(file);

	//Allocate space:
	*ptr = (uint8_t*)malloc(buffer_length);

	if (!*ptr)
	{
		fprintf(stderr, "Failed to allocate memory: %d bytes\n", buffer_length);
		exit(EXIT_FAILURE);
	}

	//Read all the bytes:
	if (fread(*ptr, 1, file_length, file) != file_length)
	{
		fprintf(stderr, "Failed to read file contents: %s\n", file_path);
		exit(EXIT_FAILURE);
	}

	//Close the file:
	fclose(file);

	//Set the trailing zero:
	if (insert_trailing_zero)
	{
		(*ptr)[buffer_length - 1] = 0;
	}

	return buffer_length;
}

//Check for an OpenGL error if we are not debugging:
void check_error(const char* dbg_domain, const char* error_text)
{
#ifdef DEBUG
	GLenum error = glGetError();

	if (error != GL_NO_ERROR)
	{
		printf("[%s] %s: %d\n", dbg_domain, error_text, error);
		exit(EXIT_FAILURE);
	}
#endif
}

GLFWwindow* create_glfw_window(user_info_t* user_info)
{
    printf("Creating window ...\n");

    //We want at least a 4.2 context:
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 1);

    //Enable forward-compatibility and use the core profile:
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

    //No depth and stencil buffer:
    glfwWindowHint(GLFW_DEPTH_BITS, 0);
    glfwWindowHint(GLFW_STENCIL_BITS, 0);

    //Spawn the window:
    GLFWwindow* window = glfwCreateWindow(user_info->window_size[0], user_info->window_size[1], "Mandel-GL", NULL, NULL);

    if (!window)
    {
    	fprintf(stderr, "Failed to create window.\n");
        exit(EXIT_FAILURE);
    }

    //Register all the window callbacks:
    glfwSetFramebufferSizeCallback(window, framebuffer_size_callback);
    glfwSetWindowSizeCallback(window, window_size_callback);
    glfwSetKeyCallback(window, key_callback);
    glfwSetMouseButtonCallback(window, mouse_button_callback);
    glfwSetCursorPosCallback(window, cursor_pos_callback);
    glfwSetScrollCallback(window, scroll_callback);

    return window;
}

void init_gl_features()
{
	printf("Initializing some GL features ...\n");
	const char dbg_domain[] = "Initializing GL features";

    //Disable alpha blending:
    glDisable(GL_BLEND);
    check_error(dbg_domain, "Failed to disable alpha blending");
    
    //Disable the depth test:
    glDisable(GL_DEPTH_TEST);
    check_error(dbg_domain, "Failed to disable the depth test");
    
    glDepthMask(GL_FALSE);
    check_error(dbg_domain, "Failed to disable the depth mask");
    
    //Disable the scissor test:
    glDisable(GL_SCISSOR_TEST);
    check_error(dbg_domain, "Failed to disable the scissor test");
    
    //Disable the stencil test:
    glDisable(GL_STENCIL_TEST);
    check_error(dbg_domain, "Failed to disable the stencil test");
    
    //Disable dithering:
    glDisable(GL_DITHER);
    check_error(dbg_domain, "Failed to disable dithering");
}

void init_vertex_data(GLuint* vertex_buffer_object, GLuint* vertex_array_object)
{
	printf("Uploading vertex data ...\n");
	const char dbg_domain[] = "Initializing vertex data";

	//Create and bind a dummy VAO (this is actually needed in desktop GL):
	glGenVertexArrays(1, vertex_array_object);
	check_error(dbg_domain, "Failed to generate VAO");

	glBindVertexArray(*vertex_array_object);
	check_error(dbg_domain, "Failed to bind VAO");

    //Generate a VBO:
    glGenBuffers(1, vertex_buffer_object);
    check_error(dbg_domain, "Failed to generate VBO");
    
    //Bind it:
    glBindBuffer(GL_ARRAY_BUFFER, *vertex_buffer_object);
    check_error(dbg_domain, "Failed to bind VBO");
    
    //Create simple vertex data for the corners:
    vertex_data_t vertex_data[] =
    {
    	{ .x = -1, .y = -1 },
    	{ .x = +1, .y = -1 },
    	{ .x = -1, .y = +1 },
    	{ .x = +1, .y = +1 }
    };
    
    //Upload it:
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertex_data), (const GLvoid*)vertex_data, GL_STATIC_DRAW);
    check_error(dbg_domain, "Failed to buffer vertex data");
    
    //Enable the array:
    glEnableVertexAttribArray(VERTEX_DATA_POSITION_ATTRIBUTE);
    check_error(dbg_domain, "Failed to enable position attribute");
    
    //Specify the vertex data:
    glVertexAttribPointer(VERTEX_DATA_POSITION_ATTRIBUTE, 2, GL_FLOAT, GL_FALSE, sizeof(vertex_data_t), (GLvoid*)offsetof(vertex_data_t, x));
    check_error(dbg_domain, "Failed to specify position attribute");
}

GLuint create_shader(GLenum shader_type, const char* file_path)
{
	const char dbg_domain[] = "Creating shader";

	//Read all the bytes:
	uint8_t* shader_source;
	read_all_bytes(file_path, 1, &shader_source);

    //Create a shader of our type:
    GLuint shader_handle = glCreateShader(shader_type);
    check_error(dbg_domain, "Failed to generate shader handle");

    //Pass the shader source down to OpenGL:
    glShaderSource(shader_handle, 1, (const GLchar**)&shader_source, NULL);
    check_error(dbg_domain, "Failed to provide shader source code");

    //Free the shader source:
    free(shader_source);

    //Compile the shader:
    glCompileShader(shader_handle);
    check_error(dbg_domain, "Failed to compile shader");

    //Check if we had success:
    GLint compilation_success;

    glGetShaderiv(shader_handle, GL_COMPILE_STATUS, &compilation_success);
    check_error(dbg_domain, "Failed to retrieve shader parameter");

    if (compilation_success != (GLint)GL_TRUE)
    {
        //Retrieve the error message:
        char error_message[256];

        glGetShaderInfoLog(shader_handle, 256, NULL, error_message);
        check_error(dbg_domain, "Failed to retrieve shader info log");

        //Print it and fail:
        fprintf(stderr, "[%s] Failed to compile a shader: %s\n", dbg_domain, error_message);
        exit(EXIT_FAILURE);
    }

    //Return the shader handle:
    return shader_handle;
}

void init_shader_program(shader_program_t* shader_program)
{
	printf("Compiling shaders ...\n");
	const char dbg_domain[] = "Initializing shaders";

    //Create the vertex shader:
    GLuint vertex_shader_handle = create_shader(GL_VERTEX_SHADER, "shaders/vertex_shader.glsl");
    
    //Create the fragment shader:
    GLuint fragment_shader_handle = create_shader(GL_FRAGMENT_SHADER, "shaders/fragment_shader.glsl");
    
    //Create the program:
    shader_program->handle = glCreateProgram();
    check_error(dbg_domain, "Failed to generate shader program handle");
    
    //Attach the shaders:
    glAttachShader(shader_program->handle, vertex_shader_handle);
    check_error(dbg_domain, "Failed to attach vertex shader");
    
    glAttachShader(shader_program->handle, fragment_shader_handle);
    check_error(dbg_domain, "Failed to attach fragment shader");
    
    //Link the program:
    glLinkProgram(shader_program->handle);
    check_error(dbg_domain, "Failed to link shader program");
    
    //Check if we had success:
    GLint linking_success;
    
    glGetProgramiv(shader_program->handle, GL_LINK_STATUS, &linking_success);
    check_error(dbg_domain, "Failed to retrieve shader program parameter");
    
    if (linking_success != (GLint)GL_TRUE)
    {
        //Retrieve the error message:
        char error_message[256];
        
        glGetProgramInfoLog(shader_program->handle, 256, NULL, error_message);
        check_error(dbg_domain, "Failed to retrieve shader program info log");
        
        //Print it and fail:
        fprintf(stderr, "[%s] Failed to link shader program: %s\n", dbg_domain, error_message);
        exit(EXIT_FAILURE);
    }
    
    //After we have linked the program, it's a good idea to detach the shaders from it:
    glDetachShader(shader_program->handle, vertex_shader_handle);
    check_error(dbg_domain, "Failed to detach vertex shader");
    
    glDetachShader(shader_program->handle, fragment_shader_handle);
    check_error(dbg_domain, "Failed to detach fragment shader");
    
    //We don't need the shaders anymore, so we can delete them right here:
    glDeleteShader(vertex_shader_handle);
    check_error(dbg_domain, "Failed to delete vertex shader");
    
    glDeleteShader(fragment_shader_handle);
    check_error(dbg_domain, "Failed to delete fragment shader");
    
    //Use our program from now on:
    glUseProgram(shader_program->handle);
    check_error(dbg_domain, "Failed to enable shader program");
    
    //Retrieve the uniforms:
    shader_program->gaussian_position_uniform = glGetUniformLocation(shader_program->handle, "gaussian_position");
    check_error(dbg_domain, "Failed to retrieve uniform (gaussian_position)");
    
    if (shader_program->gaussian_position_uniform < 0)
    {
        fprintf(stderr, "[%s] Uniform is not available: gaussian_position\n", dbg_domain);
        exit(EXIT_FAILURE);
    }
    
    shader_program->gaussian_half_frame_uniform = glGetUniformLocation(shader_program->handle, "gaussian_half_frame");
    check_error(dbg_domain, "Failed to retrieve uniform (gaussian_half_frame)");
    
    if (shader_program->gaussian_half_frame_uniform < 0)
    {
        fprintf(stderr, "[%s] Uniform is not available: gaussian_half_frame\n", dbg_domain);
        exit(EXIT_FAILURE);
    }
    
    shader_program->iterations_uniform = glGetUniformLocation(shader_program->handle, "iterations");
    check_error(dbg_domain, "Failed to retrieve uniform (iterations)");
    
    if (shader_program->iterations_uniform < 0)
    {
        fprintf(stderr, "[%s] Uniform is not available: iterations\n", dbg_domain);
        exit(EXIT_FAILURE);
    }

    //Set the texture uniform:
    GLint hue_texture_uniform = glGetUniformLocation(shader_program->handle, "hue_texture");
    check_error(dbg_domain, "Failed to retrieve uniform (hueTexture)");
    
    if (hue_texture_uniform < 0)
    {
        fprintf(stderr, "[%s] Uniform is not available: hue_texture_uniform\n", dbg_domain);
        exit(EXIT_FAILURE);
    }
    
    //Assign the value to this uniform (const):
    glUniform1i(hue_texture_uniform, 0);
    check_error(dbg_domain, "Failed to assign to constant uniform (hue_texture_uniform)");

    //Release the shader compiler:
    glReleaseShaderCompiler();
    check_error(dbg_domain, "Failed to release the shader compiler");
}

GLuint create_hue_texture(const char* file_path)
{
	const char dbg_domain[] = "Creating texture";

	//Read all the bytes:
	uint8_t* texture_data;
	int length = read_all_bytes(file_path, 0, &texture_data);

	//How many pixels are there?
	GLsizei pixels_count = length / 4;

	//TODO: Check PoT

	//Generate a texture handle:
	GLuint texture_handle;

	glGenTextures(1, &texture_handle);
	check_error(dbg_domain, "Failed to generate texture handle");

	//Bind our texture:
	glBindTexture(GL_TEXTURE_2D, texture_handle);
	check_error(dbg_domain, "Failed to bind texture");

	//Set wrapping mode:
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    check_error(dbg_domain, "Failed to set wrapping for s");
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    check_error(dbg_domain, "Failed to set wrapping for t");

    //Provide the bytes:
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, pixels_count, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, (const GLvoid*)texture_data);
    check_error(dbg_domain, "Failed to push texture data (2D)");

    //Free the texture data:
    free(texture_data);

    //Set min filter:
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    check_error(dbg_domain, "Failed to set texture minification filter");
    
    //Set mag filter:
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    check_error(dbg_domain, "Failed to set texture magnification filter");

    return texture_handle;
}

void init_textures(GLuint* hue_texture_handles)
{
	printf("Uploading textures ...\n");

    //Activate the texture unit:
    glActiveTexture(GL_TEXTURE0);
    check_error("Initializing textures", "Failed to activate texture unit");
    
    //Create the textures:
    hue_texture_handles[0] = create_hue_texture("textures/fire.rgba");
    hue_texture_handles[1] = create_hue_texture("textures/ice.rgba");
    hue_texture_handles[2] = create_hue_texture("textures/ash.rgba");
    hue_texture_handles[3] = create_hue_texture("textures/psychedelic.rgba");
}

void bind_texture(GLuint texture_handle)
{
	//Bind the new texture:
	glBindTexture(GL_TEXTURE_2D, texture_handle);
	check_error("Binding hue texture", "Failed to bind hue texture");
}

void render_frame(user_info_t* user_info)
{
	char dbg_domain[] = "Rendering frame";

	//Provide Gaussian position and half frame as uniforms:
	glUniform2f(user_info->shader_program.gaussian_position_uniform, (GLfloat)(user_info->position[0]), (GLfloat)(user_info->position[1]));
	check_error(dbg_domain, "Failed to provide uniform (gaussian_position)");

	glUniform2f(user_info->shader_program.gaussian_half_frame_uniform, (GLfloat)((0.5 * user_info->window_size[0]) / user_info->scale), (GLfloat)((0.5 * user_info->window_size[1]) / user_info->scale));
	check_error(dbg_domain, "Failed to provide uniform (gaussian_half_frame)");

	glUniform1ui(user_info->shader_program.iterations_uniform, (GLuint)(user_info->iterations));
	check_error(dbg_domain, "Failed to provide uniform (iterations)");

	//Clear the renderbuffer with the given clear color:
	glClear(GL_COLOR_BUFFER_BIT);
	check_error(dbg_domain, "Failed to clear renderbuffer");

	//Draw a full-screen-quad:
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	check_error(dbg_domain, "Failed to draw");
}

int main(void)
{
	printf("Hello Mandel-GL!\n");

	//Set an error callback to print out all problems from GLFW:
    glfwSetErrorCallback(error_callback);

    if (!glfwInit())
    {
    	fprintf(stderr, "Failed to initialize GLFW.\n");	
        exit(EXIT_FAILURE);
    }

    //Create and initialize a user info struct:
    user_info_t user_info;

    user_info.window_size[0] = 800;
    user_info.window_size[1] = 600;

    user_info.is_panning = 0;

    user_info.position[0] = 0;
    user_info.position[1] = 0;

    user_info.scale = MIN_SCALE;

    user_info.iterations = 500;

    //Create a GLFW window:
    GLFWwindow* window = create_glfw_window(&user_info);

    //Make the OpenGL context of the window current:
    glfwMakeContextCurrent(window);

    //Ask GLAD to load all the shiny modern OpenGL stuff for us:
    gladLoadGLLoader((GLADloadproc)glfwGetProcAddress);

    //Try to swap on every screen update:
    glfwSwapInterval(1);

    //Initialize some GL features:
    init_gl_features();

    //Set the viewport for the first time:
    int initial_width, initial_height;
    glfwGetFramebufferSize(window, &initial_width, &initial_height);

    glViewport(0, 0, initial_width, initial_height);
    check_error("Initializing", "Failed to specify initial viewport");

    //Initialize our vertex data:
    GLuint vertex_buffer_object;
    GLuint vertex_array_object;

    init_vertex_data(&vertex_buffer_object, &vertex_array_object);

    //Initialize our shader program and retrieve the uniform locations:
    init_shader_program(&user_info.shader_program);

    //Initialize the hue textures:
    init_textures(user_info.hue_texture_handles);

    //Bind the fire texture:
    bind_texture(user_info.hue_texture_handles[0]);

    //Save the user info in the window:
    glfwSetWindowUserPointer(window, (void*)&user_info);

    //Set the clear color:
    glClearColor(0, 0, 0, 1);
    check_error("Initializing", "Failed to specify clear color");

    //Enter the render loop:
    while (!glfwWindowShouldClose(window))
    {
    	//Render a frame:
    	render_frame(&user_info);

    	//Swap the buffers:
    	glfwSwapBuffers(window);

    	//Poll window events:
        glfwPollEvents();
    }

    //Delete the VAO:
    glDeleteVertexArrays(1, &vertex_array_object);
    check_error("Closing", "Failed to delete vertex array object");

    //Delete the VBO:
    glDeleteBuffers(1, &vertex_buffer_object);
    check_error("Closing", "Failed to delete vertex buffer object");

    //Delete the shader program:
    glDeleteProgram(user_info.shader_program.handle);
    check_error("Closing", "Failed to delete shader program");

    //Delete hue textures:
    glDeleteTextures(4, user_info.hue_texture_handles);
    check_error("Closing", "Failed to delete hue textures");

    //Destroy the window:
    glfwDestroyWindow(window);

    //Terminate GLFW:
    glfwTerminate();

    //We are done :)
    exit(EXIT_SUCCESS);
}

//All the callbacks:
void error_callback(int error, const char* description)
{
	fprintf(stderr, "GLFW error: %s\n", description);
}

void framebuffer_size_callback(GLFWwindow* window, int width, int height)
{
	//Apply as the new viewport:
	glViewport(0, 0, width, height);
	check_error("Changing viewport size", "Failed to specify new viewport");
}

void window_size_callback(GLFWwindow* window, int width, int height)
{
	//Get the user info:
	user_info_t* user_info = (user_info_t*)glfwGetWindowUserPointer(window);

	//Update width and height:
	user_info->window_size[0] = width;
	user_info->window_size[1] = height;
}

void key_callback(GLFWwindow* window, int key, int scancode, int action, int mods)
{
	//Get the user info:
	user_info_t* user_info = (user_info_t*)glfwGetWindowUserPointer(window);

	switch (key)
	{
	//Manage iterations:
	case GLFW_KEY_UP: user_info->iterations = MIN(user_info->iterations + 10, MAX_ITERATIONS); break;
	case GLFW_KEY_DOWN: user_info->iterations = MAX(user_info->iterations - 10, MIN_ITERATIONS); break;

	//Bind different textures:
	case GLFW_KEY_1: bind_texture(user_info->hue_texture_handles[0]); break;
	case GLFW_KEY_2: bind_texture(user_info->hue_texture_handles[1]); break;
	case GLFW_KEY_3: bind_texture(user_info->hue_texture_handles[2]); break;
	case GLFW_KEY_4: bind_texture(user_info->hue_texture_handles[3]); break;
	}
}

void mouse_button_callback(GLFWwindow* window, int button, int action, int mods)
{
	//Get the user info:
	user_info_t* user_info = (user_info_t*)glfwGetWindowUserPointer(window);

	//Start / stop panning:
	if (button == GLFW_MOUSE_BUTTON_LEFT)
	{
		user_info->is_panning = (action == GLFW_PRESS);
	}
}

void cursor_pos_callback(GLFWwindow* window, double xoffset, double yoffset)
{
	//Get the user info:
	user_info_t* user_info = (user_info_t*)glfwGetWindowUserPointer(window);

	//Are we panning?
	if (user_info->is_panning)
	{
		user_info->position[0] = CLAMPED_POSITION(user_info->position[0] - ((xoffset - user_info->cursor_position[0]) / user_info->scale));
		user_info->position[1] = CLAMPED_POSITION(user_info->position[1] + ((yoffset - user_info->cursor_position[1]) / user_info->scale));
	}

	//Save the new position:
	user_info->cursor_position[0] = xoffset;
	user_info->cursor_position[1] = yoffset;
}

void scroll_callback(GLFWwindow* window, double xoffset, double yoffset)
{
	//Get the user info:
	user_info_t* user_info = (user_info_t*)glfwGetWindowUserPointer(window);
    
    //Calculate delta to center:
    double delta_x = user_info->cursor_position[0] - (0.5 * user_info->window_size[0]);
    double delta_y = user_info->cursor_position[1] - (0.5 * user_info->window_size[1]);

    //Convert the cursor position to Gaussian:
    double center_x = user_info->position[0] + (delta_x / user_info->scale);
    double center_y = user_info->position[1] - (delta_y / user_info->scale);
    
	//Set the new scale:
	user_info->scale = CLAMPED_SCALE(pow(2, MOUSE_WHEEL_FACTOR * yoffset) * user_info->scale);
    
    //Move the saved Gaussian back to the center point:
    user_info->position[0] = CLAMPED_POSITION(center_x - (delta_x / user_info->scale));
    user_info->position[1] = CLAMPED_POSITION(center_y + (delta_y / user_info->scale));
}
