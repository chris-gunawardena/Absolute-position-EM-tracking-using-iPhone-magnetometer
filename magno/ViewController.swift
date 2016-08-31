//
//  ViewController.swift
//  magno
//
//  Created by Chris Gunawardena on 21/11/2015.
//  Copyright © 2015 Chris Gunawardena. All rights reserved.
//
import UIKit
import CoreMotion
import CoreLocation
import Darwin
import SceneKit
import Charts

protocol DoubleConvertible {
    init(_ double: Double)
    var double: Double { get }
}
extension Double : DoubleConvertible { var double: Double { return self         } }
extension Float  : DoubleConvertible { var double: Double { return Double(self) } }
extension CGFloat: DoubleConvertible { var double: Double { return Double(self) } }
extension Array where Element: DoubleConvertible {
    var total: Element {
        return  Element(reduce(0){ $0 + $1.double })
    }
    var average: Element {
        return  isEmpty ? Element(0) : Element(total.double / Double(count))
    }
}
extension Array where Element: IntegerType {
    /// Returns the sum of all elements in the array
    var total: Element {
        return reduce(0, combine: +)
    }
    /// Returns the average of all elements in the array
    var average: Double {
        return isEmpty ? 0 : Double(total.hashValue) / Double(count)
    }
}
extension CollectionType {
    func last(count:Int) -> [Self.Generator.Element] {
        let selfCount = self.count as! Int
        if selfCount <= count - 1 {
            return Array(self)
        } else {
            return Array(self.reverse()[0...count - 1].reverse())
        }
    }
}

class ViewController: UIViewController, CLLocationManagerDelegate, SCNSceneRendererDelegate, ChartViewDelegate {
    @IBOutlet weak var magno_label: UILabel!
    @IBOutlet weak var combine_scene_view: SCNView!
    @IBOutlet weak var lineChartView: LineChartView!
    
    var timer = NSTimer()
    var magnetometerUpdateInterval =  0.01
    var num_transmitters = 3
    var refresh_rate = 1 //per second
    var normalise_window = 8
    var magno_readings_x: [Double] = []
    var magno_readings_y: [Double] = []
    var magno_readings_z: [Double] = []
    var magno_readings_n: [Double] = []
    var motionManager : CMMotionManager?
    var locationManager : CLLocationManager?
    var box: SCNNode!
    var test_data = [[Double]]()
    var start_time = NSDate().timeIntervalSinceReferenceDate * 1000
    var chart_queue: dispatch_queue_t?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        startMotionManager()
        //startLocationManager()
        
        test_data = get_test_data()
        
        initChart()
        self.box = create_scene(combine_scene_view)
        
        // start timer
        timer = NSTimer.scheduledTimerWithTimeInterval(magnetometerUpdateInterval, target:self, selector: #selector(ViewController.ticker), userInfo: nil, repeats: true)
    }
    
    var counter = 0
    var i = 0
    func ticker() {
        // collect raw data
        let field = getMagnetometerData()
        magno_readings_x.append(field.x)
        magno_readings_y.append(field.y)
        magno_readings_z.append(field.z)
        
        //normalise using interquartile mean
        if magno_readings_x.count >= normalise_window {
            let nx = magno_readings_x.last! - interquartile_mean(magno_readings_x)
            let ny = magno_readings_y.last! - interquartile_mean(magno_readings_y)
            let nz = magno_readings_z.last! - interquartile_mean(magno_readings_z)
            let xyz_magnitude = sqrt(nx*nx + ny*ny + nz*nz)
//            if magno_readings_n.count >= normalise_window {
//                magno_readings_n.append(xyz_magnitude - interquartile_mean(magno_readings_n.last(normalise_window)))
//            } else {
                magno_readings_n.append(xyz_magnitude)
//            }
            magno_readings_x.removeFirst()
            magno_readings_y.removeFirst()
            magno_readings_z.removeFirst()
        }
        
        // peak detection
        let sliding_window_size = Int(1 / magnetometerUpdateInterval) / refresh_rate
        if magno_readings_n.count > sliding_window_size + 2 {
            
            let peaks = sync_phase(find_peaks(magno_readings_n))
            
            let r1 = intensity_to_distance(peaks[1])
            let r2 = intensity_to_distance(peaks[2])
            let r3 = intensity_to_distance(peaks[3])
            
            let cordinates = trilaterate(r1, r2: r2, r3: r3)
            let scale = Float(3.0)
            //plot3d(self.box, x: r1, y: r2, z: r3)
            plot3d(self.box, x: cordinates.x * scale, y: cordinates.y * scale, z: cordinates.z * scale)
            chart(self.i, p1: peaks[0], p2: peaks[1], p3: peaks[2], p4: peaks[3], p5: self.magno_readings_n.last!)
            
            // time
//            let now = NSDate().timeIntervalSinceReferenceDate * 1000
//            let time_diff = Int(now - self.start_time)
//            self.start_time = now
            
            self.magno_label.text = NSString(format: "%.1f %.1f %.1f\n%.1f %.1f %.1f",
                                             peaks[1], peaks[2], peaks[3], r1, r2, r3) as String
            magno_readings_n.removeFirst()
            i = i + 1
        }
        // used for test data
        counter = counter + 1
        if counter >= test_data.count {
            counter = 0
        }
    }

