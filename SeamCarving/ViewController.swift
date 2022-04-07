//
//  ViewController.swift
//  SeamCarving
//
//  Created by Leander Masopust on 19.11.21.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import CoreFoundation

// code snippet from SO to measure time needed for certain code parts
// https://stackoverflow.com/questions/24755558/measure-elapsed-time-in-swift
class ParkBenchTimer {

    let startTime:CFAbsoluteTime
    var endTime:CFAbsoluteTime?

    init() {
        startTime = CFAbsoluteTimeGetCurrent()
    }

    func stop() -> CFAbsoluteTime {
        endTime = CFAbsoluteTimeGetCurrent()

        return duration!
    }

    var duration:CFAbsoluteTime? {
        if let endTime = endTime {
            return endTime - startTime
        } else {
            return nil
        }
    }
}
// code snippet from SO to close keyboard when tapping around
//https://stackoverflow.com/questions/24126678/close-ios-keyboard-by-touching-anywhere-using-swift
extension UIViewController {
    func hideKeyboardWhenTappedAround() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(UIViewController.dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    @objc func dismissKeyboard() {
        view.endEditing(true)
    }
}

class ImageSaver: NSObject {
    func writeToPhotoAlbum(image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(saveCompleted), nil)
    }

    @objc func saveCompleted(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        print("Save finished!")
    }
}

// custom CIFilter to calculate energyMap with metal kernel
class EnergyMapFilter: CIFilter {
    private let kernel: CIKernel
    var inputImage: CIImage?
    override init() {

        // initialize kernel from metallib
        let url = Bundle.main.url(forResource: "default", withExtension: "metallib")!
        let data = try! Data(contentsOf: url)
        kernel = try! CIKernel(functionName: "energyMap", fromMetalLibraryData: data)
        super.init()
    }
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // calculates and returns energyMap
    func outputImage() -> CIImage? {

        // sample given inputImage
        let sampler = CISampler.init(image:inputImage!)

        // apply kernel to sampled image and return result
        return kernel.apply(extent: inputImage!.extent, roiCallback: {(index,rect)-> CGRect in return rect}, arguments: [sampler, inputImage!.extent.width, inputImage!.extent.height])
    }
}

class ViewController: UIViewController, UINavigationControllerDelegate, UIImagePickerControllerDelegate {

    // UI components
    @IBOutlet var imageView: UIImageView!
    @IBOutlet var selectButton: UIButton!
    @IBOutlet var carveButton: UIButton!
    @IBOutlet var frameButton: UIButton!
    @IBOutlet var labelX: UILabel!
    @IBOutlet var labelY: UILabel!
    @IBOutlet var inputX: UITextField!
    @IBOutlet var inputY: UITextField!

    // picker for choosing image out of gallery
    var imagePicker = UIImagePickerController()

    // width and height of internal CGImage, for height carving width = height of picture and height = width of picture
    var width = 0
    var height = 0


    var frame: CGImage? = nil
    var image: CGImage? = nil

    // seams, seamMap, energyMap of current iteration for global access
    var seams: [[Int]]? = nil
    var seamMap: [[CGFloat]]? = nil
    var energyMap: CGImage? = nil

    // raw data of energyMap for global access and to avoid recalculation
    var energyMapDataPointer: UnsafePointer<UInt8>? = nil

    // alpha map extracted for constraints
    var alphaMap: [[UInt8]]? = nil

    // file name of frame that is supposed to be carved
    var frameFileName: String = "frame-1"

    // single, global instance of EnergyMapFilter
    var filter = EnergyMapFilter()

    // part of experiment to carve multiple seams without recalculating seamMap/energyMap
    var seamAmount = 1
    var seamAmountCurrent = 0
    var startWidth = 0
    var carvedHeight = 0

    // timing the time used for each calculation step
    var energyMapTime = 0.0
    var seamMapTime = 0.0
    var seamTime = 0.0
    var seamRemovalTime = 0.0

    override func viewDidLoad() {
        super.viewDidLoad()
        self.hideKeyboardWhenTappedAround()
    }

