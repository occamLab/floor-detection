/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the AR experience.
*/

import UIKit
import SceneKit
import ARKit

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    // MARK: - IBOutlets

    @IBOutlet weak var sessionInfoView: UIView!
    @IBOutlet weak var sessionInfoLabel: UILabel!
    @IBOutlet weak var sceneView: ARSCNView!
    var pins: [SCNNode] = []
    let label = UILabel(frame: CGRect(x: 0, y: 0, width: 400, height: 25))

    // MARK: - View Life Cycle

    /// - Tag: StartARSession
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Start the view's AR session with a configuration that uses the rear camera,
        // device position and orientation tracking, and plane detection.
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        sceneView.session.run(configuration)

        // Set a delegate to track the number of plane anchors for providing UI feedback.
        sceneView.session.delegate = self
        
        // Prevent the screen from being dimmed after a while as users will likely
        // have long periods of interaction without touching the screen or buttons.
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Show debug UI to view performance metrics (e.g. frames per second).
        sceneView.showsStatistics = true
        
        addTapGestureToSceneView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        label.font = UIFont.preferredFont(forTextStyle: .title2)

        label.textColor = .black

        label.center.x = sceneView.center.x
        label.center.y = sceneView.bounds.maxY + 50

        label.textAlignment = .center
        label.backgroundColor = .white

        label.text = ""

        sceneView.addSubview(label)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Pause the view's AR session.
        sceneView.session.pause()
    }

    // MARK: - ARSCNViewDelegate
    
    /// - Tag: PlaceARContent
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        // Place content only for anchors found by plane detection.
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        
        // Create a custom object to visualize the plane geometry and extent.
        let plane = Plane(anchor: planeAnchor, in: sceneView)
        
        // Add the visualization to the ARKit-managed node so that it tracks
        // changes in the plane anchor as plane estimation continues.
        node.addChildNode(plane)
    }

    /// - Tag: UpdateARContent
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        // Update only anchors and nodes set up by `renderer(_:didAdd:for:)`.
        guard let planeAnchor = anchor as? ARPlaneAnchor,
            let plane = node.childNodes.first as? Plane
            else { return }
        
        // Update ARSCNPlaneGeometry to the anchor's new estimated shape.
        if let planeGeometry = plane.meshNode.geometry as? ARSCNPlaneGeometry {
            planeGeometry.update(from: planeAnchor.geometry)
        }

        // Update extent visualization to the anchor's new bounding rectangle.
        if let extentGeometry = plane.extentNode.geometry as? SCNPlane {
            extentGeometry.width = CGFloat(planeAnchor.extent.x)
            extentGeometry.height = CGFloat(planeAnchor.extent.z)
            plane.extentNode.simdPosition = planeAnchor.center 
        }
        
        plane.centerNode?.transform = SCNMatrix4(anchor.transform)
        
        // Update the plane's classification and the text position
        if #available(iOS 12.0, *),
            let classificationNode = plane.classificationNode,
            let classificationGeometry = classificationNode.geometry as? SCNText {
            let currentClassification = planeAnchor.classification.description
            if let oldClassification = classificationGeometry.string as? String, oldClassification != currentClassification {
                classificationGeometry.string = currentClassification
                classificationNode.centerAlign()
            }
        }
        
    }
    
    func addTapGestureToSceneView() {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(ViewController.addBox(withGestureRecognizer:)))
        sceneView.addGestureRecognizer(tapGestureRecognizer)
    }
    
    // move node position relative to another node's position.
    func updatePositionAndOrientationOf(_ node: SCNNode, withPosition position: SCNVector3, relativeTo referenceNode: SCNNode) {
        let referenceNodeTransform = matrix_float4x4(referenceNode.transform)
        
        var translationMatrix = matrix_identity_float4x4
        translationMatrix.columns.3.x = position.x
        translationMatrix.columns.3.y = position.y
        translationMatrix.columns.3.z = position.z
        
        let updatedTransform = matrix_multiply(referenceNodeTransform, translationMatrix)
        node.transform = SCNMatrix4(updatedTransform)
    }
    
    @objc func addBox(withGestureRecognizer recognizer: UIGestureRecognizer) {
        let box = SCNBox(width: 0.05, height: 0.2, length: 0.05, chamferRadius: 0)
        
        let text = SCNText(string: "Pin", extrusionDepth: 0)
        
        let cameraNode = sceneView.pointOfView
        let boxNode = SCNNode()
        let textNode = SCNNode()
        boxNode.geometry = box
        boxNode.name = "Pin"
        textNode.geometry = text
        textNode.name = "Pin"
        let boxPosition = SCNVector3(0,0,-0.4)
        let textPosition = SCNVector3(0,0.1,0)
        
        updatePositionAndOrientationOf(boxNode, withPosition: boxPosition, relativeTo: cameraNode!)
        
        textNode.scale = SCNVector3(0.005,0.005,0.005)
        textNode.position = textPosition
        
        sceneView.scene.rootNode.addChildNode(boxNode)
        boxNode.addChildNode(textNode)
        
        pins.append(boxNode)
        label.text = ""
        
        if pins.count > 2 {
            pins[0].removeFromParentNode()
            pins.remove(at: 0)
        }
        if pins.count == 2 {
            let result1 = getFloorIntersection(from: pins[0])
            let result2 = getFloorIntersection(from: pins[1])
            var shareFloor = false
            var gotMatch = false
            let epsilon: Float = 0.05
            for r1 in result1 {
                makeIntersectNode(from: pins[0], onto: r1)
                for r2 in result2 {
                    makeIntersectNode(from: pins[1], onto: r2)
                    if r1.anchor == r2.anchor {
                        gotMatch = true
                        // Get positions of pin projections
                        let delta = simd_float3(0, epsilon, 0)
                        let pos1 = simd_float3(r1.worldTransform.columns.3.x,
                                               r1.worldTransform.columns.3.y,
                                               r1.worldTransform.columns.3.z)
                        let pos2 = simd_float3(r2.worldTransform.columns.3.x,
                                               r2.worldTransform.columns.3.y,
                                               r2.worldTransform.columns.3.z)
                        
                        
                        // Detect if the pins are too far apart
                        let diff = pos1 - pos2
                        let dist = length(diff)
                        if dist > 2 {
                            shareFloor = false
                            label.text = "Too far apart (\(dist) m)"
                            print("Too far apart (\(dist) m)")
                            break
                        }
                        
                        // Create line node between pin projections
                        let hitTestNode = lineNode(from: pos1, to: pos2)
                        guard let plane = r1.anchor as? ARPlaneAnchor else {
                            continue
                        }
                        
                        // Detect if the line node leaves the plane boundary
                        let vertices = plane.geometry.boundaryVertices
                        var leavePlane = false
                        for i in 0...(vertices.count - 2){
                            if hitTestNode.hitTestWithSegment(from: SCNVector3(vertices[i]), to: SCNVector3(vertices[i+1])).count > 0 {
                                leavePlane = true
                                break
                            }
                        }
                        if leavePlane {
                            shareFloor = false
                            label.text = "Left plane boundary"
                            print("Left plane boundary")
                            continue
                        }
                        
                        // Detect if the ray from pos2 to pos1 crosses a wall
                        let raycastquery = ARRaycastQuery(origin: pos2 + delta, direction: diff, allowing: .existingPlaneGeometry, alignment: .vertical)
                        let raycastResults = sceneView.session.raycast(raycastquery)
                        if raycastResults.count == 0 {
                            shareFloor = true
                            label.text = "No walls"
                            print("No walls")
                            break
                        }
                        
                        // If it does cross a wall, check if the wall is between the positions
                        shareFloor = true
                        for wall in raycastResults {
                            let intersection = simd_float3(wall.worldTransform.columns.3.x,
                                                           wall.worldTransform.columns.3.y,
                                                           wall.worldTransform.columns.3.z)
                            if length(intersection - pos2) < dist {
                                makeIntersectNode(from: pins[0], onto: wall, UIColor.cyan)
                                shareFloor = false
                                label.text = "Hit wall"
                                print("Hit wall")
                                break
                            }
                        }
                        if shareFloor {
                            break
                        }
                    }
                }
                if shareFloor {
                    break
                }
            }
            if result1.count == 0 {
                for r2 in result2 {
                    makeIntersectNode(from: pins[1], onto: r2)
                }
            }
            if !gotMatch {
                label.text = "Different planes. P1: \(result1.count). P2: \(result2.count)"
                print("Not the same plane. P1 planes: \(result1.count). P2 planes: \(result2.count).")
            }
            
            if shareFloor {
                pins[0].geometry?.firstMaterial?.diffuse.contents = UIColor.green
                pins[1].geometry?.firstMaterial?.diffuse.contents = UIColor.green
            } else {
                pins[0].geometry?.firstMaterial?.diffuse.contents = UIColor.red
                pins[1].geometry?.firstMaterial?.diffuse.contents = UIColor.red
            }
        }
    }
    
    func getFloorIntersection(from pin: SCNNode) -> [ARRaycastResult]{
        let pos = vector3(pin.position.x, pin.position.y, pin.position.z)
        let raycastquery = ARRaycastQuery(origin: pos, direction: vector3(0,-1,0), allowing: .existingPlaneGeometry, alignment: .horizontal)
        return sceneView.session.raycast(raycastquery)
    }
    
    func makeIntersectNode(from pin: SCNNode, onto result: ARRaycastResult, _ color: UIColor = UIColor.purple){
        let smallBox = SCNBox(width: 0.05, height: 0.05, length: 0.05, chamferRadius: 0)
        let intersectNode = SCNNode()
        intersectNode.geometry = smallBox
        intersectNode.name = "Intersection"
        intersectNode.transform = SCNMatrix4(matrix_multiply(simd_float4x4(pin.transform).inverse, result.worldTransform))
        intersectNode.geometry?.firstMaterial?.diffuse.contents = color
        pin.addChildNode(intersectNode)
    }
    
    func lineNode(from: simd_float3, to: simd_float3) -> SCNNode {
        let distance = simd_length(to - from)
        let cylinder = SCNCylinder(radius: 0.005, height: CGFloat(distance))
        
        let lineNode = SCNNode(geometry: cylinder)
        lineNode.position = SCNVector3((from + to)/2)
        lineNode.eulerAngles = SCNVector3(Float.pi/2,
                                          acos((to.z - from.z)/distance),
                                          atan2(to.y - from.y, to.x - from.x))
        return lineNode
    }
    
    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        guard let frame = session.currentFrame else { return }
        updateSessionInfoLabel(for: frame, trackingState: frame.camera.trackingState)
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        guard let frame = session.currentFrame else { return }
        updateSessionInfoLabel(for: frame, trackingState: frame.camera.trackingState)
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        updateSessionInfoLabel(for: session.currentFrame!, trackingState: camera.trackingState)
    }

    // MARK: - ARSessionObserver

    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay.
        sessionInfoLabel.text = "Session was interrupted"
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required.
        sessionInfoLabel.text = "Session interruption ended"
        resetTracking()
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        sessionInfoLabel.text = "Session failed: \(error.localizedDescription)"
        guard error is ARError else { return }
        
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        
        // Remove optional error messages.
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        
        DispatchQueue.main.async {
            // Present an alert informing about the error that has occurred.
            let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
            let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
                alertController.dismiss(animated: true, completion: nil)
                self.resetTracking()
            }
            alertController.addAction(restartAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }

    // MARK: - Private methods

    private func updateSessionInfoLabel(for frame: ARFrame, trackingState: ARCamera.TrackingState) {
        // Update the UI to provide feedback on the state of the AR experience.
        let message: String

        switch trackingState {
        case .normal where frame.anchors.isEmpty:
            // No planes detected; provide instructions for this app's AR interactions.
            message = "Move the device around to detect horizontal and vertical surfaces."
            
        case .notAvailable:
            message = "Tracking unavailable."
            
        case .limited(.excessiveMotion):
            message = "Tracking limited - Move the device more slowly."
            
        case .limited(.insufficientFeatures):
            message = "Tracking limited - Point the device at an area with visible surface detail, or improve lighting conditions."
            
        case .limited(.initializing):
            message = "Initializing AR session."
            
        default:
            // No feedback needed when tracking is normal and planes are visible.
            // (Nor when in unreachable limited-tracking states.)
            message = ""

        }

        sessionInfoLabel.text = message
        sessionInfoView.isHidden = message.isEmpty
    }

    private func resetTracking() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
}