    func intensity_to_distance(intensity: Double) -> Float {
        //http://www.instructables.com/id/Evaluate-magnetic-field-variation-with-distance/?ALLSTEPS
        let distance = pow(1 / intensity, 1 / 3.0)
        return Float(distance)
    }
    
    func initChart() {
        self.lineChartView.delegate = self
        let set_a: LineChartDataSet = LineChartDataSet(yVals: [ChartDataEntry](), label: "a")
        set_a.drawCirclesEnabled = false
        set_a.setColor(UIColor.blueColor())
        let set_b: LineChartDataSet = LineChartDataSet(yVals: [ChartDataEntry](), label: "b")
        set_b.drawCirclesEnabled = false
        set_b.setColor(UIColor.greenColor())
        let set_c: LineChartDataSet = LineChartDataSet(yVals: [ChartDataEntry](), label: "c")
        set_c.drawCirclesEnabled = false
        set_c.setColor(UIColor.yellowColor())
        let set_d: LineChartDataSet = LineChartDataSet(yVals: [ChartDataEntry](), label: "d")
        set_d.drawCirclesEnabled = false
        set_d.setColor(UIColor.purpleColor())
        let set_e: LineChartDataSet = LineChartDataSet(yVals: [ChartDataEntry](), label: "e")
        set_e.drawCirclesEnabled = false
        set_e.setColor(UIColor.redColor())
        self.lineChartView.data = LineChartData(xVals: [String](), dataSets: [set_a, set_b, set_c, set_d, set_e])
        //
        //chart_queue = dispatch_queue_create("com.chart.queue", DISPATCH_QUEUE_SERIAL);
    }
    
    func startMotionManager() {
        motionManager = CMMotionManager()
        motionManager?.showsDeviceMovementDisplay = true
        motionManager?.magnetometerUpdateInterval = magnetometerUpdateInterval
        motionManager?.startMagnetometerUpdates()
    }
    
    func startLocationManager() {
        locationManager = CLLocationManager()
        locationManager?.requestWhenInUseAuthorization()
        locationManager?.startUpdatingHeading()
    }
    
    func create_scene(view: SCNView) -> SCNNode {
        let scene = SCNScene()
        view.scene = scene
        
        let camera = SCNCamera()
        //camera.usesOrthographicProjection = true
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(x: 1, y: 1, z: 10)
        cameraNode.rotation = SCNVector4(1,0,1, deg2rad(30))
        cameraNode.rotation = SCNVector4(0,0,1, deg2rad(-30))
        scene.rootNode.addChildNode(cameraNode)
        
        scene.rootNode.addChildNode(make_light(30, y: 0, z: 0))
        scene.rootNode.addChildNode(make_light(0, y: 30, z: 0))
        scene.rootNode.addChildNode(make_light(0, y: 0, z: 30))

        // axis
        scene.rootNode.addChildNode(make_box(UIColor.redColor(), width: 30.0, height: 0.1, length: 0.1))
        scene.rootNode.addChildNode(make_box(UIColor.greenColor(), width: 0.1, height: 30.0, length: 0.1))
        scene.rootNode.addChildNode(make_box(UIColor.blueColor(), width: 0.1, height: 0.1, length: 30.0))
        
        let marker = make_box(UIColor.redColor(), width: 0.5, height: 0.5, length: 0.5)
        scene.rootNode.addChildNode(marker)
        
        view.delegate = self
        view.playing = true
        
        return marker
    }
    
    func make_box(color: UIColor, width: CGFloat, height: CGFloat, length: CGFloat) -> SCNNode{
        let box_geometry = SCNBox(width: width, height: height, length: length, chamferRadius: 0)
        box_geometry.firstMaterial?.diffuse.contents =  color
        return SCNNode(geometry: box_geometry)
    }

    func make_light(x: Float, y: Float, z: Float) -> SCNNode{
        let light = SCNLight()
        light.type = SCNLightTypeOmni
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.position = SCNVector3(x: x, y: y, z: z)
        return lightNode
    }
    
    func plot3d(marker:SCNNode, x: Float, y: Float, z: Float) {
        marker.position.x = x
        marker.position.y = y
        marker.position.z = z
    }
    
