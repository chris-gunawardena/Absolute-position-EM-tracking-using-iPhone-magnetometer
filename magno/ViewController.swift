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
    var r1_history: [Double] = []
    var r2_history: [Double] = []
    var r3_history: [Double] = []
    var motionManager : CMMotionManager?
    var locationManager : CLLocationManager?
    var box: SCNNode!
    var test_data = [[Double]]()
    var start_time = NSDate().timeIntervalSinceReferenceDate * 1000
    var chart_queue: dispatch_queue_t?
    var charts_enbled = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        start_motion_manager()
        //start_location_manager()
        
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
        let field = get_magnetometer_data()
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
            
            r1_history.append(intensity_to_distance(peaks[1]))
            r2_history.append(intensity_to_distance(peaks[2]))
            r3_history.append(intensity_to_distance(peaks[3]))
            if(r1_history.count >= 4) {
                let r1 = interquartile_mean(r1_history)
                let r2 = interquartile_mean(r2_history)
                let r3 = interquartile_mean(r3_history)
            
                let cordinates = trilaterate(r1, r2: r2, r3: r3)
                let scale = Double(2.0)
                //plot3d(self.box, x: r1, y: r2, z: r3)
                plot3d(self.box, x: cordinates.x * scale, y: cordinates.y * scale, z: cordinates.z * scale)
                chart(self.i, p1: peaks[0], p2: peaks[1], p3: peaks[2], p4: peaks[3], p5: self.magno_readings_n.last!)
                
                // time between readings, should be 10ms but longer when charts are enabled
                let now = NSDate().timeIntervalSinceReferenceDate * 1000
                let time_diff = Int(now - self.start_time)
                self.start_time = now
                
                self.magno_label.text = NSString(format: "%.1f\n%.1f %.1f %.1f\n%.1f %.1f %.1f\n%.1f %.1f",
                                                 time_diff,
                                                 peaks[1], peaks[2], peaks[3],
                                                 r1, r2, r3,
                                                 cordinates.x, cordinates.y) as String
                r1_history.removeFirst()
                r2_history.removeFirst()
                r3_history.removeFirst()
            }
            magno_readings_n.removeFirst()
            i = i + 1
        }
        // used for test data
        counter = counter + 1
        if counter >= test_data.count {
            counter = 0
        }
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
    func chart(i: Int, p1: Double, p2: Double, p3: Double, p4: Double, p5: Double) {
        if (charts_enbled == false) {
            return
        }
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

    func start_motion_manager() {
        motionManager = CMMotionManager()
        motionManager?.showsDeviceMovementDisplay = true
        motionManager?.magnetometerUpdateInterval = magnetometerUpdateInterval
        motionManager?.startMagnetometerUpdates()
    }
    func start_location_manager() {
        locationManager = CLLocationManager()
        locationManager?.requestWhenInUseAuthorization()
        locationManager?.startUpdatingHeading()
    }
    
    func create_scene(view: SCNView) -> SCNNode {
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
        
        let scene = SCNScene()
        view.scene = scene
        
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.yFov = 10
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(x: 0.5, y: 0.5, z: 5)
//        cameraNode.rotation = SCNVector4(1,0,1, deg2rad(30))
//        cameraNode.rotation = SCNVector4(0,0,1, deg2rad(-30))
        scene.rootNode.addChildNode(cameraNode)
        
        scene.rootNode.addChildNode(make_light(5, y: 0, z: 0))
        scene.rootNode.addChildNode(make_light(0, y: 5, z: 0))
        scene.rootNode.addChildNode(make_light(0, y: 0, z: 5))

        // axis
        scene.rootNode.addChildNode(make_box(UIColor.redColor(), width: 2, height: 0.01, length: 0.01))
        scene.rootNode.addChildNode(make_box(UIColor.greenColor(), width: 0.01, height: 2, length: 0.01))
        scene.rootNode.addChildNode(make_box(UIColor.blueColor(), width: 0.01, height: 0.01, length: 2))
        
        let marker = make_box(UIColor.magentaColor(), width: 0.1, height: 0.1, length: 0.1)
        scene.rootNode.addChildNode(marker)
        
        view.delegate = self
        view.playing = true
        
        return marker
    }
    func plot3d(marker:SCNNode, x: Double, y: Double, z: Double) {
        marker.position.x = Float(x)
        marker.position.y = Float(y)
        marker.position.z = Float(z)
    }
    
    func get_magnetometer_data() -> (x: Double, y: Double, z: Double){
        if let mm = motionManager{
            if let magnetometerData = mm.magnetometerData{
                charts_enbled = false // updating chart slows down getting data
                print(NSString(format: "%.8f,%.8f,%.8f,",
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
    func get_test_data() -> [[Double]] {
        guard let path = NSBundle.mainBundle().pathForResource("testdata", ofType: "csv") else {
            return []
        }
        do {
            let content = try String(contentsOfFile:path, encoding: NSUTF8StringEncoding)
            let line_str_array = content.componentsSeparatedByString("\n")
            return line_str_array.map {
                let field_str_array = $0.componentsSeparatedByString(",")
                return field_str_array.map {
                    Double($0)!
                }
            }
        } catch _ as NSError {
            return []
        }
    }

    func interquartile_mean(array: [Double]) -> Double {
        let sorted_array = array.sort()
        let from = Int(array.count*1/4)
        let to = Int(array.count*3/4)
        return Array(sorted_array[from..<to]).average
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
    func sync_phase(array: [Double]) -> [Double] {
        var peaks = array
        // lowest peak is the sync cycle
        let lowest_peak = peaks.minElement()
        while(peaks[0] != lowest_peak) {
            peaks.append(peaks.removeFirst())
        }
        return peaks
    }
    func intensity_to_distance(intensity: Double) -> Double {
        //http://www.instructables.com/id/Evaluate-magnetic-field-variation-with-distance/?ALLSTEPS
        let distance = pow(1 / intensity, 1 / 3.0)
        return distance
    }
    func trilaterate(r1: Double, r2: Double, r3: Double) -> (x: Double, y: Double, z: Double) {
        let nr1 = r1 / (r1+r2+r3)
        let nr2 = r2 / (r1+r2+r3)
        let nr3 = r3 / (r1+r2+r3)
        // https://en.wikipedia.org/wiki/Trilateration
        let d = Double(0.5)
        let i = Double(0.25)
        let j = sqrt(d*d - i*i)
        
        let x = (nr1*nr1 - nr2*nr2 + d*d) / (2 * d)
        let y = ((nr1*nr1 - nr3*nr3 + i*i + j*j) / (2*j)) - i*x/j
        //let z2 = (nr1*nr1) - (x*x) - (y*y)
        //let z = z2 > 0  ? sqrt(z2) : sqrt(z2 * -1)
        
        return (x: x, y: y, z: 0.1)
    }

    func deg2rad(deg : Float) -> Float {
        return deg * 0.017453292519943295769236907684886
    }
    func locationManagerShouldDisplayHeadingCalibration(manager: CLLocationManager) -> Bool {
        // if you want the calibration dialog to be able to appear
        return true
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
}
