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
    @IBOutlet var chooseButton: UIButton!
    @IBOutlet var labelX: UILabel!
    @IBOutlet var labelY: UILabel!
    @IBOutlet var inputX: UITextField!
    @IBOutlet var inputY: UITextField!
    var imagePicker = UIImagePickerController()
    var width = 0
    var height = 0
    var img: CGImage? = nil
    var seam: [Int]? = nil
    var seamMap: [[CGFloat]]? = nil
    var energyMap: CGImage? = nil
    var prov: UnsafePointer<UInt8>? = nil
    var filter = EnergyMapFilter()

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
        imageView.image = image
        seamMap = nil
        seam = nil
        energyMap = nil
        prov = nil
        let width = imageView.image?.size.width
        let height = imageView.image?.size.height
        labelX.text = "\(width ?? 0.0)"
        labelY.text = "\(height ?? 0.0)"
    }

    @IBAction func startCarving() {
        let xReductionInput = (inputX.text! as NSString).integerValue

        // checks for faulty input
        if (imageView.image?.cgImage == nil){return}
        if (xReductionInput <= 0) {return}

        // set global variables
        img = imageView.image!.cgImage!
        width = img!.width
        height = img!.height

        var energyMapTime = 0.0
        var seamMapTime = 0.0
        var seamTime = 0.0
        var seamRemovalTime = 0.0

        DispatchQueue(label: "l").async {
            let timer = ParkBenchTimer()
            for _ in 1...xReductionInput {
                // release memory early
                autoreleasepool {
                    // calculate energy map
                    let timer1 = ParkBenchTimer()
                    self.energyMap = self.calculateEnergyMapX()
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

                    // set correct width
                    self.width = self.width-1

                    // set UI in main Thread
                    DispatchQueue.main.async {
                        self.labelX.text = "\(self.width)"
                        self.imageView.image =  UIImage(cgImage: self.img!)
                        self.imageView.setNeedsDisplay()
                    }
                }
                //showSeamMap(seamMap: seamMap)
            }

            // dump time outputs
            print("The EnergyMap took \(energyMapTime) seconds.")
            print("The SeamMap took \(seamMapTime) seconds.")
            print("The Seam took \(seamTime) seconds.")
            print("The Removal of Seam took \(seamRemovalTime) seconds.")
            print("The Carving took \(timer.stop()) seconds.")
        }

    }
    func calculateEnergyMapX() -> CGImage {
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
        imageView.image =  UIImage(cgImage: context.makeImage()!)
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
            DispatchQueue.concurrentPerform(iterations: (height)) { row in

                // get column of seam for this specific row
                let seamColumn = seam[Int(row)]

                // iterate over columns
                for column in 0..<(inputImage.bytesPerRow / 4) {

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
        let context2 = CGContext(data: &rawData, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)!
        // Retrieve image from memory context.
        let resultImage = context2.makeImage()!
        UIGraphicsEndImageContext()
        let imageCropped = cropLastColumn(image:resultImage)
        img = imageCropped
    }
}


