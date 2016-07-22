//
//  ViewController.swift
//  ARToolKitBySwift
//
//  Created by 藤澤研究室 on 2016/07/11.
//  Copyright © 2016年 藤澤研究室. All rights reserved.
// sa2tala

import UIKit
import QuartzCore

class ViewController: UIViewController, CameraVideoTookPictureDelegate, EAGLViewTookSnapshotDelegate {
    var running: Bool
    var runLoopInterval: Int
    var runLoopTimePrevious: NSTimeInterval
    var videoPaused: Bool
    var gVid: AR2VideoParamT
    var gARHandle: ARHandle
    var gARPattHandle: ARPattHandle
    var gCallCountMarkerDetect: Int64
    var gAR3DHandle: AR3DHandle
    var gPatt_width: ARdouble
    var gPatt_trans34: ARdouble
    var gPatt_found: Int32
    var gPatt_id: Int32
    var useContPoseEstimation: Bool
    var gCparamLT: ARParamLT
    var glView: ARView
    var arglContextSettings: ARGL_CONTEXT_SETTINGS_REF
    
    
    
    @IBAction func start() {
        let vconf : CChar = nil
        if (gVid = ar2VideoOpenAsync(vconf, startCallback, self)) == false
        {
            NSLog("Error: Unable to open connection to camera.\n");
            self.stop()
            return
        }
    }
    
    @IBAction func stop() {
        self.stopRunLoop()
        
        if arglContextSettings == true {
            arglCleanup(arglContextSettings);
            arglContextSettings = NULL;
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
    
    func cameraVideoTookPicture(sender: AnyObject,  userData data: AnyObject)
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
            k = -1;
            for (j = 0; j < gARHandle.marker_num; j++) {
                if (gARHandle.markerInfo[j].id == gPatt_id) {
                    if (k == -1)
                    {
                        k = j; // First marker detected.
                    }
                    else if (gARHandle.markerInfo[j].cf > gARHandle.markerInfo[k].cf)
                    {
                        k = j; // Higher confidence marker detected.
                    }
                }
            }
    
            if (k != -1)
            {
                // Get the transformation between the marker and the real camera into gPatt_trans.
                if (gPatt_found && useContPoseEstimation)
                {
                    err = arGetTransMatSquareCont(gAR3DHandle, &(gARHandle.markerInfo[k]), gPatt_trans, gPatt_width, gPatt_trans);
                }
                else
                {
                    err = arGetTransMatSquare(gAR3DHandle, &(gARHandle.markerInfo[k]), gPatt_width, gPatt_trans);
                }
                var modelview : [Float] = []
                gPatt_found = TRUE;
                [glView setCameraPose:modelview];
            } else {
                gPatt_found = FALSE;
                [glView setCameraPose:NULL];
            }

// Get current time (units = seconds).
NSTimeInterval runLoopTimeNow;
runLoopTimeNow = CFAbsoluteTimeGetCurrent();
[glView updateWithTimeDelta:(runLoopTimeNow - runLoopTimePrevious)];

// The display has changed.
[glView drawView:self];

// Save timestamp for next loop.
runLoopTimePrevious = runLoopTimeNow;
}
    }

    func takeSnapshot() {
    }

    func stopRunLoop() {
        if running == true {
            ar2VideoCapStop(gVid)
            running = false
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
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

