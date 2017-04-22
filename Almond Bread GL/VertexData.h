//
//  VertexData.h
//  Almond Bread GL
//
//  Created by Jonas Treumer on 21.04.17.
//  Copyright © 2017 TU Bergakademie Freiberg. All rights reserved.
//

#import <OpenGLES/ES3/gl.h>

#define VERTEX_DATA_POSITION_ATTRIBUTE 0

typedef struct
{
    GLfloat position[2];
} VertexData;

extern const size_t VERTEX_DATA_POSITION_OFFSET;
