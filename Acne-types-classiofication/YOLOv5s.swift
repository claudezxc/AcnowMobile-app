import CoreML
import Vision
import UIKit

struct YOLOv5sOutput: Identifiable {
    let id = UUID()
    let classLabel: String
    let confidence: Float
    let boundingBox: CGRect
}

class YOLOv5s {
    private let model: MLModel
    private let inputWidth: Int = 640
    private let inputHeight: Int = 640
    var confidenceThreshold: Float = 0.30  // Add this line

    
    init?() {
        guard let model = try? best(configuration: MLModelConfiguration()).model else {
            return nil
        }
        self.model = model
    }
    
    func detect(image: UIImage) -> [YOLOv5sOutput] {
        print("Input image size: \(image.size)")
        let resizedImage = image.resize(to: CGSize(width: inputWidth, height: inputHeight))
        guard let pixelBuffer = resizedImage.normalized() else {
            print("Failed to create normalized pixel buffer")
            return []
        }
        print("Resized image size: \(inputWidth)x\(inputHeight)")

        let inputFeatures = try? MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: pixelBuffer)])
        
        guard let outputFeatures = try? model.prediction(from: inputFeatures!),
              let outputArray = outputFeatures.featureValue(for: "var_909")?.multiArrayValue else {
            print("Failed to get output from model")
            return []
        }
        
        print("Output array shape: \(outputArray.shape)")
        return postprocess(features: outputArray)
    }
    
    private func postprocess(features: MLMultiArray) -> [YOLOv5sOutput] {
        var outputs: [YOLOv5sOutput] = []
        let gridSize = 80
        let numClasses = 5 // Adjust if your model has a different number of classes
        let confidenceThreshold: Float = 0.25
        
        print("Grid size: \(gridSize), Number of classes: \(numClasses)")
        
        for i in 0..<25200 {
                let confidence = Float(features[[0, i, 4] as [NSNumber]].doubleValue)
                guard confidence > confidenceThreshold else { continue }  
            
            var classProbs: [Float] = []
            for c in 0..<numClasses {
                classProbs.append(Float(features[[0, i, 5 + c] as [NSNumber]].doubleValue))
            }
            
            guard let maxIndex = classProbs.indices.max(by: { classProbs[$0] < classProbs[$1] }) else { continue }
            let maxProb = classProbs[maxIndex]
            
            let x = Float(features[[0, i, 0] as [NSNumber]].doubleValue)
            let y = Float(features[[0, i, 1] as [NSNumber]].doubleValue)
            let w = Float(features[[0, i, 2] as [NSNumber]].doubleValue)
            let h = Float(features[[0, i, 3] as [NSNumber]].doubleValue)

            let boundingBox = CGRect(x: CGFloat(x - w/2), y: CGFloat(y - h/2), width: CGFloat(w), height: CGFloat(h))
            
            outputs.append(YOLOv5sOutput(classLabel: getClassName(for: maxIndex),
                                         confidence: maxProb * confidence,
                                         boundingBox: boundingBox))
        }
        
        print("Number of detections before NMS: \(outputs.count)")
        let finalOutputs = nonMaxSuppression(outputs: outputs, iouThreshold: 0.5)
        print("Number of detections after NMS: \(finalOutputs.count)")
        return finalOutputs
    }
    
    private func getClassName(for index: Int) -> String {
        let classNames = ["comedone","nodule", "pustule", "papule",  "cyst"] // Update these to match your model's classes
        return index < classNames.count ? classNames[index] : "unknown"
    }
    
    private func nonMaxSuppression(outputs: [YOLOv5sOutput], iouThreshold: Float) -> [YOLOv5sOutput] {
        let sortedOutputs = outputs.sorted { $0.confidence > $1.confidence }
        var selected: [YOLOv5sOutput] = []
        
        for output in sortedOutputs {
            var shouldSelect = true
            
            for selectedOutput in selected {
                let iou = calculateIoU(boxA: output.boundingBox, boxB: selectedOutput.boundingBox)
                if iou > iouThreshold {
                    shouldSelect = false
                    break
                }
            }
            
            if shouldSelect {
                selected.append(output)
            }
        }
        
        return selected
    }
    
    private func calculateIoU(boxA: CGRect, boxB: CGRect) -> Float {
        let intersectionArea = boxA.intersection(boxB).area
        let unionArea = boxA.area + boxB.area - intersectionArea
        return Float(intersectionArea / unionArea)
    }
}

extension UIImage {
    func resize(to newSize: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        self.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return resizedImage
    }
    
    func normalized() -> CVPixelBuffer? {
        let attributes = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                          kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(self.size.width),
                                         Int(self.size.height),
                                         kCVPixelFormatType_32ARGB,
                                         attributes,
                                         &pixelBuffer)
        
        guard status == kCVReturnSuccess, let unwrappedPixelBuffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(unwrappedPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(unwrappedPixelBuffer)
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: pixelData,
                                      width: Int(self.size.width),
                                      height: Int(self.size.height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(unwrappedPixelBuffer),
                                      space: rgbColorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
            return nil
        }
        
        context.translateBy(x: 0, y: self.size.height)
        context.scaleBy(x: 1.0, y: -1.0)
        
        UIGraphicsPushContext(context)
        self.draw(in: CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height))
        UIGraphicsPopContext()
        CVPixelBufferUnlockBaseAddress(unwrappedPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        return unwrappedPixelBuffer
    }
}

extension CGRect {
    var area: CGFloat {
        return width * height
    }
}
