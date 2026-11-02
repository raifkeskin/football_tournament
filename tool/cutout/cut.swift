import Foundation
import Vision
import CoreImage
import AppKit

// Kullanım: cut <girdi.jpg> <çıktı.png>  (scripts/make_cutouts.py çağırır)
// Ön plan maskesi + yüze göre baş-omuz kırpımı, 192x240 saydam PNG; kaynak kırpım genişliği "srcpx=" ile yazılır.
let args = CommandLine.arguments
let url = URL(fileURLWithPath: args[1])
guard let ci = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { exit(1) }
let handler = VNImageRequestHandler(ciImage: ci)
let fg = VNGenerateForegroundInstanceMaskRequest()
let face = VNDetectFaceRectanglesRequest()
try handler.perform([fg, face])
guard let obs = fg.results?.first else { print("NOMASK"); exit(2) }
// En büyük örnek (kişi) seçilir.
let buf = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: false)
var out = CIImage(cvPixelBuffer: buf)
let W = ci.extent.width, H = ci.extent.height
var crop: CGRect
if let f = face.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }) {
  let fb = f.boundingBox
  let fw = fb.width * W, fh = fb.height * H
  let cx = fb.midX * W
  let w = fw * 2.9, h = w * 1.25
  let top = fb.maxY * H + fh * 0.55          // CI'da y yukarı
  crop = CGRect(x: cx - w/2, y: top - h, width: w, height: h)
  print("FACE ratio=\(String(format: "%.2f", fw / W))")
} else {
  crop = ci.extent; print("NOFACE")
}
// Fotoğraf dışına taşan kırpım fotoğrafa sığdırılır; sonuç alt-ortaya oturur.
crop = crop.intersection(ci.extent)
out = out.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
let s = min(192 / crop.width, 240 / crop.height)
out = out.transformed(by: CGAffineTransform(scaleX: s, y: s))
out = out.transformed(by: CGAffineTransform(translationX: (192 - crop.width * s) / 2, y: 0))
print("srcpx=\(Int(crop.width))")
let ctx = CIContext()
let rect = CGRect(x: 0, y: 0, width: 192, height: 240)
let cg = ctx.createCGImage(out, from: rect, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))!
let rep = NSBitmapImageRep(cgImage: cg)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