    func trilaterate(r1: Float, r2: Float, r3: Float) -> (x: Float, y: Float, z: Float) {
        // https://en.wikipedia.org/wiki/Trilateration
        let d = Float(1) // has to be smaller then r1 + r2
        let i = d / 2.0
        let j = sqrt(3) * d / 2
        
        let x = (r1*r1 - r2*r2 + d*d) / (2 * d)
        let y = ((r1*r1 - r3*r3 + i*i + j*j) / (2*j)) - i*x/j
        //let z2 = (r1*r1) - (x*x) - (y*y)
        let z = Float(0.0)//z2 > 0  ? sqrt(z2) : sqrt(z2 * -1)
        
        return (x: x, y: y, z: z)
    }
    
    func get_test_data() -> [[Double]] {
        return [[56.58, 231.90, -749.38], [56.23, 231.55, -749.72], [56.58, 230.85, -749.38], [57.10, 233.12, -749.89], [56.23, 232.59, -749.38], [56.40, 233.12, -749.22], [55.35, 232.77, -749.22], [56.58, 231.90, -750.06], [54.83, 231.90, -749.72], [54.83, 231.90, -749.72], [54.66, 233.12, -749.55], [57.10, 233.47, -749.89], [55.70, 231.72, -750.56], [55.70, 232.07, -749.55], [55.53, 232.94, -749.05], [55.01, 233.12, -749.55], [55.35, 232.42, -749.55], [55.88, 232.59, -750.39], [55.53, 232.24, -749.38], [55.53, 232.94, -750.39], [55.53, 233.29, -749.38], [53.08, 232.94, -749.38], [56.23, 231.55, -750.06], [55.18, 232.59, -750.73], [55.70, 232.77, -750.90], [56.58, 232.24, -748.04], [56.93, 232.94, -750.39], [54.48, 232.59, -750.39], [48.72, 232.07, -748.54], [49.42, 230.67, -748.21], [50.99, 233.64, -746.36], [57.97, 232.24, -749.38], [55.88, 231.55, -749.72], [56.58, 231.90, -749.38], [56.93, 232.59, -750.06], [55.35, 232.42, -748.88], [55.53, 231.55, -749.38], [56.58, 232.59, -749.38], [56.05, 232.77, -749.22], [55.35, 233.12, -749.22], [56.93, 233.29, -748.71], [57.62, 231.20, -749.72], [56.75, 233.12, -750.23], [56.23, 231.55, -749.38], [56.05, 233.47, -749.89], [55.70, 232.07, -750.90], [58.32, 232.94, -750.06], [55.01, 231.37, -749.22], [56.05, 233.12, -748.88], [56.23, 232.59, -750.39], [57.28, 233.99, -750.39], [72.99, 227.01, -750.73], [89.93, 210.42, -735.76], [90.63, 211.12, -736.44], [74.04, 213.73, -732.23], [55.18, 233.29, -749.38], [55.53, 232.94, -749.72], [55.53, 232.94, -749.72], [57.28, 233.29, -749.72], [57.97, 234.34, -749.72], [56.05, 232.07, -749.55], [55.53, 231.90, -748.71], [56.23, 232.94, -750.39], [56.23, 232.94, -750.39], [57.10, 231.02, -749.22], [57.10, 232.07, -749.89], [56.23, 232.24, -748.71], [56.58, 232.59, -749.38], [55.18, 231.55, -749.72], [57.28, 231.90, -750.06], [55.53, 233.64, -748.71], [56.23, 233.64, -750.39], [56.40, 232.07, -750.23], [56.93, 232.94, -749.72], [57.62, 234.69, -749.72], [57.45, 232.42, -749.22], [56.23, 232.24, -750.06], [70.55, 236.09, -744.68], [69.85, 238.18, -742.99], [69.50, 236.44, -744.34], [58.50, 232.42, -749.55], [57.45, 234.51, -749.22], [57.45, 234.51, -749.22], [55.70, 232.07, -749.89], [56.58, 232.24, -750.73], [56.93, 232.94, -749.38], [55.88, 231.90, -749.72], [57.45, 233.12, -750.23], [56.23, 232.94, -749.72], [58.32, 232.59, -750.39], [57.10, 231.72, -749.22], [57.28, 232.94, -749.05], [57.80, 231.72, -749.22], [56.05, 233.82, -750.56], [57.10, 232.77, -749.55], [56.40, 232.77, -750.56], [57.62, 232.59, -749.38], [58.67, 232.59, -749.72], [58.85, 232.77, -750.23], [56.58, 232.24, -749.05], [56.75, 232.77, -750.90], [58.15, 233.12, -750.56], [58.15, 233.12, -750.56], [56.23, 233.99, -748.71], [57.62, 232.59, -749.72], [58.32, 232.94, -749.72], [57.28, 233.29, -749.38], [58.32, 233.29, -750.06], [57.62, 233.64, -749.05], [57.62, 233.64, -749.05], [57.80, 232.42, -749.55], [58.85, 231.72, -749.89], [57.45, 233.12, -749.55], [57.80, 233.82, -749.89], [56.93, 233.64, -749.72], [58.85, 232.42, -749.89], [57.97, 232.24, -750.06], [57.28, 233.29, -750.73], [57.45, 232.77, -749.55], [58.67, 233.64, -749.05], [58.85, 232.42, -750.56], [57.28, 232.59, -751.07], [58.67, 233.99, -749.72], [59.20, 232.77, -750.23], [58.15, 231.72, -749.89], [60.07, 232.59, -749.38], [58.32, 233.29, -749.05], [52.39, 233.64, -749.05], [47.32, 233.82, -745.85], [46.80, 233.99, -745.35], [48.37, 233.82, -746.19], [57.97, 232.94, -751.07], [58.67, 231.90, -749.05], [59.20, 233.12, -750.23], [59.20, 233.12, -750.23], [60.24, 234.51, -750.90], [58.50, 232.07, -748.88], [59.20, 233.12, -750.56], [58.67, 232.59, -749.72], [59.20, 233.82, -748.54], [58.50, 231.72, -749.89], [59.02, 232.24, -749.72], [57.80, 233.12, -751.23], [57.62, 232.59, -749.38], [59.02, 231.90, -749.38], [59.02, 231.90, -749.38], [58.85, 233.12, -749.89], [58.50, 232.42, -750.23], [60.07, 232.59, -750.73], [58.67, 232.24, -749.38], [60.07, 232.24, -750.39], [59.89, 232.77, -750.23], [92.72, 247.79, -766.37], [92.72, 247.79, -766.37], [93.77, 247.79, -766.71], [92.72, 247.44, -766.71], [59.20, 232.07, -749.22], [60.24, 232.42, -750.23], [59.20, 232.77, -749.89], [59.02, 232.59, -750.73], [58.15, 233.82, -750.23], [58.67, 232.94, -749.05], [56.93, 232.59, -750.73], [60.07, 231.55, -750.06], [60.07, 231.55, -750.06], [59.37, 232.94, -749.72], [59.72, 232.59, -751.07], [59.20, 231.72, -750.90], [60.24, 231.72, -750.90], [59.89, 233.82, -750.90], [58.85, 233.47, -750.56], [58.85, 232.42, -751.23], [59.02, 233.64, -749.72], [61.29, 233.12, -749.89], [59.72, 232.24, -750.39], [60.24, 231.37, -750.23], [59.72, 233.29, -750.73], [60.07, 231.55, -750.39], [67.75, 232.59, -749.72], [68.97, 231.72, -749.22], [68.10, 232.94, -748.38], [59.89, 233.12, -749.89], [59.89, 233.82, -750.56], [60.24, 234.17, -750.23], [58.32, 232.94, -751.40], [60.77, 233.64, -751.40], [60.24, 233.12, -749.89], [59.72, 232.24, -750.39], [59.89, 232.77, -749.89], [59.20, 231.37, -749.89], [59.20, 233.82, -750.90], [60.94, 233.12, -751.23], [59.89, 232.42, -750.90], [60.24, 233.12, -749.55], [59.72, 233.99, -749.72], [60.07, 232.24, -750.06], [60.24, 233.12, -750.23], [58.50, 232.42, -751.57], [58.67, 233.64, -752.41], [59.55, 233.12, -749.89], [61.29, 234.17, -749.89], [59.55, 232.42, -750.56], [60.59, 232.77, -750.56], [60.77, 232.94, -750.73], [58.85, 233.12, -748.54], [59.20, 233.12, -751.91], [61.47, 232.24, -750.73], [59.72, 234.34, -750.39], [61.64, 232.77, -748.21], [61.64, 232.77, -748.21], [59.55, 232.07, -750.23], [60.42, 231.55, -749.38], [60.59, 233.12, -749.55], [60.07, 231.90, -752.08], [61.82, 233.64, -750.39], [59.02, 233.64, -750.06], [59.89, 233.82, -750.56], [60.42, 230.50, -750.73], [61.29, 233.82, -750.23], [60.24, 232.77, -751.23], [59.72, 233.99, -750.39], [61.64, 231.02, -750.23], [60.59, 233.12, -751.57], [59.72, 233.99, -751.40], [59.89, 233.47, -750.90], [60.59, 233.47, -749.55], [59.37, 233.29, -750.39], [60.77, 232.59, -750.39], [51.86, 242.20, -739.80], [45.58, 242.55, -739.80], [44.88, 242.90, -739.80], [51.51, 234.86, -749.22], [59.55, 232.07, -751.57], [60.07, 233.29, -749.72], [61.29, 233.12, -751.57], [60.59, 233.82, -749.55], [59.37, 233.64, -750.06], [59.20, 232.77, -750.90], [59.72, 233.99, -750.06], [60.94, 234.51, -750.56], [59.20, 233.12, -751.57], [60.59, 233.82, -750.56], [61.12, 232.94, -750.73], [59.89, 234.17, -751.57], [60.59, 233.47, -750.90], [60.59, 231.37, -749.89], [59.55, 233.12, -750.90], [60.07, 234.69, -751.07], [60.77, 233.99, -751.40], [60.59, 232.42, -750.56], [60.59, 232.42, -750.56], [61.47, 232.59, -750.06], [60.94, 232.07, -751.57], [69.67, 260.71, -777.47], [67.93, 260.01, -777.81], [66.18, 261.06, -775.79], [57.62, 235.39, -754.09], [60.94, 233.47, -750.56], [61.64, 233.82, -750.23], [60.59, 234.17, -749.55], [61.82, 232.94, -750.73], [60.42, 233.64, -750.73], [60.07, 232.59, -749.72], [61.12, 232.24, -751.07], [60.94, 233.82, -750.23], [61.64, 235.21, -749.55], [60.94, 232.77, -750.90], [60.24, 234.17, -749.22], [60.77, 233.64, -750.73], [61.64, 232.42, -750.56], [61.12, 232.59, -750.06], [61.29, 233.47, -750.90], [60.77, 232.59, -750.73], [60.42, 233.29, -750.39], [60.42, 233.29, -750.06], [62.69, 233.82, -750.90], [59.89, 233.47, -750.56], [60.42, 233.29, -750.06], [65.66, 233.29, -749.38], [65.83, 232.07, -750.23], [66.53, 231.72, -749.89], [61.99, 233.12, -751.23], [61.47, 232.24, -750.06], [61.12, 235.04, -750.39], [60.42, 232.24, -749.38], [61.64, 233.47, -750.23], [61.64, 233.47, -750.23], [60.07, 233.64, -750.39], [60.59, 232.42, -750.90], [61.29, 233.12, -750.90], [61.99, 233.47, -750.56], [61.12, 232.94, -751.40], [60.42, 232.59, -751.40], [61.12, 234.69, -751.07], [61.64, 232.42, -751.23], [60.07, 233.64, -750.06], [62.51, 233.64, -751.40], [60.24, 234.17, -750.90], [60.77, 234.34, -750.06], [61.47, 234.69, -750.06], [60.59, 233.47, -750.56], [60.59, 233.12, -750.90], [62.16, 233.64, -751.40], [59.89, 232.77, -751.23], [61.82, 232.59, -751.40], [62.16, 232.94, -751.74], [61.12, 233.29, -749.72], [61.82, 233.64, -749.38], [59.55, 234.86, -750.90], [61.82, 232.94, -751.07], [60.77, 232.24, -750.06], [60.77, 232.24, -751.40], [60.24, 233.12, -749.55], [62.16, 234.34, -749.05], [61.12, 233.64, -750.06], [61.12, 232.24, -749.38], [62.34, 232.77, -750.90], [61.47, 233.29, -750.39], [61.47, 233.29, -750.39], [60.07, 232.94, -750.73], [54.66, 244.29, -737.44], [50.47, 246.04, -738.45], [58.32, 236.44, -754.09], [60.59, 233.12, -750.90], [61.82, 233.64, -750.06], [61.29, 233.47, -750.56], [61.64, 232.42, -750.23], [61.99, 233.47, -750.56], [61.64, 233.82, -750.56], [61.64, 234.51, -750.90], [61.82, 231.90, -749.38], [61.29, 232.42, -750.56], [60.94, 232.42, -750.23], [61.29, 232.77, -749.89], [60.77, 234.34, -750.73], [61.47, 230.85, -749.38], [61.82, 233.64, -750.39], [61.64, 234.17, -750.90], [61.47, 233.64, -750.39], [61.29, 234.86, -750.90], [62.34, 233.47, -751.57], [51.16, 252.33, -774.78], [51.51, 253.37, -774.44], [60.94, 233.82, -750.90], [62.16, 232.94, -748.71], [62.16, 233.64, -750.39], [60.94, 233.82, -749.22], [62.34, 233.82, -750.90], [60.94, 234.51, -749.89], [62.69, 234.17, -751.23], [61.99, 233.82, -749.89], [60.77, 233.29, -751.40], [61.64, 233.82, -750.56], [61.82, 233.29, -751.07], [62.16, 232.59, -751.74], [61.29, 231.37, -750.23], [62.86, 234.34, -750.06], [61.47, 232.24, -749.72], [61.47, 232.94, -752.08], [62.51, 232.94, -749.72], [62.69, 233.47, -749.89], [65.13, 232.42, -749.89], [64.26, 230.50, -751.40], [61.47, 232.94, -751.74], [61.82, 233.29, -751.07], [62.34, 233.47, -750.90], [61.64, 233.47, -750.56], [61.12, 232.59, -751.40], [61.64, 234.86, -749.89], [60.42, 232.59, -750.39], [61.99, 233.12, -749.89], [61.47, 231.90, -750.39], [61.64, 232.77, -752.24], [61.47, 232.59, -750.39], [61.64, 234.51, -750.90], [62.69, 234.51, -750.23], [63.04, 233.12, -749.22], [61.29, 232.77, -750.56], [60.59, 233.47, -748.54], [62.69, 232.07, -750.23], [62.34, 232.77, -750.56], [62.34, 232.77, -751.23], [61.82, 233.64, -750.06], [61.82, 232.24, -750.39], [62.51, 233.99, -750.73], [60.94, 234.17, -749.89], [60.94, 234.17, -749.89], [62.34, 232.07, -749.89], [62.86, 232.24, -750.06], [62.86, 232.24, -750.06], [61.47, 232.94, -749.38], [60.42, 232.24, -749.38], [62.69, 233.47, -750.56], [61.99, 232.77, -749.22], [61.99, 232.77, -749.22], [62.34, 233.82, -749.89], [62.34, 232.77, -751.23], [62.16, 233.29, -749.72], [62.51, 233.64, -750.73], [59.37, 234.69, -748.04], [61.47, 233.29, -750.73], [60.94, 233.47, -750.56], [61.64, 234.17, -749.22], [59.37, 246.21, -741.31], [58.85, 245.34, -741.82], [61.12, 233.64, -750.06], [61.64, 233.12, -751.57], [62.51, 233.64, -749.05], [60.59, 234.86, -750.56], [60.59, 233.82, -749.89], [60.94, 234.86, -749.89], [62.16, 232.59, -751.40], [61.82, 233.64, -750.39], [61.99, 233.82, -750.56], [60.94, 233.12, -750.90], [60.94, 233.12, -750.90], [59.89, 234.17, -751.23], [60.94, 232.42, -750.56], [61.82, 232.94, -751.40], [61.12, 233.29, -751.07], [62.69, 234.86, -750.23], [61.64, 235.21, -751.23], [61.64, 235.21, -751.23], [60.94, 233.47, -750.90], [40.86, 246.56, -779.66], [40.86, 246.56, -779.66], [39.46, 245.52, -778.31], [61.64, 234.17, -749.89], [61.64, 234.17, -749.89], [61.47, 233.99, -750.06], [63.04, 234.51, -750.90], [62.16, 233.64, -750.73], [62.69, 233.82, -748.88], [61.64, 233.47, -750.90], [61.47, 232.94, -751.07], [60.94, 233.47, -749.89], [61.99, 233.82, -750.56], [61.12, 232.24, -750.73], [61.12, 233.64, -750.39], [61.12, 234.34, -751.07], [61.82, 233.99, -751.07], [61.82, 233.99, -750.39], [62.51, 232.59, -751.07], [61.47, 234.34, -751.40], [62.69, 234.17, -749.89], [63.21, 234.69, -749.72], [64.78, 233.12, -751.57], [62.16, 233.64, -751.07], [61.47, 234.34, -749.72], [61.64, 233.47, -749.89], [62.51, 233.29, -749.05], [63.39, 233.82, -750.90], [63.39, 234.86, -750.56], [61.29, 234.17, -749.55], [60.77, 232.94, -749.72], [62.69, 231.37, -749.89], [62.69, 231.37, -749.89], [61.12, 233.64, -751.40], [62.16, 234.34, -749.72], [60.94, 234.17, -750.90], [61.82, 232.94, -749.72], [61.12, 232.24, -751.40], [61.82, 233.64, -751.40], [61.29, 233.47, -750.90], [61.82, 234.34, -750.73], [61.12, 233.29, -750.39], [61.29, 232.77, -749.89], [61.29, 233.47, -750.23], [60.42, 233.29, -750.73], [60.42, 233.29, -750.73], [61.64, 233.47, -751.57], [62.34, 234.17, -751.57], [62.69, 233.12, -750.23], [61.12, 232.94, -751.07], [61.12, 232.94, -751.07], [61.64, 233.12, -752.24], [60.77, 234.34, -750.39], [61.99, 234.51, -750.23], [60.59, 232.77, -751.23], [61.64, 234.51, -751.91], [61.64, 235.91, -750.56], [60.24, 234.17, -750.56], [60.77, 233.64, -751.74], [60.77, 233.64, -751.74], [60.59, 234.86, -751.23], [60.77, 232.59, -750.73], [61.64, 234.51, -749.89], [61.47, 233.99, -751.07], [62.69, 233.82, -749.89], [59.37, 242.37, -745.35], [59.55, 241.50, -745.85], [58.32, 240.98, -746.69], [61.82, 234.69, -750.39], [60.42, 233.99, -750.73], [60.94, 233.82, -750.23], [61.47, 233.99, -751.07], [61.47, 233.29, -750.73], [61.47, 234.34, -750.73], [61.99, 234.17, -750.23], [61.99, 234.17, -750.23], [61.82, 233.64, -751.40], [59.89, 233.82, -750.56], [59.89, 233.82, -750.56], [60.77, 233.99, -750.06], [60.77, 233.99, -750.06], [60.59, 233.12, -750.56], [60.77, 232.94, -751.40], [60.77, 232.94, -751.40], [60.59, 234.17, -751.91], [60.59, 234.17, -751.91], [60.94, 233.12, -750.23], [61.12, 233.29, -749.05], [61.12, 233.29, -749.05], [60.07, 234.34, -750.39], [51.16, 222.64, -761.33], [43.83, 233.47, -780.50], [51.86, 241.15, -774.11], [59.89, 233.47, -750.23], [61.29, 232.77, -749.55], [61.82, 233.64, -750.73], [61.82, 234.69, -750.73], [61.82, 234.69, -750.73], [61.64, 233.82, -749.22], [61.47, 234.69, -750.73], [60.42, 232.94, -748.71], [61.12, 233.99, -750.06], [61.12, 233.99, -750.06], [61.29, 234.17, -750.90], [60.07, 234.34, -749.38], [61.12, 234.69, -751.07], [59.89, 233.12, -749.89], [59.89, 233.12, -749.89], [60.59, 232.77, -751.57], [60.07, 233.99, -749.72], [61.99, 234.17, -749.22], [62.16, 232.94, -750.06], [60.42, 233.29, -751.40], [61.12, 233.64, -749.72], [61.99, 234.51, -749.55], [64.43, 234.51, -749.55], [63.21, 233.29, -750.39], [60.94, 233.82, -750.56], [61.82, 234.69, -750.39], [61.29, 234.17, -750.90], [62.34, 233.82, -749.55], [60.77, 233.64, -751.07], [61.47, 232.94, -750.39], [61.47, 233.29, -749.38], [59.89, 234.17, -750.90], [60.77, 233.29, -750.06], [60.42, 233.29, -750.39], [60.07, 234.34, -751.74], [60.07, 234.34, -751.74], [61.29, 234.51, -749.55], [59.89, 233.82, -750.23], [59.89, 233.82, -750.23], [61.82, 234.69, -751.74], [61.82, 234.69, -751.74], [60.42, 233.99, -750.06], [61.47, 233.64, -750.73], [61.47, 233.64, -750.73], [61.64, 233.47, -750.90], [61.64, 233.47, -750.90], [61.64, 234.17, -749.89], [59.37, 233.64, -751.07], [59.37, 233.64, -751.07], [60.59, 233.47, -751.23], [60.77, 233.64, -750.73], [60.24, 233.82, -750.23], [60.24, 233.82, -749.89], [60.24, 233.82, -749.89], [60.24, 234.17, -751.23], [59.72, 234.34, -750.73], [60.94, 233.47, -750.23], [62.34, 233.12, -751.57], [62.34, 233.12, -751.57], [60.07, 234.34, -750.39], [59.55, 232.42, -750.23], [59.20, 232.77, -749.89], [60.94, 234.17, -750.56], [60.24, 233.82, -750.23], [60.24, 233.47, -751.91], [60.42, 233.29, -750.39], [59.72, 234.69, -750.06], [61.29, 233.12, -750.90], [61.29, 233.12, -750.90], [61.12, 233.99, -750.39], [59.20, 234.51, -751.23], [59.89, 238.01, -747.87], [58.15, 238.71, -748.21], [57.97, 238.18, -747.70], [60.77, 233.99, -749.72], [61.99, 234.51, -751.23], [60.94, 232.77, -750.56], [60.77, 233.64, -750.39], [60.77, 234.34, -750.73], [59.72, 233.99, -748.38], [60.07, 233.29, -750.39], [59.89, 235.21, -750.90], [59.89, 235.21, -750.90], [59.89, 233.12, -750.23], [59.89, 233.12, -750.23], [59.89, 232.77, -750.56], [59.89, 232.77, -750.56], [60.07, 233.29, -750.73], [60.59, 233.82, -749.55], [60.59, 233.82, -749.55], [60.24, 233.47, -751.57], [59.89, 233.12, -749.89], [59.89, 233.12, -749.89], [59.89, 234.17, -750.56], [59.89, 234.17, -750.56], [49.77, 216.35, -766.37], [60.59, 219.85, -788.23], [62.34, 219.85, -788.91], [73.69, 232.24, -776.97], [59.72, 233.99, -750.06], [59.89, 232.77, -749.89], [59.20, 234.17, -749.55], [60.77, 232.24, -749.72], [57.80, 233.82, -749.55], [59.37, 233.64, -749.72], [60.24, 232.77, -749.55], [60.24, 232.77, -749.55]]
    }
    
