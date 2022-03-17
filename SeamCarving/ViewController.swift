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
import PhotosUI

//https://stackoverflow.com/questions/24755558/measure-elapsed-time-in-swift
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

class EnergyMapFilter: CIFilter {

    private let kernel: CIKernel
    var inputImage: CIImage?
    override init() {
        let url = Bundle.main.url(forResource: "default", withExtension: "metallib")!
        let data = try! Data(contentsOf: url)
        kernel = try! CIKernel(functionName: "energyMap", fromMetalLibraryData: data)
        super.init()
    }
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    func outputImage() -> CIImage? {
        let sampler = CISampler.init(image:inputImage!)
        guard let inputImage = inputImage else {return nil}
        return kernel.apply(extent: inputImage.extent, roiCallback: {(index,rect)-> CGRect in return rect}, arguments: [sampler, inputImage.extent.width, inputImage.extent.height])
    }
}

class ViewController: UIViewController, UINavigationControllerDelegate, UIImagePickerControllerDelegate {

    @IBOutlet var  imageView: UIImageView!
    @IBOutlet var selectButton: UIButton!
    @IBOutlet var carveButton: UIButton!
    @IBOutlet var frameButton: UIButton!
    @IBOutlet var labelX: UILabel!
    @IBOutlet var labelY: UILabel!
    @IBOutlet var inputX: UITextField!
    @IBOutlet var inputY: UITextField!
    var imagePicker = UIImagePickerController()
    var width = 0
    var height = 0
    var img: CGImage? = nil
    var imgInFrame: CGImage? = nil
    var seam: [Int]? = nil
    var seamMap: [[CGFloat]]? = nil
    var energyMap: CGImage? = nil
    var prov: UnsafePointer<UInt8>? = nil
    var alphaMap: [[UInt8]]? = nil
    var filter = EnergyMapFilter()
    var energyMapTime = 0.0
    var seamMapTime = 0.0
    var seamTime = 0.0
    var seamRemovalTime = 0.0

    override func viewDidLoad() {
        super.viewDidLoad()
        self.hideKeyboardWhenTappedAround()
    }


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

        // set global variables and updated imageView
        imageView.image = image
        seamMap = nil
        seam = nil
        energyMap = nil
        prov = nil

