//
//  RenderView.swift
//  Almond Bread GL
//
//  Created by Jonas Treumer on 21.04.17.
//  Copyright © 2017 TU Bergakademie Freiberg. All rights reserved.
//

import UIKit

class RenderView: UIView, UIGestureRecognizerDelegate
{
    //Is this a checked (debug) build?
    private static let isCheckedBuild = false
    
    //Limit position and scale:
    private static let minPosition: Double = -3
    private static let maxPosition: Double = 3
    
    private static let minScale: Double = 75
    private static let maxScale: Double = 100000000
    
    //The GLES context:
    private let eaglContext: EAGLContext
    
    //The GLES layer (passed by the view):
    private var eaglLayer: CAEAGLLayer! = nil
    
    //Our framebuffer that is used for displaying and rendering.
    private var framebuffer: GLuint = 0
    
    //Our renderbuffer.
    //Red (1 byte)
    //Green (1 byte)
    //Blue (1 byte)
    //Unused (1 byte) <--- only because Apple manages the layer (kEAGLColorFormatRGBA8)!
    private var renderbuffer: GLuint = 0
    
    //Our drawbuffer comfiguration for the framebuffer:
    private static let drawbuffers = [GLenum(GL_COLOR_ATTACHMENT0)]
    
    //The current viewport in pixels:
    private var viewportWidthPx: UInt = 1
    private var viewportHeightPx: UInt = 1
    
    //The current clear color as GLubyte array:
    private var clearColor: [GLfloat] = [255 / 255.0, 255 / 255.0, 255 / 255.0, 255 / 255.0]
    
    //The display link (callback on new frame):
    private var displayLink: CADisplayLink! = nil
    
    //Helper property for us:
    private var isPaused: Bool = false
    {
        didSet
        {
            //Mark as dirty:
            self.isDirty = true
            
            //Running:
            if !self.isPaused
            {
                //Enable the display link:
                setDisplayLinkEnabled(true)
                
                //Set the current viewport:
                inGLESContext
                {
                    setViewport()
                }
                
                //We are done with resuming:
                return
            }
            
            //We have to pause. First, stop the display link:
            setDisplayLinkEnabled(false)
            
            //Finish rendering:
            inGLESContext
            {
                glFinish()
                RenderView.checkError(inDebugDomain: "Pausing", withErrorText: "Failed to join pipeline")
            }
        }
    }
    
    //We render on demand. Is the view currently dirty?
    private var isDirty = true
    
    //The vertex buffer object:
    private var vertexBufferObject: GLuint = 0
    
    //The shader program:
    private var shaderProgramHandle: GLuint = 0
    
    //The hue textures;
    private var hueTextures = [HueTexture: GLuint]()
    
    //The uniforms:
    private var gaussianPositionUniform: GLint = 0
    private var gaussianHalfFrameUniform: GLint = 0
    private var iterationsUniform: GLint = 0
    
    //The current supersampling factor:
    var superSamplingFactor = Double(UIScreen.main.scale)
    {
        didSet
        {
            //Mark as dirty:
            self.isDirty = true
            
            //Update the viewport if we are not paused:
            guard !self.isPaused else
            {
                return
            }
            
            inGLESContext
            {
                setViewport()
            }
        }
    }
    
    //The current multisampling level:
    var multiSamplingLevel = 0
    {
        didSet
        {
            //Mark as dirty:
            self.isDirty = true
            
            //Link the buffers if we are not paused:
            guard !self.isPaused else
            {
                return
            }
            
            inGLESContext
            {
                linkBuffers()
            }
        }
    }
    
    //The current position (Gaussian):
    var positionX: Double = 0
    {
        didSet
        {
            //Mark as dirty:
            self.isDirty = true
            
            //Clamp:
            self.positionX = max(RenderView.minPosition, min(self.positionX, RenderView.maxPosition))
        }
    }
    
    var positionY: Double = 0
    {
        didSet
        {
            //Mark as dirty:
            self.isDirty = true
            
            //Clamp:
            self.positionY = max(RenderView.minPosition, min(self.positionY, RenderView.maxPosition))
        }
    }
    
