import SwiftUI

struct ClassifyView: View {
    let selectedImage: UIImage
    @State private var classificationResults: [YOLOv5sOutput] = []
    @State private var processedImage: UIImage?
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                Text("Classification Result")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding()
                
                if let processedImage = processedImage {
                    Image(uiImage: processedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width * 0.95, height: geometry.size.height * 0.8)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(radius: 10)
                } else {
                    ProgressView()
                        .frame(height: geometry.size.height * 0.8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.edgesIgnoringSafeArea(.all))
        }
        .navigationTitle("Classify")
        .onAppear {
            classifyImage()
        }
    }
    
    private func classifyImage() {
        guard let yolo = YOLOv5s() else {
            print("Failed to initialize YOLOv5s model")
            return
        }
        
        // Set the confidence threshold here
        yolo.confidenceThreshold = 0.3  // Adjust this value as needed
        
        let results = yolo.detect(image: selectedImage)
        self.classificationResults = results
        
        let processedImage = drawBoundingBoxes(on: selectedImage, with: results)
        self.processedImage = processedImage
    }
    
    private func drawBoundingBoxes(on image: UIImage, with results: [YOLOv5sOutput]) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        
        let processedImage = renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            
            let ctx = context.cgContext
            ctx.setLineWidth(9)  // Slightly thicker line for better visibility
            
            let scaleX = image.size.width / 640
            let scaleY = image.size.height / 640
            
            for result in results {
                // Choose color based on class
                let color: UIColor
                switch result.classLabel {
                case "comedone": color = .blue
                case "papule": color = .green
                case "pustule": color = .red
                case "nodule": color = .purple
                case "cyst": color = .orange
                default: color = .yellow
                }
                ctx.setStrokeColor(color.cgColor)
                
                // Center the bounding box on the object
                let centerX = result.boundingBox.midX * scaleX
                let centerY = result.boundingBox.midY * scaleY
                let width = result.boundingBox.width * scaleX
                let height = result.boundingBox.height * scaleY
                
                let rect = CGRect(x: centerX - width/2, y: centerY - height/2, width: width, height: height)
                
                ctx.addRect(rect)
                ctx.strokePath()
                
                // Draw a label for each box
                let label = "\(result.classLabel) (\(String(format: "%.2f", result.confidence)))"
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 30),  // Increased font size
                    .foregroundColor: UIColor.white
                ]
                
                let size = label.size(withAttributes: attributes)
                let textRect = CGRect(x: rect.minX, y: max(rect.minY - size.height - 4, 0), width: size.width + 8, height: size.height + 4)
                
                ctx.setFillColor(color.cgColor)
                ctx.fill(textRect)
                
                label.draw(in: textRect, withAttributes: attributes)
            }
        }
        
        return processedImage
    }
}
