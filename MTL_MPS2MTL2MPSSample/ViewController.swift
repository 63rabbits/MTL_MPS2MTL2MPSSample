//
//  ViewController.swift
//  MTL_MPS2MTL2MPSSample
//
//  Created by 63rabbits goodman on 2023/08/02.
//

import UIKit
import MetalKit
import MetalPerformanceShaders

let vertexData: [Float] = [-1, -1, 0, 1,
                            1, -1, 0, 1,
                           -1,  1, 0, 1,
                            1,  1, 0, 1]

let textureCoordinateData: [Float] = [0, 1,
                                      1, 1,
                                      0, 0,
                                      1, 0]

class ViewController: UIViewController, MTKViewDelegate {

    private let device = MTLCreateSystemDefaultDevice()!
    private var commandQueue: MTLCommandQueue!
    private var texture: MTLTexture!
    private var midTexture01: MTLTexture!
    private var midTexture02: MTLTexture!

    private var vertexBuffer: MTLBuffer!
    private var texCoordBuffer: MTLBuffer!
    private var renderPipeline01: MTLRenderPipelineState!
    private var renderPipeline02: MTLRenderPipelineState!
    private let renderPassDescriptor01 = MTLRenderPassDescriptor()
    private let renderPassDescriptor02 = MTLRenderPassDescriptor()

    @IBOutlet private weak var mtkView: MTKView!

    override func viewDidLoad() {
        super.viewDidLoad()

        setupMetal()

        loadTexture()

        makeBuffers()

        makePipeline(pixelFormat: texture.pixelFormat)

        mtkView.enableSetNeedsDisplay = true
        mtkView.setNeedsDisplay()
    }

    private func setupMetal() {
        commandQueue = device.makeCommandQueue()

        mtkView.device = device
        mtkView.delegate = self
        mtkView.framebufferOnly = false
    }

    private func loadTexture() {
        let textureLoader = MTKTextureLoader(device: device)
        texture = try! textureLoader.newTexture(
            name: "kerokero",
            scaleFactor: view.contentScaleFactor,
            bundle: nil)

        mtkView.colorPixelFormat = texture.pixelFormat

        // make mid-texture
        let midTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                                        pixelFormat: texture.pixelFormat,
                                        width: texture.width,
                                        height: texture.height,
                                        mipmapped: false)
        midTextureDescriptor.usage = [ .renderTarget, .shaderRead, .shaderWrite ]
        midTexture01 = device.makeTexture(descriptor: midTextureDescriptor)
        midTexture02 = device.makeTexture(descriptor: midTextureDescriptor)

    }
    
    private func makeBuffers() {
        var size: Int
        size = vertexData.count * MemoryLayout<Float>.size
        vertexBuffer = device.makeBuffer(bytes: vertexData, length: size, options: [])

        size = textureCoordinateData.count * MemoryLayout<Float>.size
        texCoordBuffer = device.makeBuffer(bytes: textureCoordinateData, length: size, options: [])
    }

    private func makePipeline(pixelFormat: MTLPixelFormat) {
        guard let library = device.makeDefaultLibrary() else {fatalError()}

        let descriptor01 = MTLRenderPipelineDescriptor()
        descriptor01.vertexFunction = library.makeFunction(name: "vertexThrough")
        descriptor01.fragmentFunction = library.makeFunction(name: "fragmentTurnOver")
        descriptor01.colorAttachments[0].pixelFormat = pixelFormat
        renderPipeline01 = try! device.makeRenderPipelineState(descriptor: descriptor01)

        // make this pipeline to fit image to mktview.
        let descriptor02 = MTLRenderPipelineDescriptor()
        descriptor02.vertexFunction = library.makeFunction(name: "vertexThrough")
        descriptor02.fragmentFunction = library.makeFunction(name: "fragmentThrough")
        descriptor02.colorAttachments[0].pixelFormat = pixelFormat
        renderPipeline02 = try! device.makeRenderPipelineState(descriptor: descriptor02)

    }



    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // nop
    }

    func draw(in view: MTKView) {
        guard MPSSupportsMTLDevice(device) else {return}

        guard let drawable = view.currentDrawable else {return}

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {fatalError()}

        // render pass #1
        let binary = MPSImageThresholdBinary(device: device,
                                             thresholdValue: 0.2,
                                             maximumValue: 1.0,
                                             linearGrayColorTransform: nil)
        binary.encode(commandBuffer: commandBuffer,
                      sourceTexture: texture,
                      destinationTexture: midTexture01)

        // render pass #2
        renderPassDescriptor01.colorAttachments[0].texture = midTexture02
        guard let renderEncoder01 = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor01) else {return}
        guard let renderPipeline01 = renderPipeline01 else {fatalError()}
        renderEncoder01.setRenderPipelineState(renderPipeline01)
        renderEncoder01.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder01.setVertexBuffer(texCoordBuffer, offset: 0, index: 1)
        renderEncoder01.setFragmentTexture(midTexture01, index: 0)
        renderEncoder01.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder01.endEncoding()

        // render pass #3
        let blur = MPSImageGaussianBlur(device: device, sigma: 10.0)
        blur.encode(commandBuffer: commandBuffer,
                      sourceTexture: midTexture02,
                      destinationTexture: midTexture01)

        // render pass #4 to fit the image into mktview.
        renderPassDescriptor02.colorAttachments[0].texture = drawable.texture
        guard let renderEncoder02 = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor02) else {return}
        guard let renderPipeline02 = renderPipeline02 else {fatalError()}
        renderEncoder02.setRenderPipelineState(renderPipeline02)
        renderEncoder02.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder02.setVertexBuffer(texCoordBuffer, offset: 0, index: 1)
        renderEncoder02.setFragmentTexture(midTexture01, index: 0)
        renderEncoder02.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder02.endEncoding()

        commandBuffer.present(drawable)

        commandBuffer.commit()

        commandBuffer.waitUntilCompleted()

    }
}