    //The current scale (point per Gaussian):
    var scale: Double = RenderView.minScale
    {
        didSet
        {
            //Mark as dirty:
            self.isDirty = true
            
            //Clamp:
            self.scale = max(RenderView.minScale, min(self.scale, RenderView.maxScale))
        }
    }
    
    //The iterations to perform:
    var iterations: UInt = 256
    {
        didSet
        {
            //Mark as dirty:
            self.isDirty = true
        }
    }
    
    //The current hue texture:
    var hueTexture: HueTexture = .fire
    {
        didSet
        {
            //MArk as dirty:
            self.isDirty = true
            
            //Bind the corresponding texture:
            inGLESContext
            {
                glBindTexture(GLenum(GL_TEXTURE_2D), self.hueTextures[self.hueTexture]!)
                RenderView.checkError(inDebugDomain: "Binding hue texture", withErrorText: "Failed to bind hue texture")
            }
        }
    }
    
    //Override the layer class to generate an instance of CAEAGLLayer:
    override public class var layerClass: AnyClass
    {
        return CAEAGLLayer.self
    }
    
    //Check for GLES errors:
    class func checkError(inDebugDomain dbgDomain: String, withErrorText dbgText: String)
    {
        //Only on checked builds:
        guard RenderView.isCheckedBuild else
        {
            return
        }
        
        let error = glGetError()
        precondition(error == GLenum(GL_NO_ERROR), "[\(dbgDomain)] \(dbgText) (\(error)).")
    }
    
    required init?(coder aDecoder: NSCoder)
    {
        let dbgDomain = "Initializing GLES view"
        
        //Try to initialize the context:
        guard let context = EAGLContext(api: .openGLES3) else
        {
            preconditionFailure("[\(dbgDomain)] Failed to create GLES 3.0 context.")
        }
        
        //Configure it:
        context.isMultiThreaded = false
        
        //Assign the context:
        self.eaglContext = context
        
        //Initialize the superview:
        super.init(coder: aDecoder)
        
        //Get the layer of this class as CAEAGLLayer:
        guard let eaglLayer = self.layer as? CAEAGLLayer else
        {
            preconditionFailure("[\(dbgDomain)] View's layer must be a CAEAGLLayer.")
        }
        
        //Assign it:
        self.eaglLayer = eaglLayer
        
        //Configure it:
        self.eaglLayer.contentsScale = CGFloat(self.superSamplingFactor)
        self.eaglLayer.drawableProperties = [kEAGLColorFormatRGBA8: kEAGLDrawablePropertyColorFormat]
        self.eaglLayer.isOpaque = true
        
        inGLESContext
        {
            //Initialize the framebuffer and renderbuffer:
            initializeFramebufferRenderbuffer()
        
            //Initialize GLES features (or, more precisely, disable them all):
            initializeGLESFeatures()
        
            //Set the viewport for the first time:
            setViewport()
            
            //Initialize the vertex data:
            initializeVertexData()
            
            //Initialize the shaders:
            initializeShaders()
            
            //Initialize the textures:
            initializeTextures()
        }
        
        //Enable the display link:
        setDisplayLinkEnabled(true)
        
        //Subscribe to app state:
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        
        //Initialize the gesture recognizers:
        initializeGestureRecognizers()
    }
    
