#version 410

//Input:
//Vertex data:
layout(location = 0) in vec4 position;

//Output:
//The value to sample:
out vec2 c;

//Uniforms:
//Half frame (Gaussian):
uniform vec2 gaussian_half_frame;

//Position (Gaussian):
uniform vec2 gaussian_position;

void main()
{
    //Set the current position (this is always (-1 | 1)^2):
    gl_Position = position;
    
    //Calculate c:
    c = gaussian_position + (position.xy * gaussian_half_frame);
}