    func getMagnetometerData() -> (x: Double, y: Double, z: Double){
        if let mm = motionManager{
            if let magnetometerData = mm.magnetometerData{
                print(NSString(format: "(x: %.2f, y: %.2f, z: %.2f),",
                    magnetometerData.magneticField.x, magnetometerData.magneticField.y,  magnetometerData.magneticField.z) as String)
                return (x: magnetometerData.magneticField.x, y: magnetometerData.magneticField.y, z: magnetometerData.magneticField.z)
                //                if let lm = locationManager{
                //                    if let h = lm.heading{
                //                        print(NSString(format: "%.0f\t%.0f\t%.0f\t%.0f\t%.0f\t%.0f", field.x, field.y, field.z, h.x, h.y, h.z ) as String)
                //                    }
                //                }
            } else {
                let data = test_data[counter]
                return (x: data[0], y: data[1], z: data[2])
            }
        } else {
            let data = test_data[counter]
            return (x: data[0], y: data[1], z: data[2])
        }
    }
    
    func interquartile_mean(array: [Double]) -> Double {
        let sorted_array = array.sort()
        let from = Int(array.count*1/4)
        let to = Int(array.count*3/4)
        return Array(sorted_array[from..<to]).average
    }

    func find_peaks(array: [Double]) -> [Double] {
        // find the highest peak
        let max_element_i = array.indexOf(array.maxElement()!)!
        
        // find the other 3 with equal distance
        let frame_size = Int((1 / magnetometerUpdateInterval) / Double(refresh_rate)  / Double(num_transmitters + 1))
        let i_mod = max_element_i % frame_size
        let spread = frame_size/4
        return [
            get_highest(array, index: i_mod + (frame_size * 0), spread: spread),
            get_highest(array, index: i_mod + (frame_size * 1), spread: spread),
            get_highest(array, index: i_mod + (frame_size * 2), spread: spread),
            get_highest(array, index: i_mod + (frame_size * 3), spread: spread)
        ]
    }