    deinit
    {
        let dbgDomain = "Releasing GLES view"
        
        inGLESContext
        {
            //Finish rendering:
            glFinish()
            RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to join pipeline")
            
            //Delete VBO:
            glDeleteBuffers(1, &self.vertexBufferObject)
            RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to delete vertex buffer object")
            
            self.vertexBufferObject = 0
            
            //Delete shader program:
            glDeleteProgram(self.shaderProgramHandle)
            self.shaderProgramHandle = 0
            
            //Delete hue textures:
            var textureHandles: [GLuint] = self.hueTextures.values.map{ $0 }
            
            glDeleteTextures(GLsizei(textureHandles.count), &textureHandles)
            RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to delete hue textures")
            
            self.hueTextures.removeAll()
            
            //Delete framebuffer:
            glDeleteBuffers(1, &self.framebuffer)
            RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to delete framebuffer")
            
            self.framebuffer = 0
            
            //Delete renderbuffer:
            glDeleteBuffers(1, &self.renderbuffer)
            RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to delete renderbuffer")
            
            self.renderbuffer = 0
        }
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        //Mark as dirty:
        self.isDirty = true
        
        //Set our viewport if we are not paused:
        guard !self.isPaused else
        {
            return
        }
        
        inGLESContext
        {
            setViewport()
        }
    }
    
    public override func removeFromSuperview()
    {
        super.removeFromSuperview()
        
        //This counts as pausing:
        self.isPaused = true
    }
    
    public override func didMoveToSuperview()
    {
        super.didMoveToSuperview()
        
        //This counts as resuming:
        self.isPaused = false
    }
    
    //Sets our context and returns the old one:
    private func inGLESContext(closure: () -> Void)
    {
        let dbgDomain = "Setting context"
        
        //Get the current context to restore it later:
        let oldContext = EAGLContext.current()
        
        //Move to our new context:
        var success = EAGLContext.setCurrent(self.eaglContext)
        precondition(success, "[\(dbgDomain)] Failed to set current context.")
        
        //Execute the closure:
        closure()
        
        //Restore the old context:
        success = EAGLContext.setCurrent(oldContext)
        precondition(success, "[\(dbgDomain)] Failed to restore old context.")
    }
    
