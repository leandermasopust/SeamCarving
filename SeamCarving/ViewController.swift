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
// https://gist.github.com/michaeldong/ac607e732728b704a0ddd6606f9dde56 with small changes
extension CGImage {

    subscript (x: Int, y: Int) -> [CGFloat] {

        if x < 0 || x > Int(self.width) || y < 0 || y > Int(self.height) {
            return []
        }

        let provider = self.dataProvider
        let providerData = provider!.data
        let data = CFDataGetBytePtr(providerData)

        let numberOfComponents = 4
        let pixelData = ((Int(self.bytesPerRow / 4) * y) + x) * numberOfComponents

        let r = CGFloat(data![pixelData]) / 255.0
        let g = CGFloat(data![pixelData + 1]) / 255.0
        let b = CGFloat(data![pixelData + 2]) / 255.0
        let a = CGFloat(data![pixelData + 3]) / 255.0

        return [r, g, b, a]
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
        let width = imageView.image?.size.width
        let height = imageView.image?.size.height
        labelX.text = "\(width ?? 0.0)"
        labelY.text = "\(height ?? 0.0)"
    }

    var width = 0
    var height = 0
    var img: CGImage? = nil

    @IBAction func startCarving() {
        let xReductionInput = (inputX.text! as NSString).integerValue

        // checks for faulty input
        if (imageView.image?.cgImage == nil){return}
        if (xReductionInput <= 0) {return}

        // set global variables
        img = imageView.image!.cgImage!
        width = img!.width
        height = img!.height

        let timer = ParkBenchTimer()
        for _ in 1...xReductionInput {
            // calculate energy map
            let timer1 = ParkBenchTimer()
            let energyMap = calculateEnergyMapX(inputIm: img!)
            print("The EnergyMap took \(timer1.stop()) seconds.")
            // TODO: MEMORY LEAK IN HERE UH OH

            // calculate seam map
            let timer2 = ParkBenchTimer()
            let seamMap = calculateSeamMap(energyMap: energyMap)
            print("The SeamMap took \(timer2.stop()) seconds.")

            // calculate seam
            let timer3 = ParkBenchTimer()
            let seam = calculateSeam(seamMap: seamMap)
            print("The Seam took \(timer3.stop()) seconds.")

            // remove seam
            let timer4 = ParkBenchTimer()
            removeSeam(inputImage: img!, seam:seam)
            print("The Removal of Seam took \(timer4.stop()) seconds.")

            // set UI and global variables
            width = width-1
            labelX.text = "\(width)"
            labelY.text = "\(height)"

            //showSeamMap(seamMap: seamMap)
        }
        print("The Carving took \(timer.stop()) seconds.")
        imageView.image =  UIImage(cgImage: img!)

    }
    func calculateEnergyMapX(inputIm: CGImage) -> CGImage {
        let inputImage = CIImage(cgImage: inputIm)
        let context = CIContext(options: nil)
        let filter = EnergyMapFilter()
        filter.inputImage = inputImage
        let outputImage = context.createCGImage(filter.outputImage()!, from: inputImage.extent)!
        UIGraphicsEndImageContext()
        return outputImage
    }

    func calculateSeamMap(energyMap: CGImage!) -> [[CGFloat]]{
        var map = [[CGFloat]](repeating: [CGFloat](repeating: 0, count: Int(width)), count: Int(height))
        for y in 0...(height-1) {
            for x in 0...(width-1) {
                let red = energyMap[x,y][0]

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
        return map
    }

    func showSeamMap(seamMap: [[CGFloat]]) {
        let rows = seamMap.count
        let columns = seamMap[0].count
        var max = 0.0
        for x in 1...columns-2 {
            for y in 1...rows-2 {
                if(max < seamMap[y][x]) {
                    max = seamMap[y][x]
                }
            }
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel:Int = 4
        let bytesPerRow = 4 * columns
        let bitsPerComponent = 8
        let dataSize =  columns * bytesPerPixel * rows
        var rawData = [UInt8](repeating: 0, count: Int(dataSize))
        let bitmapInfo = img!.bitmapInfo.rawValue
        let context = CGContext(data: &rawData, width: columns, height: rows, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)!

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
        let rows = seamMap.count
        let columns = seamMap[0].count
        var seamIndex = [Int](repeating: 0, count: rows)

        // calculate start of seam from bottom
        let y = rows-1
        var min = CGFloat.greatestFiniteMagnitude
        var minIndex = -1
        for x in 0...columns-1 {
            if(min > seamMap[y][x]) {
                min = seamMap[y][x]
                minIndex = x
            }
        }
        seamIndex[y] = minIndex
        print("Carving at: ")
        print(minIndex)

        // calculate rest of seam by looking at the top neighbour values
        for y in stride(from: rows-2, through: 0, by: -1) {
            let xValueOfSeamPartBelow = seamIndex[y+1]
            var min = CGFloat.greatestFiniteMagnitude
            var minIndex = -1
            for x in xValueOfSeamPartBelow-1...xValueOfSeamPartBelow+1 {
                if(x <= -1) {
                    continue
                }
                if(x >= columns) {
                    continue
                }
                if(min > seamMap[y][x]) {
                    min = seamMap[y][x]
                    minIndex = x
                }
            }
            //print("Cutting at: ")
            //print(minIndex)
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
        let dataSize = inputImage.bytesPerRow * inputImage.height
        var rawData = [UInt8](repeating: 0, count: Int(dataSize))
        let bitmapInfo = inputImage.bitmapInfo.rawValue
        let context = CGContext(data: &rawData, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)!
        context.draw(inputImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var byteIndex = 0
        // iterate over all bytes
        while byteIndex < dataSize {

            // get column and row of current pixel
            let column =  ((byteIndex / 4) % (bytesPerRow/4))
            let row = ((byteIndex - (column*4)) / bytesPerRow)

            // get column of seam for this specific row
            let seamColumn = seam[Int(row)]
            if(column >= width-1) {
                rawData[byteIndex + 0] = UInt8(0)
                rawData[byteIndex + 1] = UInt8(0)
                rawData[byteIndex + 2] = UInt8(0)
                rawData[byteIndex + 3] = UInt8(0)
            }/*
            else if(column == seamColumn) {
                rawData[byteIndex + 0] = UInt8(255)
                rawData[byteIndex + 1] = UInt8(0)
                rawData[byteIndex + 2] = UInt8(0)
                rawData[byteIndex + 3] = UInt8(255)
            }*/
            // shift bytes at/right of seam
            else if(column < width-1 && column >= seamColumn) {
                rawData[byteIndex + 0] = UInt8(rawData[byteIndex + 4])
                rawData[byteIndex + 1] = UInt8(rawData[byteIndex + 5])
                rawData[byteIndex + 2] = UInt8(rawData[byteIndex + 6])
                rawData[byteIndex + 3] = UInt8(rawData[byteIndex + 7])
            }
            byteIndex += 4
        }
        // Retrieve image from memory context.
        let resultImage = context.makeImage()!
        UIGraphicsEndImageContext()
        let imageCropped = cropLastColumn(image:resultImage)
        img = imageCropped
    }
}