        // update extent textfields
        labelX.text = "\(Int(image.cgImage!.width))"
        labelY.text = "\(Int(image.cgImage!.height))"
    }
    @IBAction func selectFrame() {
        img = imageView.image!.cgImage!
        let f1 = UIImage.init(named:"frame-1")
        let f1JPG = UIImage.init(named:"frame-1.bmp")
        /*let f2 = UIImage.init(named:"frame-2")
        let f3 = UIImage.init(named:"frame-4")
        let f4 = UIImage.init(named:"frame-5")
        let f5 = UIImage.init(named:"frame-6")
        let f6 = UIImage.init(named:"frame-7")
        let f7 = UIImage.init(named:"frame-8")*/

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

            alphaMap![row][column] = rawData[byteIndex + 3]
            byteIndex += 4
        }
        imageView.image = f1JPG
        imgInFrame = img!
        img = f1JPG!.cgImage!
        width = img!.width
        height = img!.height
        labelX.text = "\(Int(imageView.image!.size.width))"
        labelY.text = "\(Int(imageView.image!.size.height))"
        seamMap = nil
        seam = nil
        energyMap = nil
        prov = nil


        print(f1JPG!.cgImage!.width == f1!.cgImage!.width)
        print(f1JPG!.cgImage!.height == f1!.cgImage!.height)
        //imageView.image = UIImage(cgImage:f1!.cgImage!)


    }

    func calculateDifference() -> [Int] {
        var counterHeight = 0
        var counterWidth = 0
        for i in 0..<height {
            if(alphaMap![i][0] == 0) {
                counterHeight += 1
            }
        }
        for i in 0..<width {
            if(alphaMap![0][i] == 0) {
                counterWidth += 1
            }
        }
        counterHeight = counterHeight - imgInFrame!.height
        counterWidth = counterWidth - imgInFrame!.width
        print([counterWidth, counterHeight])
        return [counterWidth, counterHeight]
    }

    func placeImageInFrame() {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel:Int = 4
        let bytesPerRow = 4 * width
        let bitsPerComponent = 8
        let dataSize =  width * bytesPerPixel * height
        var rawData = [UInt8](repeating: 0, count: Int(dataSize))
        let bitmapInfo = img!.bitmapInfo.rawValue
        let context = CGContext(data: &rawData, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)!

        let bytesPerRowImg = 4 * imgInFrame!.width
        var rawDataImg = [UInt8](repeating: 0, count: Int(dataSize))
        let bitmapInfoImg = imgInFrame!.bitmapInfo.rawValue
        let contextImg = CGContext(data: &rawDataImg, width: imgInFrame!.width, height: imgInFrame!.height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRowImg, space: colorSpace, bitmapInfo: bitmapInfoImg)!

        context.draw(img!, in: CGRect(x: 0, y: 0, width: width, height: height))
        contextImg.draw(imgInFrame!, in: CGRect(x: 0, y: 0, width: imgInFrame!.width, height: imgInFrame!.height))

        var byteIndex = 0
        var byteCounterImg = 0
        // Iterate through pixels
        while byteIndex < dataSize {

            let r = rawData[byteIndex + 0]
            let g = rawData[byteIndex + 1]
            let b = rawData[byteIndex + 2]

            if(r > 250 && g < 50 && b > 250) {
                var originalImageColumn = ((byteCounterImg / 4) % (bytesPerRowImg/4))
                while(originalImageColumn > imgInFrame!.width) {
                    byteCounterImg += 4
                    originalImageColumn = ((byteCounterImg / 4) % (bytesPerRowImg/4))
                }
                rawData[byteIndex + 0] = rawDataImg[byteCounterImg + 1]
                rawData[byteIndex + 1] = rawDataImg[byteCounterImg + 2]
                rawData[byteIndex + 2] = rawDataImg[byteCounterImg + 3]
                byteCounterImg += 4
            }
            byteIndex += 4
        }
        img = context.makeImage()!

        // set UI in main Thread
        DispatchQueue.main.async {
            self.imageView.image =  UIImage(cgImage: self.img!)
            self.imageView.setNeedsDisplay()
        }

    }

    @IBAction func startCarving() {

        // get number of pixels to carve for each dimension
        let xReductionInput = calculateDifference()[0]
        let yReductionInput = calculateDifference()[1]

        // checks for faulty input
        if (imageView.image?.cgImage == nil){return}
        if (xReductionInput < 0) {return}
        if (yReductionInput < 0) {return}
        if (Int(imageView.image!.size.width) - xReductionInput <= 1) {return}
        if (Int(imageView.image!.size.height) - yReductionInput <= 1) {return}


        // return if there is nothing to carve
        if (xReductionInput + yReductionInput <= 0) {return}

        // set global variables
        img = imageView.image!.cgImage!
        width = img!.width
        height = img!.height

        DispatchQueue(label: "l").async {

            // disable carve button and select button
            DispatchQueue.main.sync {
                self.carveButton.isEnabled = false
                self.selectButton.isEnabled = false
                self.frameButton.isEnabled = false
            }

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
                self.carveButton.isEnabled = true
                self.selectButton.isEnabled = true
                self.frameButton.isEnabled = true
            }
        }
    }
    func carveWidth(xReductionInput: Int) {
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
            let ci = CIImage(cgImage: img!).oriented(.left)
            img = CIContext().createCGImage(ci, from: ci.extent)

            // rotate UIImageView 90° clockwise
            imageView.transform = imageView.transform.rotated(by: .pi / 2)

            // set imageView frame so the imageView scaling doesn't change
            imageView.frame = CGRect(x: x, y: y,
                                     width: imageView.frame.height, height: imageView.frame.width)

            // finally set the rotated image into the rotated imageView
            imageView.image = UIImage(cgImage:img!)

            // resetting global variables
            seamMap = nil
            seam = nil
            energyMap = nil
            prov = nil
            width = img!.width
            height = img!.height
        }

        carve(pixel: yReductionInput, dimension: "height")

        DispatchQueue.main.sync {

            // get original x,y origin points from imageView
            let x = imageView.frame.minX
            let y = imageView.frame.minY

            // rotate img 90° clockwise
            let ci = CIImage(cgImage: img!).oriented(.right)
            img = CIContext().createCGImage(ci, from: ci.extent)

            // rotate UIImageView 270° clockwise
            imageView.transform = imageView.transform.rotated(by: .pi * 1.5)

            // set imageView frame so the imageView scaling doesn't change
            imageView.frame = CGRect(x: x, y: y,
                                     width: imageView.frame.height, height: imageView.frame.width)

            // finally set the rotated image into the rotated imageView
            self.imageView.image =  UIImage(cgImage: self.img!)

            // resetting global variables
            seamMap = nil
            seam = nil
            energyMap = nil
            prov = nil
            width = img!.width
            height = img!.height
        }

    }

    func carve(pixel: Int, dimension: String)  {

        for _ in 0..<pixel {

            // release memory early
            autoreleasepool {

                // calculate energy map
                let timer1 = ParkBenchTimer()
                self.energyMap = self.calculateEnergyMap()
                self.prov = CFDataGetBytePtr(self.energyMap!.dataProvider!.data)
                energyMapTime += timer1.stop()

                // calculate seam map
                let timer2 = ParkBenchTimer()
                self.calculateSeamMap(energyMap: self.energyMap, lastSeam: self.seam, lastSeamMap: &self.seamMap)
                seamMapTime += timer2.stop()

                // calculate seam
                let timer3 = ParkBenchTimer()
                self.seam = self.calculateSeam(seamMap: self.seamMap!)
                seamTime += timer3.stop()

                // remove seam
                let timer4 = ParkBenchTimer()
                self.removeSeam(inputImage: self.img!, seam: self.seam!)
                seamRemovalTime += timer4.stop()

                // set correct width/height
                if dimension == "height" {
                    self.width = self.width-1
                }
                if dimension == "width" {
                    self.width = self.width-1
                }

                // set UI in main Thread
                DispatchQueue.main.async {
                    if dimension == "height" {
                        self.labelY.text = "\(self.width)"
                    }
                    if dimension == "width" {
                        self.labelX.text = "\(self.width)"
                    }
                    self.imageView.image =  UIImage(cgImage: self.img!)
                    self.imageView.setNeedsDisplay()
                }
            }
            //showSeamMap(seamMap: seamMap!)
        }
    }

    func calculateEnergyMap() -> CGImage {
        filter.inputImage = CIImage(cgImage: img!)
        let outputImage = CIContext().createCGImage(filter.outputImage()!, from: filter.inputImage!.extent)!
        return outputImage
    }

    func calculateSeamMap(energyMap: CGImage!, lastSeam: [Int]?, lastSeamMap: inout [[CGFloat]]?){
        if(lastSeamMap == nil || lastSeam == nil) {
            var map = [[CGFloat]](repeating: [CGFloat](repeating: 0, count: Int(width)), count: Int(height))
            for y in 0...(height-1) {
                for x in 0...(width-1) {
                    let red = CGFloat(prov![((Int(energyMap.bytesPerRow / 4) * y) + x) * 4]) / 255.0
                    if(x == 0 || x == (width-1)) {
                        // workaround to avoid edge-cutting
                        map[y][x] = CGFloat.greatestFiniteMagnitude
                    }
                    else if(y == 0) {
                        map[y][x] = red
                    }
                    else {
                        map[y][x] = min(min(map[y-1][x-1], map[y-1][x]),map[y-1][x+1]) + red
                    }
                }
            }
            lastSeamMap = map
        }
        else {
            for y in 0...(height-1) {
                for x in (seam![y] - y - 1)...(seam![y] + y) {
                    if(x > (width-1) || x  < 0) {
                        continue
                    }
                    let red = CGFloat(prov![((Int(energyMap.bytesPerRow / 4) * y) + x) * 4]) / 255.0
                    if(x == 0 || x == (width-1)) {
                        // workaround to avoid edge-cutting
                        lastSeamMap![y][x] = CGFloat.greatestFiniteMagnitude
                    }
                    else if(y == 0) {
                        lastSeamMap![y][x] = red
                    }
                    else {
                        lastSeamMap![y][x] = min(min(lastSeamMap![y-1][x-1], lastSeamMap![y-1][x]), lastSeamMap![y-1][x+1]) + red
                    }
                }
            }
        }
    }

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
        let bitmapInfo = img!.bitmapInfo.rawValue
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
        img = context.makeImage()!
        DispatchQueue.main.sync {
            imageView.image =  UIImage(cgImage: img!)
        }
    }


    func calculateSeam(seamMap: [[CGFloat]]) -> [Int] {
        // returns array of length image.size.height where the value is the index
        // 0 <= x <= image.size.width with x being part of the seam
        var seamIndex = [Int](repeating: 0, count: height)

        // calculate start of seam from bottom
        let y = height-1
        var min = CGFloat.greatestFiniteMagnitude
        var minIndex = -1
        for x in 0...width-1 {
            if(min > seamMap[y][x]) {
                min = seamMap[y][x]
                minIndex = x
            }
        }
        seamIndex[y] = minIndex
        //print("Carving at: ")
        //print(minIndex)

        // calculate rest of seam by looking at the top neighbour values
        for y in stride(from: height-2, through: 0, by: -1) {
            let xValueOfSeamPartBelow = seamIndex[y+1]
            var min = CGFloat.greatestFiniteMagnitude
            var minIndex = -1
            for x in xValueOfSeamPartBelow-1...xValueOfSeamPartBelow+1 {
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
        return seamIndex
    }

    func cropLastColumn(image: CGImage) -> CGImage {
        let resultSize = CGSize(width: (Int(width) - 1), height: Int(height))
        let toRect = CGRect(origin: .zero, size: resultSize)
        return  image.cropping(to: toRect)!
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
                    else if(column == seamColumn) {

                        subBuffer[byteIndex + 3] = UInt8(255)
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
        let context2 = CGContext(data: &rawData, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)!
        // Retrieve image from memory context.
        let resultImage = context2.makeImage()!
        let imageCropped = cropLastColumn(image:resultImage)
        img = imageCropped
    }
}