    // choose image out of gallery
    @IBAction func selectImage() {
        if UIImagePickerController.isSourceTypeAvailable(.savedPhotosAlbum) {
            imagePicker.delegate = self
            imagePicker.sourceType = .savedPhotosAlbum
            imagePicker.allowsEditing = true
            present(imagePicker, animated: true, completion: nil)
        }
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]){
        guard let image = info[.editedImage] as? UIImage else {return}
        self.dismiss(animated: true, completion: { () -> Void in})

        // enable frame selection
        self.frameButton.isEnabled = true

        // disable carving without choosing a frame
        self.carveButton.isEnabled = false

        // set global variables and updated imageView
        imageView.image = image
        seamMap = nil
        seams = nil
        energyMap = nil
        energyMapDataPointer = nil

        // update extent textfields
        labelX.text = "\(Int(image.cgImage!.width))"
        labelY.text = "\(Int(image.cgImage!.height))"
    }

    @IBAction func selectFrame() {
            // store selected image into img
            frame = imageView.image!.cgImage!

            // load frame image
            let f1 = UIImage.init(named:self.frameFileName)
            let width2 = f1!.cgImage!.width
            let height2 = f1!.cgImage!.height
            alphaMap = [[UInt8]](repeating: [UInt8](repeating: 0, count: width2), count: height2)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bytesPerPixel:Int = 4
            let bytesPerRow = 4 * width2
            let bitsPerComponent = 8
            let dataSize =  width2 * bytesPerPixel * height2
            var rawData = [UInt8](repeating: 0, count: Int(dataSize))
            let bitmapInfo = f1!.cgImage!.bitmapInfo.rawValue
            let context = CGContext(data: &rawData, width: width2, height: height2, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)!
            context.draw(f1!.cgImage!, in: CGRect(x: 0, y: 0, width: width2, height: height2))

            var byteIndex = 0

            // Iterate through pixels
            while byteIndex < dataSize {

                // Get Column and Row of current pixel
                let column =  ((byteIndex / 4) % (bytesPerRow/4))
                let row = ((byteIndex - (column*4)) / bytesPerRow )

                // retrieve alpha channel for explicit pixel that are not to carve (a=255)
                alphaMap![row][column] = rawData[byteIndex + 3]

                byteIndex += 4
            }
            // load extra image without alpha information since the other .png files have RGBA = (0,0,0,0) everywhere, where alpha = 0. workaround for specific given frame files.
            let noalpha = UIImage.init(named:self.frameFileName + "-noalpha")
            imageView.image = noalpha
            image = frame!
            frame = noalpha!.cgImage!

            // set/reset global vars
            width = frame!.width
            height = frame!.height
            labelX.text = "\(Int(imageView.image!.size.width))"
            labelY.text = "\(Int(imageView.image!.size.height))"
            seamMap = nil
            seams = nil
            energyMap = nil
            energyMapDataPointer = nil
            self.carveButton.isEnabled = true
            self.frameButton.isEnabled = false
        }

    // helper function to transpose alphaMap matrix
    func transposeAlphaMap(matrix: [[UInt8]]) {
        var newMatrix = [[UInt8]](repeating:[UInt8](repeating: 0, count: matrix.count), count: matrix[0].count)
        for y in 0..<matrix.count {
            for x in 0..<matrix[y].count {
                newMatrix[x][y] = matrix[y][x]
            }
        }
        alphaMap! = newMatrix
    }

    // calculate difference to carve by calculating (255,0,255) part of frame
    func calculateDifference() -> [Int] {
            var counterHeight = 0
            var counterWidth = 0
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bytesPerPixel:Int = 4
            let bytesPerRow = 4 * width
            let bitsPerComponent = 8
            let dataSize =  width * bytesPerPixel * height
            var rawData = [UInt8](repeating: 0, count: Int(dataSize))
            let bitmapInfo = frame!.bitmapInfo.rawValue
            let context = CGContext(data: &rawData, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)!

            context.draw(frame!, in: CGRect(x: 0, y: 0, width: width, height: height))

            var byteIndex = 0
            // Iterate through pixels
            while byteIndex < dataSize {
                let r = rawData[byteIndex + 0]
                let g = rawData[byteIndex + 1]
                let b = rawData[byteIndex + 2]
                let column =  ((byteIndex / 4) % (bytesPerRow/4))
                let row = ((byteIndex - (column*4)) / bytesPerRow )

                // while key color and remains in same line, count for width
                if(r >= 254 && g <= 1 && b >= 254 && row == 500) {
                    counterWidth += 1
                }
                if(r >= 254 && g <= 1 && b >= 254 && column == 500) {
                    counterHeight += 1
                }
                byteIndex += 4
            }
            counterWidth -= image!.width
            counterHeight -= image!.height
            return [counterWidth, counterHeight]
        }

    // replace placeholder part of frame with original image
    func placeImageInFrame() {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel:Int = 4
        let bitsPerComponent = 8

        // context for frame data
        let bytesPerRow = 4 * width
        let dataSize =  width * bytesPerPixel * height
        var rawData = [UInt8](repeating: 0, count: Int(dataSize))
        let bitmapInfo = frame!.bitmapInfo.rawValue
        let context = CGContext(data: &rawData, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)!

        // context for image data
        let bytesPerRowImg = 4 * image!.width
        var rawDataImg = [UInt8](repeating: 0, count: Int(dataSize))
        let bitmapInfoImg = image!.bitmapInfo.rawValue
        let contextImg = CGContext(data: &rawDataImg, width: image!.width, height: image!.height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRowImg, space: colorSpace, bitmapInfo: bitmapInfoImg)!

        context.draw(frame!, in: CGRect(x: 0, y: 0, width: width, height: height))
        contextImg.draw(image!, in: CGRect(x: 0, y: 0, width: image!.width, height: image!.height))

        var byteIndex = 0
        var byteCounterImg = 0

        // Iterate through pixels
        while byteIndex < dataSize {

            let r = rawData[byteIndex + 0]
            let g = rawData[byteIndex + 1]
            let b = rawData[byteIndex + 2]

            // identify if pixel is to fill with image data
            if(r > 250 && g < 50 && b > 250) {
                var originalImageColumn = ((byteCounterImg / 4) % (bytesPerRowImg/4))

                // skip end of row if bytesPerRow has overflow over width
                while(originalImageColumn > image!.width) {
                    byteCounterImg += 4
                    originalImageColumn = ((byteCounterImg / 4) % (bytesPerRowImg/4))
                }

                // write image pixel information into place-to-fill
                rawData[byteIndex + 0] = rawDataImg[byteCounterImg + 0]
                rawData[byteIndex + 1] = rawDataImg[byteCounterImg + 1]
                rawData[byteIndex + 2] = rawDataImg[byteCounterImg + 2]

                byteCounterImg += 4
            }
            byteIndex += 4
        }

        // retrieve image from context
        frame = context.makeImage()!

        // set UI in main Thread
        DispatchQueue.main.async {
            self.imageView.image =  UIImage(cgImage: self.frame!)
            self.imageView.setNeedsDisplay()
        }
    }

    @IBAction func startCarving() {

        // set global variables
        width = frame!.width
        height = frame!.height

        // get number of pixels to carve for each dimension
        let difference = self.calculateDifference()
        let xReductionInput = difference[0]
        let yReductionInput = difference[1]

        // checks for faulty input
        if (imageView.image?.cgImage == nil){return}
        if (xReductionInput < 0) {return}
        if (yReductionInput < 0) {return}
        if (Int(imageView.image!.size.width) - xReductionInput <= 1) {return}
        if (Int(imageView.image!.size.height) - yReductionInput <= 1) {return}

        // return if there is nothing to carve
        if (xReductionInput + yReductionInput <= 0) {return}

        DispatchQueue(label: "l").async {
            // disable carve button and select button
            DispatchQueue.main.sync {
                self.carveButton.isEnabled = false
                self.selectButton.isEnabled = false
                self.frameButton.isEnabled = false
            }

            // start carving timer
            let timer = ParkBenchTimer()

            self.carveWidth(xReductionInput: xReductionInput)
            self.carveHeight(yReductionInput: yReductionInput)
            self.placeImageInFrame()

            // dump time outputs
            print("The EnergyMap took \(self.energyMapTime) seconds.")
            print("The SeamMap took \(self.seamMapTime) seconds.")
            print("The Seam took \(self.seamTime) seconds.")
            print("The Removal of Seam took \(self.seamRemovalTime) seconds.")
            print("The Carving took \(timer.stop()) seconds.")

            // enable carve button and select button
            DispatchQueue.main.sync {
                ImageSaver().writeToPhotoAlbum(image: self.imageView.image!)
                self.carveButton.isEnabled = true
                self.selectButton.isEnabled = true
                self.frameButton.isEnabled = true
            }
        }
    }
    func carveWidth(xReductionInput: Int) {
        self.startWidth = width
        self.carve(pixel: xReductionInput, dimension: "width")
    }
    func carveHeight(yReductionInput: Int)  {

        // carving height by rotating img: CGImage by 270° and counterrotating the UIImageView
        // so the displayed image doesn't get rotated even though the image is rotated
        // and thus gets carved in height

        DispatchQueue.main.sync {

            // get original x,y origin points from imageView
            let x = imageView.frame.minX
            let y = imageView.frame.minY

            // rotate img 270° clockwise
            let ci = CIImage(cgImage: frame!).oriented(.left)
            frame = CIContext().createCGImage(ci, from: ci.extent)

            // rotate UIImageView 90° clockwise
            imageView.transform = imageView.transform.rotated(by: .pi / 2)

            // set imageView frame so the imageView scaling doesn't change
            imageView.frame = CGRect(x: x, y: y,
                                     width: imageView.frame.height, height: imageView.frame.width)

            // finally set the rotated image into the rotated imageView
            imageView.image = UIImage(cgImage:frame!)

            // resetting global variables
            seamMap = nil
            seams = nil
            energyMap = nil
            energyMapDataPointer = nil
            width = frame!.width
            height = frame!.height
        }
        self.startWidth = width

        // reverse rows + transpose alphaMap so it maps back to img
        for i in 0..<alphaMap!.count {
            alphaMap![i] = alphaMap![i].reversed()
        }
        transposeAlphaMap(matrix: alphaMap!)

        // start carving
        carve(pixel: yReductionInput, dimension: "height")

        DispatchQueue.main.sync {

            // get original x,y origin points from imageView
            let x = imageView.frame.minX
            let y = imageView.frame.minY

            // rotate img 90° clockwise
            let ci = CIImage(cgImage: frame!).oriented(.right)
            frame = CIContext().createCGImage(ci, from: ci.extent)

            // rotate UIImageView 270° clockwise
            imageView.transform = imageView.transform.rotated(by: .pi * 1.5)

            // set imageView frame so the imageView scaling doesn't change
            imageView.frame = CGRect(x: x, y: y,
                                     width: imageView.frame.height, height: imageView.frame.width)

            // finally set the rotated image into the rotated imageView
            self.imageView.image =  UIImage(cgImage: self.frame!)

            // resetting global variables
            seamMap = nil
            seams = nil
            energyMap = nil
            energyMapDataPointer = nil
            width = frame!.width
            height = frame!.height
        }

    }

    func carve(pixel: Int, dimension: String)  {

        let startWidth = self.width
        var cached = false
        var precalculatedSeams: [[Int]] = []

        // read precalculatedSeams from json, get from Bundle at after first build
        let jsonURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("precalculatedSeams.json")
        let jsonURLBundle = Bundle.main.path(forResource: "precalculatedSeams", ofType: "json")
        var jsonData: Data = Data()
        do {
            jsonData = try Data(contentsOf: jsonURL)
        } catch {
            jsonData = try! Data(contentsOf: URL(fileURLWithPath: jsonURLBundle!))
        }
        let jsonDecoder = JSONDecoder()
        var seamDict = try! jsonDecoder.decode([String: [String:[[Int]]]].self, from: jsonData)
        if seamDict[frameFileName] != nil{
            if seamDict[frameFileName]![dimension] != nil {
                cached = true
                precalculatedSeams = seamDict[frameFileName]![dimension]!
            }
        }
        // if frame seams were not precalculated, initialize that part of the dict
        if(seamDict[frameFileName] == nil) {
            seamDict[frameFileName] = Dictionary<String, [[Int]]>()
        }

        for x in 0..<pixel {

            // check if current seam isn't cached yet
            if(x >= precalculatedSeams.count) {
                cached = false
            }

            // release memory early to avoid memoryoverflow
            autoreleasepool {
                seamAmountCurrent = min(seamAmount,  pixel - (startWidth - self.width))

                // calculate seamMap, energyMap, seam if not cached or if seam length doesn't match the height of the CGImage
                if(!cached || seamDict[frameFileName]![dimension]![x].count == 0 || seamDict[frameFileName]![dimension]![x].count != height) {

                    // calculate energy map
                    let timer1 = ParkBenchTimer()
                    self.energyMap = self.calculateEnergyMap()
                    self.energyMapDataPointer = CFDataGetBytePtr(self.energyMap!.dataProvider!.data)
                    energyMapTime += timer1.stop()

                    // calculate seam map
                    let timer2 = ParkBenchTimer()
                    self.calculateSeamMap(energyMap: self.energyMap, lastSeams: self.seams)
                    seamMapTime += timer2.stop()

                    // calculate seam
                    let timer3 = ParkBenchTimer()
                    self.seams = self.calculateSeams(seamMap: self.seamMap!)
                    var pref: [[Int]] = []
                    if(seamDict[frameFileName]![dimension] != nil) {
                        pref = seamDict[frameFileName]![dimension]!
                    }
                    pref.append(self.seams![0])
                    seamDict[frameFileName]![dimension] = pref
                    seamTime += timer3.stop()
                }
                // if cached, get current seam
                else {
                    self.seams = [precalculatedSeams[x]]
                    print("cache-hit")
                }

                // remove seams
                let timer4 = ParkBenchTimer()
                for seam in self.seams! {
                    self.removeSeam(inputImage: self.frame!,seam: seam)
                }
                seamRemovalTime += timer4.stop()

                // set correct width/height
                if dimension == "height" {
                    self.width = self.width-seamAmountCurrent
                }
                if dimension == "width" {
                    self.width = self.width-seamAmountCurrent
                }
                // set UI in main Thread
                DispatchQueue.main.async {
                    if dimension == "height" {
                        self.labelY.text = "\(self.width)"
                    }
                    if dimension == "width" {
                        self.labelX.text = "\(self.width)"
                    }
                    self.imageView.image =  UIImage(cgImage: self.frame!)
                    self.imageView.setNeedsDisplay()
                }
            }

            // shows seamMap of one iteration, only used for debugging and getting images for presentation
            //showSeamMap(seamMap: seamMap!)
        }
        if(dimension == "width") {
            carvedHeight = pixel - 1
        }
        else {
            carvedHeight = 0
        }

        // encode dict to json and write it back (only written into file of sandboxed device, gets lost after a clean rebuild
        let jsonEncoder = JSONEncoder()
        let encodeSeams = try! jsonEncoder.encode(seamDict)
        let encodedStringSeam = String(data: encodeSeams, encoding: .utf8)!
        let data = Data(encodedStringSeam.utf8)
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("precalculatedSeams.json")
        try! data.write(to: fileURL, options: .atomic)
        print(fileURL)
    }

    func calculateEnergyMap() -> CGImage {
        filter.inputImage = CIImage(cgImage: frame!)
        let outputImage = CIContext().createCGImage(filter.outputImage()!, from: filter.inputImage!.extent)!
        return outputImage
    }

    func calculateSeamMap(energyMap: CGImage!, lastSeams: [[Int]]?){
            var map = [[CGFloat]](repeating: [CGFloat](repeating: 0, count: Int(width)), count: Int(height))
            for y in 0...(height-1) {
                for x in 0...(width-1) {

                    // retrieve value of energyMap for current pixel
                    let energy = CGFloat(energyMapDataPointer![((Int(energyMap.bytesPerRow / 4) * y) + x) * 4]) / 255.0

                    // right half of frame moves to left, so checking for originalSized alphaMap with difference only on right half, original x value on left half
                    // CAUTION: this is frame - corner specific, in general it's probably best to recalculate alphaMap at the start of every carving by also "removing the seam" from the alphaMap
                    var testX = x
                    if(x > width/2) {
                        testX = x + (startWidth - width)
                    }
                    var testY = y
                    if(y > height/2) {
                        testY = testY + carvedHeight
                    }

                    // set seamMap to high value for not getting carved (alphaMap constraint)
                    if(alphaMap![testY][testX] == 255) {
                        map[y][x] = CGFloat.greatestFiniteMagnitude
                    }

                    // workaround to avoid edge-cutting, set left- and rightmost pixelcolumn to high value
                    else if(x == 0 || x == (width-1)) {
                        map[y][x] = CGFloat.greatestFiniteMagnitude
                    }

                    // base case, if y == 0: seamMap == energyMap
                    else if(y == 0) {
                        map[y][x] = energy
                    }

                    // DP for calculating seamMap
                    else {
                        map[y][x] = min(min(map[y-1][x-1], map[y-1][x]),map[y-1][x+1]) + energy
                    }
                }
            }
        seamMap = map
    }

    // visualize given seamMap
    func showSeamMap(seamMap: [[CGFloat]]) {
        var max = 0.0
        for x in 1...width-2 {
            for y in 1...height-2 {
                if(max < seamMap[y][x]) {
                    max = seamMap[y][x]
                }
            }
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel:Int = 4
        let bytesPerRow = 4 * width
        let bitsPerComponent = 8
        let dataSize =  width * bytesPerPixel * height
        var rawData = [UInt8](repeating: 0, count: Int(dataSize))
        let bitmapInfo = frame!.bitmapInfo.rawValue
        let context = CGContext(data: &rawData, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)!

        var byteIndex = 0

        // Iterate through pixels
        while byteIndex < dataSize {

            // Get Column and Row of current pixel
            let column =  ((byteIndex / 4) % (bytesPerRow/4))
            let row = ((byteIndex - (column*4)) / bytesPerRow )

            // edge values are +Inf, visualize them as transparent
            if(width<=column || column == 0 || column == width - 1) {
                rawData[byteIndex + 0] = UInt8(0)
                rawData[byteIndex + 1] = UInt8(0)
                rawData[byteIndex + 2] = UInt8(0)
                rawData[byteIndex + 0] = UInt8(0)
                byteIndex += 4
                continue
            }

            // normalize seam map values to 0...255 and show as grey values
            rawData[byteIndex + 0] = UInt8(Int((seamMap[row][column] / max) * 255))
            rawData[byteIndex + 1] = UInt8(Int((seamMap[row][column] / max) * 255))
            rawData[byteIndex + 2] = UInt8(Int((seamMap[row][column] / max) * 255))
            rawData[byteIndex + 3] = UInt8(255)
            byteIndex += 4
        }
        frame = context.makeImage()!
        DispatchQueue.main.sync {
            imageView.image =  UIImage(cgImage: frame!)
        }
    }


    func calculateSeams(seamMap: [[CGFloat]]) -> [[Int]] {

        // returns arrays of length image.size.height where the value is the index
        // 0 <= x <= image.size.width with x being part of the seam
        var seams = [[Int]](repeating: [Int](repeating: 0, count: height), count: seamAmountCurrent)
        var lastIndicesToIgnore: [Int] = [Int](repeating: 0, count: seamAmountCurrent)
        for i in 0..<seamAmountCurrent {
            var seamIndex = [Int](repeating: 0, count: height)

            // calculate start of seam from bottom
            let y = height-1
            var min = CGFloat.greatestFiniteMagnitude
            var minIndex = -1
            for x in 0...width-1 {
                if(min > seamMap[y][x] && !lastIndicesToIgnore.contains(x)) {
                    min = seamMap[y][x]
                    minIndex = x
                }
            }
            seamIndex[y] = minIndex
            lastIndicesToIgnore[i] = minIndex

            // calculate rest of seam by looking at the top neighbour values
            for y in stride(from: height-2, through: 0, by: -1) {
                let xValueOfSeamPartBelow = seamIndex[y+1]
                var min = CGFloat.greatestFiniteMagnitude
                var minIndex = -1
                for x in xValueOfSeamPartBelow-1...xValueOfSeamPartBelow+1 {

                    // ignore all x values that are OOB
                    if(x <= -1) {
                        continue
                    }
                    if(x >= width) {
                        continue
                    }
                    if(min > seamMap[y][x]) {
                        min = seamMap[y][x]
                        minIndex = x
                    }
                }
                seamIndex[y] = minIndex
            }
            seams[i] = seamIndex
        }
        print(lastIndicesToIgnore)
        return seams
    }

    // crops last column of given CGImage
    func cropLastColumn(image: CGImage) -> CGImage {
        let resultSize = CGSize(width: (Int(width) - 1), height: Int(height))
        let toRect = CGRect(origin: .zero, size: resultSize)
        return image.cropping(to: toRect)!
    }

    func removeSeam(inputImage: CGImage, seam:[Int]) {
            let colorSpace = inputImage.colorSpace!
            let bytesPerRow = inputImage.bytesPerRow
            let bitsPerComponent = inputImage.bitsPerComponent
            let bitmapInfo = inputImage.bitmapInfo.rawValue
            let dataSize = inputImage.bytesPerRow * inputImage.height

            // retrieve input image data and store in rawDataOriginal
            var rawDataOriginal = [UInt8](repeating: 0, count: Int(dataSize))
            let context = CGContext(data: &rawDataOriginal, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)!
            context.draw(inputImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            // initialize rawData array and fill it with new image data without seam
            var rawData = Array<UInt8>(unsafeUninitializedCapacity: (inputImage.bytesPerRow) * height, initializingWith: { (subBuffer: inout UnsafeMutableBufferPointer<UInt8>, subCount: inout Int) in
                subCount = (inputImage.bytesPerRow / 4) * height

                // iterate over rows
                DispatchQueue.concurrentPerform(iterations: (height)) { row in

                    // get column of seam for this specific row
                    let seamColumn = seam[Int(row)]

                    // iterate over columns
                    DispatchQueue.concurrentPerform(iterations: (inputImage.bytesPerRow / 4)) { column in

                        // calculate current index
                        let byteIndex = (inputImage.bytesPerRow * row) + (4*column)
                        if(column >= width-1) {
                            subBuffer[byteIndex + 0] = UInt8(0)
                            subBuffer[byteIndex + 1] = UInt8(0)
                            subBuffer[byteIndex + 2] = UInt8(0)
                            subBuffer[byteIndex + 3] = UInt8(0)
                        }
                        // shift bytes at/right of seam
                        else if(column < width-1 && column >= seamColumn) {
                            subBuffer[byteIndex + 0] = UInt8(rawDataOriginal[byteIndex + 4])
                            subBuffer[byteIndex + 1] = UInt8(rawDataOriginal[byteIndex + 5])
                            subBuffer[byteIndex + 2] = UInt8(rawDataOriginal[byteIndex + 6])
                            subBuffer[byteIndex + 3] = UInt8(rawDataOriginal[byteIndex + 7])
                        }

                        // left of seam => copy values from original buffer
                        else {
                            subBuffer[byteIndex + 0] = UInt8(rawDataOriginal[byteIndex + 0])
                            subBuffer[byteIndex + 1] = UInt8(rawDataOriginal[byteIndex + 1])
                            subBuffer[byteIndex + 2] = UInt8(rawDataOriginal[byteIndex + 2])
                            subBuffer[byteIndex + 3] = UInt8(rawDataOriginal[byteIndex + 3])
                        }
                    }
                }
            })

            // build new context out of given new image data and retrieve output image
            let context2 = CGContext(data: &rawData, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)!
            let resultImage = context2.makeImage()!

            // crop out last column, which got replaced to (0,0,0,0) earlier
            let imageCropped = cropLastColumn(image:resultImage)

            // write back carved frame to global var
            frame = imageCropped
        }
}