    func get_highest(array: [Double], index: Int, spread: Int) -> Double {
        let start_index = index - spread
        let end_index = index + spread
        if 0 <= start_index && end_index < array.count {
            return array[start_index...end_index].maxElement()!
        } else {
            // Handles peak falling very beginning of frame, so also checks end of frame
            if start_index < 0 {
                let x = array[array.count+start_index..<array.count]
                let y = array[0...end_index]
                return (x + y).maxElement()!
            } else { // end_index > array.count, peak falling very end of frame, so also checks start of frame
                let x = array[start_index..<array.count]
                let y = array[0...end_index-array.count]
                return (x + y).maxElement()!
            }
        }
    }
    
    func sync_phase(array: [Double]) -> [Double] {
        var peaks = array
        // lowest peak is the sync cycle
        let lowest_peak = peaks.minElement()
        while(peaks[0] != lowest_peak) {
            peaks.append(peaks.removeFirst())
        }
        return peaks
    }
    
    func chart(i: Int, p1: Double, p2: Double, p3: Double, p4: Double, p5: Double) {
        //dispatch_async(chart_queue!) {
        self.lineChartView.data?.addEntry(ChartDataEntry(value: p1, xIndex: i), dataSetIndex: 0)
        self.lineChartView.data?.addEntry(ChartDataEntry(value: p2, xIndex: i), dataSetIndex: 1)
        self.lineChartView.data?.addEntry(ChartDataEntry(value: p3, xIndex: i), dataSetIndex: 2)
        self.lineChartView.data?.addEntry(ChartDataEntry(value: p4, xIndex: i), dataSetIndex: 3)
        self.lineChartView.data?.addEntry(ChartDataEntry(value: p5, xIndex: i), dataSetIndex: 4)
        self.lineChartView.data?.addXValue(String(i))
        self.lineChartView.setVisibleXRange(minXRange: CGFloat(1), maxXRange: CGFloat(100))
        self.lineChartView.notifyDataSetChanged()
        self.lineChartView.moveViewToX(CGFloat(i))
        //}
    }
    
    func locationManagerShouldDisplayHeadingCalibration(manager: CLLocationManager) -> Bool {
        // if you want the calibration dialog to be able to appear
        return true
    }
    
    func deg2rad(deg : Float) -> Float {
        return deg * 0.017453292519943295769236907684886
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
}
