//
//  ViewController.swift
//  ARToolKitBySwift
//
//  Created by 藤澤研究室 on 2016/07/11.
//  Copyright © 2016年 藤澤研究室. All rights reserved.
// sa2taka

import UIKit
import QuartzCore

class ViewController: UIViewController, CameraVideoTookPictureDelegate, EAGLViewTookSnapshotDelegate {
    var running: Bool
    var runLoopInterval: Int
    var runLoopTimePrevious: NSTimeInterval
    var videoPaused: Bool
    var gVid: AR2VideoParamT?
    var gARHandle: ARHandle?
    var gARPattHandle: ARPattHandle?
    var gCallCountMarkerDetect: Int64
    var gAR3DHandle: AR3DHandle?
    var gPatt_width: ARdouble
    var gPatt_trans34: ARdouble
    var gPatt_found: Int32
    var gPatt_id: Int32
    var useContPoseEstimation: Bool
    var gCparamLT: ARParamLT?
    var glView: ARView?
    var arglContextSettings: ARGL_CONTEXT_SETTINGS_REF?
    
    // ロード画面の描画
    func loadView() {
        self.wantsFullScreenLayout = YES // フルスクリーンモード
        
        // This will be overlaid with the actual AR view.
        var irisImage : String? = nil
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            irisImage = "Iris-iPad.png"
        } else { // UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone
            let result = UIScreen.mainScreen().bounds().size
            if (result.height == 568) {
                irisImage = "Iris-568h.png" // iPhone 5, iPod touch 5th Gen, etc.
            } else { // result.height == 480
                irisImage = "Iris.png"
            }
        }
        let irisView = UIImageView.alloc(initWithImage(UIImage.imageNamed(irisImage).autorelease))
        irisView.userInteractionEnabled = YES // タッチの検知を行う
        self.view = irisView
    }
    
    // 画面が表示された直後に実行される
    func viewDidAppear(animated:Bool) {
        super.viewDidAppear(animated)
        self.start()
    }
    
    // On iOS 6.0 and later, we must explicitly report which orientations this view controller supports.
    func supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
        return UIInterfaceOrientationMaskPortrait
    }
    
    func startRunLoop() {
        if (!running) {
            // After starting the video, new frames will invoke cameraVideoTookPicture:userData:.
            if (ar2VideoCapStart(gVid) != 0) {
                NSLog("Error: Unable to begin camera data capture.\n")
                self.stop()
                return
            }
            running = true
        }
    }
    
    func stopRunLoop() {
        if running == true {
            ar2VideoCapStop(gVid)
            running = false
        }
    }
    
    func setRunLoopInterval(interval:Int) {
        if (interval >= 1) {
            runLoopInterval = interval
            if (running) {
                self.stopRunLoop()
                self.startRunLoop()
            }
        }
    }
    
    func isPaused() -> Bool {
        if (!running) {
            return (NO)
        }
        return (videoPaused)
    }
    
    func setPaused(paused: Bool) {
        if (!running) {
            return
        }
        if (videoPaused != paused) {
            if (paused) {
                ar2VideoCapStop(gVid)
            }
            else {
                ar2VideoCapStart(gVid)
            }
            videoPaused = paused
        }
    }
    
    @IBAction func start() {
        let vconf : CChar = nil
        if (gVid = ar2VideoOpenAsync(vconf, startCallback, self)) == false
        {
            NSLog("Error: Unable to open connection to camera.\n")
            self.stop()
            return
        }
    }
    
    @IBAction func stop() {
        self.stopRunLoop()
        
        if arglContextSettings == true {
            arglCleanup(arglContextSettings)
            arglContextSettings = NULL
        }
        glView.removeFromSuperview()
        glView = nil
        
        if gARHandle == true{
            arPattDetach(gARHandle)
        }
        if gARPattHandle == true {
            arPattDeleteHandle(gARPattHandle)
            gARHandle = nil
        }
        arParamLTFree(gCparamLT)
        if gVid == true {
            ar2VideoClose(gVid)
            gVid = nil
        }
    }
    
    func cameraVideoTookPicture(sender:AnyObject,  userData data:AnyObject)
    {
        var buffer : AR2VideoBufferT! = ar2VideoGetImage(gVid)
        if (buffer){
            self.processFrame(buffer)
        }
    }
    
    func processFrame(buffer: AR2VideoBufferT!) {
        var err : ARdouble
        var j, k : Int
        
        if (buffer)
        {
            // Upload the frame to OpenGL.
            if (buffer.bufPlaneCount == 2)
            {
                arglPixelBufferDataUploadBiPlanar(arglContextSettings, buffer.bufPlanes[0], buffer.bufPlanes[1])
            }
            else
            {
                arglPixelBufferDataUpload(arglContextSettings, buffer.buff)
            }
            gCallCountMarkerDetect++ // Increment ARToolKit FPS counter.
            
            // Detect the markers in the video frame.
            if (arDetectMarker(gARHandle, buffer.buff) < 0)
            {
                return
            }
            // Check through the marker_info array for highest confidence
            // visible marker matching our preferred pattern.
            k = -1
            for (j = 0;j < gARHandle.marker_num;j++) {
                if (gARHandle.markerInfo[j].id == gPatt_id) {
                    if (k == -1)
                    {
                        k = j // First marker detected.
                    }
                    else if (gARHandle.markerInfo[j].cf > gARHandle.markerInfo[k].cf)
                    {
                        k = j // Higher confidence marker detected.
                    }
                }
            }
            
            if (k != -1)
            {
                // Get the transformation between the marker and the real camera into gPatt_trans.
                if (gPatt_found && useContPoseEstimation)
                {
                    err = arGetTransMatSquareCont(gAR3DHandle, &(gARHandle.markerInfo[k]), gPatt_trans, gPatt_width, gPatt_trans)
                }
                else
                {
                    err = arGetTransMatSquare(gAR3DHandle, &(gARHandle.markerInfo[k]), gPatt_width, gPatt_trans)
                }
                var modelview : [Float] = []
                gPatt_found = true
                glView(setCameraPose(modelview))
            } else {
                gPatt_found = false
                glView(setCameraPose(nil))
            }
            
            // Get current time (units = seconds).
            var runLoopTimeNow: NSTimeInterval
            runLoopTimeNow = CFAbsoluteTimeGetCurrent()
            glView(updateWithTimeDelta(runLoopTimeNow - runLoopTimePrevious))
            
            // The display has changed.
            glView(drawView(self))
            
            // Save timestamp for next loop.
            runLoopTimePrevious = runLoopTimeNow
        }
    }
    
    func takeSnapshot() {
        // We will need to wait for OpenGL rendering to complete.
        glView.setTookSnapshotDelegate(self)
        glView.takeSnapshot()
    }
    
    func voidstartRunLoop() {
        if (!running) {
            // After starting the video, new frames will invoke cameraVideoTookPicture:userData:.
            if (ar2VideoCapStart(gVid) != 0) {
                NSLog("Error: Unable to begin camera data capture.\n")
                self.stop()
                return
            }
            running = true
        }
    }
    
    
    static func startCallback(userData: void) {
        var vc = userData as? ARViewController
        vc.start2
    }
    
    func start2() {
        // Find the size of the window.
        var xsize, ysize: Int
        if (ar2VideoGetSize(gVid, &xsize, &ysize) < 0) {
            NSLog("Error: ar2VideoGetSize.\n")
            self.stop()
            return
        }
        
        // Get the format in which the camera is returning pixels.
        var pixFormat = ar2VideoGetPixelFormat(gVid)
        if (pixFormat == AR_PIXEL_FORMAT_INVALID) {
            NSLog("Error: Camera is using unsupported pixel format.\n")
            self.stop()
            return
        }
        
        // Work out if the front camera is being used. If it is, flip the viewing frustum for
        // 3D drawing.
        var flipV = false
        var frontCamera: Int
        if (ar2VideoGetParami(gVid, AR_VIDEO_PARAM_IOS_CAMERA_POSITION, &frontCamera) >= 0) {
            if (frontCamera == AR_VIDEO_IOS_CAMERA_POSITION_FRONT) {
                flipV = true
            }
        }
        
        // Tell arVideo what the typical focal distance will be. Note that this does NOT
        // change the actual focus, but on devices with non-fixed focus, it lets arVideo
        // choose a better set of camera parameters.
        ar2VideoSetParami(gVid, AR_VIDEO_PARAM_IOS_FOCUS, AR_VIDEO_IOS_FOCUS_0_3M) // Default is 0.3 metres. See <AR/sys/videoiPhone.h> for allowable values.
        
        // Load the camera parameters, resize for the window and init.
        var cparam: ARParam? = ARParam()
        if (ar2VideoGetCParam(gVid, &cparam) < 0) {
            var cparam_name: String? = "Data2/camera_para.dat"
            NSLog("Unable to automatically determine camera parameters. Using default.\n")
            if (arParamLoad(cparam_name, 1, &cparam) < 0) {
                NSLog("Error: Unable to load parameter file %s for camera.\n", cparam_name)
                self.stop()
                return
            }
        }
        if (cparam.xsize != xsize || cparam.ysize != ysize) {
            arParamChangeSize(&cparam, xsize, ysize, &cparam)
        }
        
        if ((gCparamLT = arParamLTCreate(&cparam, AR_PARAM_LT_DEFAULT_OFFSET)) == nil) {
            NSLog("Error: arParamLTCreate.\n")
            self.stop()
            return
        }
        
        // AR init.
        if ((gARHandle = arCreateHandle(gCparamLT)) == nil) {
            NSLog("Error: arCreateHandle.\n")
            self.stop()
            return
        }
        if (arSetPixelFormat(gARHandle, pixFormat) < 0) {
            NSLog("Error: arSetPixelFormat.\n")
            self.stop()
            return
        }
        if ((gAR3DHandle = ar3DCreateHandle(&gCparamLT.param)) == nil) {
            NSLog("Error: ar3DCreateHandle.\n")
            self.stop()
            return
        }
        
        // libARvideo on iPhone uses an underlying class called CameraVideo. Here, we
        // access the instance of this class to get/set some special types of information.
        var cameraVideo: CameraVideo? = ar2VideoGetNativeVideoInstanceiPhone(gVid.device.iPhone)
        if (!cameraVideo) {
            NSLog("Error: Unable to set up AR camera: missing CameraVideo instance.\n")
            self.stop()
            return
        }
        
        // The camera will be started by -startRunLoop.
        cameraVideo(setTookPictureDelegate:self)
        cameraVideo(setTookPictureDelegateUserData:nil)
        
        // Other ARToolKit setup.
        arSetMarkerExtractionMode(gARHandle, AR_USE_TRACKING_HISTORY_V2)
        //arSetMarkerExtractionMode(gARHandle, AR_NOUSE_TRACKING_HISTORY)
        //arSetLabelingThreshMode(gARHandle, AR_LABELING_THRESH_MODE_MANUAL) // Uncomment to use  manual thresholding.
        
        // Allocate the OpenGL view.
        glView = ARView.alloc().initWithFrame(UIScreen.mainScreen().bounds (pixelFormat:kEAGLColorFormatRGBA8, depthFormat:kEAGLDepth16, withStencil:NO, preserveBackbuffer:NO).autorelease) // Don't retain it, as it will be retained when added to self.view.
        glView.arViewController = self
        self.view(addSubview(glView))
        
        // Create the OpenGL projection from the calibrated camera parameters.
        // If flipV is set, flip.
        var frustum: [GLfloat]
        arglCameraFrustumRHf(&gCparamLT.param, VIEW_DISTANCE_MIN, VIEW_DISTANCE_MAX, frustum)
        glView(setCameraLens:frustum)
        glView.contentFlipV = flipV
        
        // Set up content positioning.
        glView.contentScaleMode = ARViewContentScaleModeFill
        glView.contentAlignMode = ARViewContentAlignModeCenter
        glView.contentWidth = gARHandle.xsize
        glView.contentHeight = gARHandle.ysize
        var isBackingTallerThanWide: Bool = (glView.surfaceSize.height > glView.surfaceSize.width)
        if (glView.contentWidth > glView.contentHeight) {
            glView.contentRotate90 = isBackingTallerThanWide
        }
        else {
            glView.contentRotate90 = !isBackingTallerThanWide
        }
        
        // Setup ARGL to draw the background video.
        arglContextSettings = arglSetupForCurrentContext(&gCparamLT.param, pixFormat)
        
        arglSetRotate90(arglContextSettings, (glView.contentWidth > glView.contentHeight ? isBackingTallerThanWide : !isBackingTallerThanWide))
        if (flipV) {
            arglSetFlipV(arglContextSettings, true)
        }
        var width, height: Int?
        ar2VideoGetBufferSize(gVid, &width, &height)
        arglPixelBufferSizeSet(arglContextSettings, width, height)
        
        // Prepare ARToolKit to load patterns.
        if (!(gARPattHandle = arPattCreateHandle())) {
            NSLog("Error: arPattCreateHandle.\n")
            self.stop()
            return
        }
        arPattAttach(gARHandle, gARPattHandle)
        
        // Load marker(s).
        // Loading only 1 pattern in this example.
        var patt_name: String?  = "Data2/hiro.patt"
        if ((gPatt_id = arPattLoad(gARPattHandle, patt_name)) < 0) {
            NSLog("Error loading pattern file %s.\n", patt_name)
            self.stop()
            return
        }
        gPatt_width = 40.0
        gPatt_found = false
        
        // For FPS statistics.
        arUtilTimerReset()
        gCallCountMarkerDetect = 0
        
        //Create our runloop timer
        self.setRunLoopInterval(2) // Target 30 fps on a 60 fps device.
        self.startRunLoop()
    }
    
    func cameraVideoTookPicture(sender:id, userData data:UnsafeMutablePointer<void>)
    {
        var buffer: AR2VideoBufferT? = ar2VideoGetImage(gVid)
        if (buffer) {
            self.processFrame(buffer)
        }
    }
    
    func viewWillDisappear(animated:Bool) {
        self.stop()
        super.viewWillDisappear(animated)
    }

    func dealloc() {
        super.dealloc()
    }
    
    // ARToolKit-specific methods.
    func markersHaveWhiteBorders() -> Bool {
        var mode: Int?
        arGetLabelingMode(gARHandle, &mode)
        return (mode == AR_LABELING_WHITE_REGION)
    }

    func setMarkersHaveWhiteBorders(markersHaveWhiteBorders:Bool) {
        arSetLabelingMode(gARHandle, (markersHaveWhiteBorders ? AR_LABELING_WHITE_REGION : AR_LABELING_BLACK_REGION))
    }
    
    // Call this method to take a snapshot of the ARView.
    // Once the image is ready, tookSnapshot:forview: will be called.
    func takeSnapshot() {
        // We will need to wait for OpenGL rendering to complete.
        glView.setTookSnapshotDelegate(self)
        glView.takeSnapshot()
    }
    
    // Here you can choose what to do with the image.
    // We will save it to the iOS camera roll.
    func tookSnapshot(snapshot: UnsafeMutablePointer<UIImage>, forView view:UnsafeMutablePointer<EAGLView>) {
        // First though, unset ourselves as delegate.
        glView.setTookSnapshotDelegate(nil)
    
        // Write image to camera roll.
        UIImageWriteToSavedPhotosAlbum(snapshot, self, selector(image:didFinishSavingWithError:contextInfo:), nil)
    }
    
    // Let the user know that the image was saved by playing a shutter sound,
    // or if there was an error, put up an alert.
    func image(image:UnsafeMutablePointer<UIImage>, didFinishSavingWithError error:UnsafeMutablePointer<NSError>, contextInfo: UnsafeMutablePointer<void>) {
        if (!error) {
            var shutterSound: SystemSoundID
            AudioServicesCreateSystemSoundID(NSBundle.mainBundle().URLForResource("slr_camera_shutter").withExtension("wav") as CFURLRef, &shutterSound)
            AudioServicesPlaySystemSound(shutterSound)
        } else {
            var titleString: String? = "Error saving screenshot"
            var messageString: Stirng? = error.localizedDescription()
            var moreString: String? = error.localizedFailureReason() ? error.localizedFailureReason() : NSLocalizedString("Please try again.", nil)
            messageString = NSString.stringWithFormat("%@. %@", messageString, moreString)
            var alertView: UIAlertView? = UIAlertView.alloc(initWithTitle(titleString), message(messageString), delegate(self), cancelButtonTitle("OK"), otherButtonTitles(nil))
            alertView.show()
            alertView.release()
        }
    }

    
    private(set) var glView: ARView
    private(set) var arglContextSettings: ARGL_CONTEXT_SETTINGS_REF
    private(set) var running: Bool
    var paused: Bool
    var runLoopInterval: Int
    var markersHaveWhiteBorders: Bool
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        // 変数の初期化
        glView = nil
        gVid = nil
        gCparamLT = nil
        gARHandle = nil
        gARPattHandle = nil
        gCallCountMarkerDetect = 0
        gAR3DHandle = nil
        useContPoseEstimation = false
        arglContextSettings = nil
        running = false
        videoPaused = false
        runLoopTimePrevious = CFAbsoluteTimeGetCurrent()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
}

