import SwiftUI
import RealityKit
import ARKit

struct RealityViewContainer: UIViewControllerRepresentable {
    var arSession: ARSession
    
    func makeUIViewController(context: Context) -> UIViewController {
        let arView = ARView(frame: .zero)
        arView.session = arSession
        
        let controller = UIViewController()
        controller.view = arView
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