    ///Needs context.
    private func initializeFramebufferRenderbuffer()
    {
        let dbgDomain = "Initializing framebuffer"
        
        //Generate the framebuffer:
        glGenFramebuffers(1, &self.framebuffer)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to generate framebuffer")
        
        //Generate the renderbuffer:
        glGenRenderbuffers(1, &self.renderbuffer)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to generate renderbuffer")
        
        //Bind them as default binding:
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), self.framebuffer)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to bind framebuffer")
        
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), self.renderbuffer)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to bind renderbuffer")
    }
    
    ///Needs context.
    private func initializeGLESFeatures()
    {
        let dbgDomain = "Initializing GLES features"
        
        //Disable alpha blending:
        glDisable(GLenum(GL_BLEND))
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to disable alpha blending")
        
        //Disable the depth test:
        glDisable(GLenum(GL_DEPTH_TEST))
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to disable the depth test")
        
        glDepthMask(GLboolean(GL_FALSE))
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to disable the depth mask")
        
        //Disable the scissor test:
        glDisable(GLenum(GL_SCISSOR_TEST))
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to disable the scissor test")
        
        //Disable the stencil test:
        glDisable(GLenum(GL_STENCIL_TEST))
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to disable the stencil test")
        
        //Disable dithering:
        glDisable(GLenum(GL_DITHER))
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to disable dithering")
    }
    
    ///Needs context.
    private func initializeVertexData()
    {
        let dbgDomain = "Initializing vertex data"
        
        //Generate a VBO:
        glGenBuffers(1, &self.vertexBufferObject)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to generate VBO")
        
        //Bind it:
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), self.vertexBufferObject)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to bind VBO")
        
        //Create simple vertex data for the corners:
        let vertexData = [VertexData(position: (-1, -1)), VertexData(position: (1, -1)), VertexData(position: (-1, 1)), VertexData(position: (1, 1))]
        
        //Upload it:
        vertexData.withUnsafeBytes
        {
            glBufferData(GLenum(GL_ARRAY_BUFFER), GLsizeiptr($0.count), $0.baseAddress!, GLenum(GL_STATIC_DRAW))
        }
        
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to buffer vertex data")
        
        //Enable the array:
        let positionAttribute = GLuint(VERTEX_DATA_POSITION_ATTRIBUTE)
        
        glEnableVertexAttribArray(positionAttribute)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to enable position attribute")
        
        //Specify the vertex data:
        let stride = GLsizei(MemoryLayout.size(ofValue: VertexData.self))
        
        glVertexAttribPointer(positionAttribute, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), stride, UnsafeRawPointer(bitPattern: VERTEX_DATA_POSITION_OFFSET))
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to specify position attribute")
    }
    
    ///Needs context.
    private func initializeShaders()
    {
        let dbgDomain = "Initializing shaders"
        
        //Create the vertex shader:
        let vertexShaderHandle = createShader(withType: GLenum(GL_VERTEX_SHADER), andSourceFileName: "VertexShader")
        
        //Create the fragment shader:
        let fragmentShaderHandle = createShader(withType: GLenum(GL_FRAGMENT_SHADER), andSourceFileName: "FragmentShader")
        
        //Create the program:
        self.shaderProgramHandle = glCreateProgram()
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to generate shader program handle")
        
        //Attach the shaders:
        glAttachShader(self.shaderProgramHandle, vertexShaderHandle)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to attach vertex shader")
        
        glAttachShader(self.shaderProgramHandle, fragmentShaderHandle)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to attach fragment shader")
        
        //Link the program:
        glLinkProgram(self.shaderProgramHandle)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to link shader program")
        
        //Check if we had success:
        var linkingSuccess = GLint(GL_FALSE)
        
        glGetProgramiv(self.shaderProgramHandle, GLenum(GL_LINK_STATUS), &linkingSuccess)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to retrieve shader program parameter")
        
        if linkingSuccess != GLint(GL_TRUE)
        {
            //Retrieve the error message:
            var errorMessageRaw = Array<GLchar>(repeating: 0, count: 256)
            
            glGetProgramInfoLog(self.shaderProgramHandle, GLint(errorMessageRaw.count), nil, &errorMessageRaw)
            RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to retrieve shader program info log")
            
            //Print it and fail:
            preconditionFailure("[\(dbgDomain)] Failed to link shader program: \(NSString(utf8String: errorMessageRaw)!)")
        }
        
        //After we have linked the program, it's a good idea to detach the shaders from it:
        glDetachShader(self.shaderProgramHandle, vertexShaderHandle)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to detach vertex shader")
        
        glDetachShader(self.shaderProgramHandle, fragmentShaderHandle)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to detach fragment shader")
        
        //We don't need the shaders anymore, so we can delete them right here:
        glDeleteShader(vertexShaderHandle)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to delete vertex shader")
        
        glDeleteShader(fragmentShaderHandle)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to delete fragment shader")
        
        //Use our program from now on:
        glUseProgram(self.shaderProgramHandle)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to enable shader program")
        
        //Retrieve the uniforms:
        self.gaussianPositionUniform = glGetUniformLocation(self.shaderProgramHandle, "gaussianPosition")
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to retrieve uniform (gaussianPosition)")
        
        guard self.gaussianPositionUniform >= 0 else
        {
            preconditionFailure("[\(dbgDomain)] Uniform is not available: gaussianPosition")
        }
        
        self.gaussianHalfFrameUniform = glGetUniformLocation(self.shaderProgramHandle, "gaussianHalfFrame")
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to retrieve uniform (gaussianHalfFrame)")
        
        guard self.gaussianHalfFrameUniform >= 0 else
        {
            preconditionFailure("[\(dbgDomain)] Uniform is not available: gaussianHalfFrameUniform")
        }
        
        self.iterationsUniform = glGetUniformLocation(self.shaderProgramHandle, "iterations")
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to retrieve uniform (iterations)")
        
        guard self.iterationsUniform >= 0 else
        {
            preconditionFailure("[\(dbgDomain)] Uniform is not available: iterations")
        }
        
        //Set the texture uniform:
        let hueTextureUniform = glGetUniformLocation(self.shaderProgramHandle, "hueTexture")
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to retrieve uniform (hueTexture)")
        
        guard hueTextureUniform >= 0 else
        {
            preconditionFailure("[\(dbgDomain)] Uniform is not available: hueTextureUniform")
        }
        
        //Assign the value to this uniform (const):
        glUniform1i(hueTextureUniform, 0)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to assign to constant uniform (hueTexture)")
        
        //Release the shader compiler:
        glReleaseShaderCompiler()
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to release the shader compiler")
    }
    
    ///Needs context.
    private func createShader(withType shaderType: GLenum, andSourceFileName sourceFileName: String) -> GLuint
    {
        let dbgDomain = "Creating shader"
        
        //Load the soruce code:
        guard let url = Bundle.main.url(forResource: sourceFileName, withExtension: "glsl") else
        {
            preconditionFailure("[\(dbgDomain)] Failed to load source code for shader: \"\(sourceFileName)\"")
        }
        
        guard let sourceCode = try? String(contentsOf: url, encoding: String.Encoding.utf8) else
        {
            preconditionFailure("[\(dbgDomain)] Failed to load source code for shader: \"\(sourceFileName)\"")
        }
        
        //Create a shader of our type:
        let shaderHandle = glCreateShader(shaderType)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to generate shader handle")
        
        //Get a null-terminated raw char pointer to the source:
        var sourceCodeRaw = (sourceCode as NSString).utf8String
        
        //Pass the shader source down to GLES:
        glShaderSource(shaderHandle, 1, &sourceCodeRaw, nil)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to provide shader source code")
        
        //Compile the shader:
        glCompileShader(shaderHandle)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to compile shader")
        
        //Check if we had success:
        var compilationSuccess = GLint(GL_FALSE)
        
        glGetShaderiv(shaderHandle, GLenum(GL_COMPILE_STATUS), &compilationSuccess)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to retrieve shader parameter")
        
        if compilationSuccess != GLint(GL_TRUE)
        {
            //Retrieve the error message:
            var errorMessageRaw = [GLchar](repeating: 0, count: 256)
            
            glGetShaderInfoLog(shaderHandle, GLsizei(errorMessageRaw.count), nil, &errorMessageRaw)
            RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to retrieve shader info log")
            
            //Print it and fail:
            preconditionFailure("[\(dbgDomain)] Failed to compile a shader: \(NSString(utf8String: errorMessageRaw)!)")
        }
        
        //Return the shader handle:
        return shaderHandle
    }
    
    ///Needs context.
    private func initializeTextures()
    {
        let dbgDomain = "Initializing textures"
        
        //Activate the texture unit:
        glActiveTexture(GLenum(GL_TEXTURE0))
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to activate texture unit")
        
        //Create the textures:
        HueTexture.orderedValues.forEach{ self.hueTextures[$0] = createHueTexture(forHue: $0)}
    }
    
    ///Needs context.
    private func createHueTexture(forHue hue: HueTexture) -> GLuint
    {
        let dbgDomain = "Creating texture"
        
        //Read the bytes:
        guard let url = Bundle.main.url(forResource: hue.rawValue, withExtension: "rgba") else
        {
            preconditionFailure("[\(dbgDomain)] Failed to load hue texture: \"\(hue.rawValue)\"")
        }
        
        guard let pixelsData = try? Data(contentsOf: url) else
        {
            preconditionFailure("[\(dbgDomain)] Failed to read hue texture.")
        }
        
        var pixelsBytes = Array<UInt8>(repeating: 0, count: pixelsData.count)
        pixelsData.copyBytes(to: &pixelsBytes, count: pixelsData.count)
        
        //Calculate the pixels count:
        let pixelsCount = pixelsBytes.count / 4
        
        //TODO: Check PoT
        
        //Generate a texture handle:
        var textureHandle: GLuint = 0
        
        glGenTextures(1, &textureHandle)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to generate texture handle")
        
        //Bind our texture:
        glBindTexture(GLenum(GL_TEXTURE_2D), textureHandle)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to bind texture")
        
        //Set wrapping mode:
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLint(GL_CLAMP_TO_EDGE))
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to set wrapping for s")
        
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLint(GL_CLAMP_TO_EDGE))
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to set wrapping for t")
        
        //Provide the bytes:
        glTexStorage2D(GLenum(GL_TEXTURE_2D), 1, GLenum(GL_RGBA8), GLsizei(pixelsCount), 1)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to specify texture storage (2D)")
        
        glTexSubImage2D(GLenum(GL_TEXTURE_2D), 0, 0, 0, GLsizei(pixelsCount), 1, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), pixelsBytes)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to push texture data (2D)")
        
        //Set min filter:
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GLint(GL_NEAREST))
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to set texture minification filter")
        
        //Set mag filter:
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GLint(GL_NEAREST))
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to set texture magnification filter")
        
        //Return the texture handle:
        return textureHandle
    }
    
    private func initializeGestureRecognizers()
    {
        //Panning:
        let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(panDetected(_:)))
        
        panRecognizer.delegate = self
        
        self.addGestureRecognizer(panRecognizer)
        
        //Pinching:
        let pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(pinchDetected(_:)))
        
        pinchRecognizer.delegate = self
        
        self.addGestureRecognizer(pinchRecognizer)
    }
    
    ///Needs context.
    private func setViewport()
    {
        //Calculate our pixel size from the point size and the supersampling factor:
        self.viewportWidthPx = UInt(self.superSamplingFactor * Double(self.frame.width))
        self.viewportHeightPx = UInt(self.superSamplingFactor * Double(self.frame.height))
        
        //Set the new content scale for the layer:
        self.eaglLayer.contentsScale = CGFloat(self.superSamplingFactor)
        
        //We have to link the buffers again for the new viewport:
        linkBuffers()
        
        //Tell GLES:
        glViewport(0, 0, GLsizei(self.viewportWidthPx), GLsizei(self.viewportHeightPx))
        RenderView.checkError(inDebugDomain: "Setting viewport", withErrorText: "Failed to specify the viewport")
    }

    ///Needs context.
    private func linkBuffers()
    {
        let dbgDomain = "Linking buffers"
        
        //Specify the EAGL layer as storage for the renderbuffer:
        let success = self.eaglContext.renderbufferStorage(Int(GL_RENDERBUFFER), from: self.eaglLayer)
        precondition(success, "[\(dbgDomain)] Failed to specify renderbuffer's storage")
        
        //Attach the renderbuffer to the framebuffer as color attachment 0:
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_RENDERBUFFER), self.renderbuffer)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to attach display renderbuffer")
        
        //Propagate our drawbuffers:
        glDrawBuffers(GLsizei(RenderView.drawbuffers.count), RenderView.drawbuffers)
        RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to propagate drawbuffers")
        
        //Check the display framebuffer for completeness.
        //Only on checked builds!
        if RenderView.isCheckedBuild
        {
            let framebufferStatus = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
            precondition(framebufferStatus == GLenum(GL_FRAMEBUFFER_COMPLETE), "[\(dbgDomain)] Framebuffer is not complete (\(framebufferStatus))")
        }
    }
    
    private func setDisplayLinkEnabled(_ enabled: Bool)
    {
        if enabled && (self.displayLink == nil)
        {
            self.displayLink = CADisplayLink(target: self, selector: #selector(displayUpdated(_:)))
            self.displayLink.add(to: RunLoop.current, forMode: .default)
            self.displayLink.isPaused = false
        }
        else if !enabled && (self.displayLink != nil)
        {
            self.displayLink.invalidate()
            self.displayLink = nil
        }
    }
    
    @objc func displayUpdated(_ displayLink: CADisplayLink)
    {
        let dbgDomain = "Rendering frame"
        
        //Just to be sure: Are we paused?
        //This should never happen ...
        precondition(!self.isPaused, "[Starting render pass] Paused in render pass.")
        
        //Only render if the viewport has at least one pixel and is dirty:
        guard (self.viewportWidthPx > 0) && (self.viewportHeightPx > 0) && self.isDirty else
        {
            return
        }
        
        //After the pass, we are not dirty anymore:
        defer
        {
            self.isDirty = false
        }
        
        inGLESContext
        {
            //Provide Gaussian position and half frame as uniforms:
            glUniform2f(self.gaussianPositionUniform, GLfloat(self.positionX), GLfloat(self.positionY))
            RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to provide uniform (gaussianPosition)")
            
            glUniform2f(self.gaussianHalfFrameUniform, GLfloat(0.5 * Double(self.frame.width) / self.scale), GLfloat(0.5 * Double(self.frame.height) / self.scale))
            RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to provide uniform (gaussianPosition)")
            
            glUniform1ui(self.iterationsUniform, GLuint(self.iterations))
            RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to provide uniform (iterations)")
            
            //Clear the renderbuffer with the given clear color.
            //Second parameter means: drawbuffers[0] which is the renderbuffer.
            glClearBufferfv(GLenum(GL_COLOR), 0, self.clearColor)
            RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to clear renderbuffer")
            
            //Draw a full-screen-quad:
            glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
            RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to draw")
            
            //Present the content of the renderbuffer:
            self.eaglContext.presentRenderbuffer(Int(GL_RENDERBUFFER))
            
            //Invalidate the framebuffer:
            glInvalidateFramebuffer(GLenum(GL_FRAMEBUFFER), 1, RenderView.drawbuffers)
            RenderView.checkError(inDebugDomain: dbgDomain, withErrorText: "Failed to invalidate framebuffer")
        }
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool
    {
        if (gestureRecognizer is UIPanGestureRecognizer) && (otherGestureRecognizer is UIPinchGestureRecognizer)
        {
            return true
        }
        
        if (gestureRecognizer is UIPinchGestureRecognizer) && (otherGestureRecognizer is UIPanGestureRecognizer)
        {
            return true
        }
        
        return false
    }
    
    @objc func panDetected(_ panGR: UIPanGestureRecognizer)
    {
        defer
        {
            //Reset GR:
            panGR.setTranslation(CGPoint.zero, in: self)
            
            //Mark as dirty:
            self.isDirty = true
        }
        
        //Should we pan?
        guard !self.isPaused else
        {
            return
        }
        
        //Switch over the GR state:
        switch panGR.state
        {
        case .changed, .ended:
            
            //Get the translation in points and apply it:
            let point = panGR.translation(in: self)
            
            self.positionX -= Double(point.x) / self.scale
            self.positionY += Double(point.y) / self.scale
            
        default: ()
        }
    }
    
    @objc func pinchDetected(_ pinchGR: UIPinchGestureRecognizer)
    {
        defer
        {
            //Reset GR:
            pinchGR.scale = 1
            
            //Mark as dirty:
            self.isDirty = true
        }
        
        //Should we pinch?
        guard !self.isPaused else
        {
            return
        }
        
        //Switch over the GR state:
        switch pinchGR.state
        {
        case .changed, .ended:
            
            //Get the pinch center:
            let point = pinchGR.location(in: self)
            
            //Convert to Gaussian:
            let centerX = self.positionX + ((Double(point.x) - Double(0.5 * self.frame.width)) / self.scale)
            let centerY = self.positionY - ((Double(point.y) - Double(0.5 * self.frame.height)) / self.scale)
            
            //Execute the scale:
            self.scale *= Double(pinchGR.scale)
            
            //Move the saved Gaussian back to the center point:
            self.positionX = centerX - ((Double(point.x) - Double(0.5 * self.frame.width)) / self.scale)
            self.positionY = centerY + ((Double(point.y) - Double(0.5 * self.frame.height)) / self.scale)
            
        default: ()
        }
    }
    
    //App states (-> pausing):
    @objc func appWillResignActive()
    {
        self.isPaused = true
    }
    
    @objc func appDidBecomeActive()
    {
        self.isPaused = false
    }
    
    @objc func appDidEnterBackground()
    {
        self.isPaused = true
    }
    
    @objc func appWillEnterForeground()
    {
        self.isPaused = false
    }
}
