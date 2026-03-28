import SwiftUI
import AVFoundation
import CoreImage

// =======================================================
// MARK: - Film Camera View
// Skeuomorphic film camera — 4:3 viewfinder with film
// frame borders, textured camera body, Dazz/NOMO inspired.
// =======================================================

struct FilmCameraView: View {
    let onCapture: (UIImage) -> Void
    let onDismiss: () -> Void

    @StateObject private var camera = FilmCameraEngine()
    @State private var shutterFlash = false
    @State private var capturedImage: UIImage?
    @State private var showReview = false
    @State private var shutterScale: CGFloat = 1.0
    @State private var filmCounter: Int = Int.random(in: 1...24)

    // Camera body color palette
    private let bodyColor = Color(red: 0.09, green: 0.09, blue: 0.10)
    private let bodyHighlight = Color(red: 0.15, green: 0.15, blue: 0.16)
    private let chrome = Color(red: 0.28, green: 0.28, blue: 0.30)
    private let chromeLight = Color(red: 0.42, green: 0.42, blue: 0.44)
    private let amber = Color(red: 0.95, green: 0.68, blue: 0.25)
    private let amberDim = Color(red: 0.85, green: 0.60, blue: 0.22).opacity(0.7)

    private let dateStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "'04   yy   MM   dd"
        return f
    }()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                bodyColor.ignoresSafeArea()

                if showReview, let img = capturedImage {
                    reviewScreen(image: img, geo: geo)
                        .transition(.opacity)
                } else {
                    cameraBody(geo: geo)
                        .transition(.opacity)
                }

                // Shutter flash
                if shutterFlash {
                    Color.white.ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showReview)
        }
        .statusBarHidden()
        .onAppear { camera.startSession() }
        .onDisappear { camera.stopSession() }
    }

    // =====================================================
    // MARK: - Camera Body
    // =====================================================

    private func cameraBody(geo: GeometryProxy) -> some View {
        let safeTop = geo.safeAreaInsets.top
        let safeBot = geo.safeAreaInsets.bottom
        let screenW = geo.size.width
        let screenH = geo.size.height + safeTop + safeBot  // full screen height

        // Fixed chrome heights
        let topH: CGFloat = safeTop + 52 + 1       // safe area + chrome strip + edge
        let bottomH: CGFloat = 1 + 100 + safeBot + 16  // edge + controls + safe area + grip

        // 4:3 viewfinder — fit to remaining height, capped by width
        let viewfinderPadH: CGFloat = 2
        let maxW = screenW - viewfinderPadH * 2
        let maxH = screenH - topH - bottomH
        let viewfinderH = min(maxW * (4.0 / 3.0), maxH)
        let viewfinderW = viewfinderH * (3.0 / 4.0)

        return VStack(spacing: 0) {
            // === Top camera body: brand plate + controls ===
            topCameraBody(safeTop: safeTop)

            Spacer(minLength: 0)

            // === Viewfinder area ===
            ZStack {
                // Camera preview (fills the 4:3 area)
                FilmPreviewRepresentable(camera: camera)
                    .frame(width: viewfinderW, height: viewfinderH)
                    .clipped()

                // Warm filter tint overlay
                Color(red: 1.0, green: 0.95, blue: 0.85).opacity(0.03)
                    .frame(width: viewfinderW, height: viewfinderH)
                    .allowsHitTesting(false)

                // Film frame border overlay
                filmFrameBorder(width: viewfinderW, height: viewfinderH)
            }
            .frame(width: viewfinderW, height: viewfinderH)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.black.opacity(0.8), lineWidth: 1.5)
            )

            Spacer(minLength: 0)

            // === Bottom camera body: shutter + controls ===
            bottomCameraBody(safeBot: safeBot)
        }
        .ignoresSafeArea()
    }

    // =====================================================
    // MARK: - Top Camera Body
    // =====================================================

    private func topCameraBody(safeTop: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Safe area fill
            bodyColor.frame(height: safeTop).ignoresSafeArea()

            // Chrome strip
            HStack(spacing: 0) {
                // Close button
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .background(chrome.opacity(0.6))
                        .clipShape(Circle())
                }
                .padding(.leading, 16)

                Spacer()

                // Brand plate — embossed style
                VStack(spacing: 1) {
                    Text("FUJI")
                        .font(.system(size: 8.5, weight: .heavy))
                        .tracking(4)
                        .foregroundColor(chromeLight.opacity(0.9))

                    Rectangle()
                        .fill(chrome.opacity(0.4))
                        .frame(width: 36, height: 0.5)

                    Text("CCD")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.45))
                }

                Spacer()

                // Flash indicator
                Button {
                    camera.flashEnabled.toggle()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: camera.flashEnabled ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(camera.flashEnabled ? amber : .white.opacity(0.35))
                        .frame(width: 36, height: 36)
                        .background(chrome.opacity(0.4))
                        .clipShape(Circle())
                }
                .padding(.trailing, 16)
            }
            .frame(height: 52)
            .background(
                LinearGradient(
                    colors: [bodyHighlight, bodyColor],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Thin chrome edge below top body
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [chrome.opacity(0.5), chrome.opacity(0.15)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
    }

    // =====================================================
    // MARK: - Film Frame Border (inside viewfinder)
    // =====================================================

    private func filmFrameBorder(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Semi-transparent black border strips (film rebate area)
            VStack(spacing: 0) {
                // Top strip
                HStack {
                    // Film perforations (left)
                    filmPerforations(count: 4, vertical: false)
                        .padding(.leading, 8)
                    Spacer()
                    // Frame number
                    Text("\(filmCounter)A")
                        .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                        .foregroundColor(amber.opacity(0.6))
                        .padding(.trailing, 12)
                }
                .frame(height: 18)
                .background(Color.black.opacity(0.55))

                Spacer()

                // Bottom strip
                HStack(alignment: .center) {
                    // Film stock info
                    Text("FUJI  CCD  04")
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundColor(amber.opacity(0.45))
                        .padding(.leading, 12)

                    Spacer()

                    // Date stamp
                    Text(dateStampFormatter.string(from: Date()))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(amber.opacity(0.7))
                        .padding(.trailing, 12)
                }
                .frame(height: 20)
                .background(Color.black.opacity(0.55))
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }

    /// Film perforation marks
    private func filmPerforations(count: Int, vertical: Bool) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 5, height: 8)
            }
        }
    }

    // =====================================================
    // MARK: - Bottom Camera Body
    // =====================================================

    private func bottomCameraBody(safeBot: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Chrome edge above bottom body
            Rectangle()
                .fill(chrome.opacity(0.3))
                .frame(height: 1)

            // Main control area
            HStack(alignment: .center) {
                // Frame counter (left)
                VStack(spacing: 1) {
                    Text("\(filmCounter)")
                        .font(.system(size: 20, weight: .light, design: .monospaced))
                        .foregroundColor(amber)
                    Rectangle()
                        .fill(chrome.opacity(0.3))
                        .frame(width: 20, height: 0.5)
                    Text("36")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.2))
                }
                .frame(width: 60)

                Spacer()

                // === Shutter button ===
                shutterButton

                Spacer()

                // Flip camera (right)
                Button {
                    camera.flipCamera()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    ZStack {
                        Circle()
                            .fill(chrome.opacity(0.35))
                            .frame(width: 44, height: 44)
                        Circle()
                            .stroke(chromeLight.opacity(0.3), lineWidth: 0.8)
                            .frame(width: 44, height: 44)
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .frame(width: 60)
            }
            .padding(.horizontal, 24)
            .frame(height: 100)
            .background(
                LinearGradient(
                    colors: [bodyColor, bodyHighlight.opacity(0.5), bodyColor],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Leatherette texture strip
            Rectangle()
                .fill(
                    Color(red: 0.07, green: 0.07, blue: 0.08)
                )
                .frame(height: safeBot + 16)
                .overlay(alignment: .top) {
                    // Subtle grip line
                    HStack(spacing: 3) {
                        ForEach(0..<30, id: \.self) { _ in
                            Circle()
                                .fill(Color.white.opacity(0.02))
                                .frame(width: 2, height: 2)
                        }
                    }
                    .padding(.top, 6)
                }
        }
    }

    // =====================================================
    // MARK: - Shutter Button
    // =====================================================

    private var shutterButton: some View {
        Button {
            takePhoto()
        } label: {
            ZStack {
                // Outer chrome ring
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [chromeLight, chrome, chromeLight.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                // Inner dark ring
                Circle()
                    .fill(bodyColor)
                    .frame(width: 64, height: 64)

                // Shutter face
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color(white: 0.9)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 26
                        )
                    )
                    .frame(width: 52, height: 52)

                // Highlight reflection
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.4), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .frame(width: 48, height: 48)
            }
            .scaleEffect(shutterScale)
            .shadow(color: Color.black.opacity(0.5), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // =====================================================
    // MARK: - Review Screen
    // =====================================================

    private func reviewScreen(image: UIImage, geo: GeometryProxy) -> some View {
        let screenW = geo.size.width
        let frameW = screenW - 32
        let photoW = frameW - 24
        let photoH = photoW * (4.0 / 3.0)
        let frameH = photoH + 60   // Extra space for bottom with date

        return ZStack {
            bodyColor.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Film print card — white border like a real print
                VStack(spacing: 0) {
                    // Photo area
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: photoW, height: photoH)
                        .clipped()
                        .padding(.top, 12)
                        .padding(.horizontal, 12)

                    // Bottom of print — date stamp area
                    HStack {
                        Text("FUJI CCD 04")
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(Color.gray.opacity(0.35))

                        Spacer()

                        Text(dateStampFormatter.string(from: Date()))
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundColor(amber.opacity(0.85))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
                }
                .frame(width: frameW)
                .background(Color(red: 0.97, green: 0.96, blue: 0.94))  // Slightly warm white
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 8)

                Spacer()

                // Action buttons
                HStack(spacing: 0) {
                    // Retake
                    Button {
                        capturedImage = nil
                        showReview = false
                    } label: {
                        Text("RETAKE")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(2)
                            .foregroundColor(.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(chrome.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Spacer().frame(width: 12)

                    // Use photo
                    Button {
                        onCapture(image)
                    } label: {
                        Text("USE PHOTO")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(2)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, geo.safeAreaInsets.bottom + 16)
            }
        }
    }

    // =====================================================
    // MARK: - Actions
    // =====================================================

    private func takePhoto() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        // Shutter press animation
        withAnimation(.easeIn(duration: 0.06)) { shutterScale = 0.88 }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5).delay(0.06)) { shutterScale = 1.0 }

        // Flash
        withAnimation(.easeIn(duration: 0.03)) { shutterFlash = true }
        withAnimation(.easeOut(duration: 0.12).delay(0.05)) { shutterFlash = false }

        camera.capturePhoto { image in
            guard let image else { return }
            let processed = FilmFilterEngine.applyToCapture(image)
            filmCounter = min(filmCounter + 1, 36)
            capturedImage = processed
            showReview = true
        }
    }
}

// =======================================================
// MARK: - AVCaptureSession Engine
// =======================================================

final class FilmCameraEngine: NSObject, ObservableObject {
    let captureSession = AVCaptureSession()
    @Published var flashEnabled = false
    @Published var isUsingFrontCamera = false

    private var currentDevice: AVCaptureDevice?
    private var photoOutput = AVCapturePhotoOutput()
    private var captureCompletion: ((UIImage?) -> Void)?
    private let sessionQueue = DispatchQueue(label: "film.camera.session")

    func startSession() {
        sessionQueue.async { [weak self] in
            self?.configureSession()
            self?.captureSession.startRunning()
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }

    func flipCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let wantFront = !isUsingFrontCamera
            self.captureSession.beginConfiguration()

            for input in self.captureSession.inputs {
                self.captureSession.removeInput(input)
            }

            let position: AVCaptureDevice.Position = wantFront ? .front : .back
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                self.captureSession.commitConfiguration()
                return
            }

            if self.captureSession.canAddInput(input) {
                self.captureSession.addInput(input)
                self.currentDevice = device
            }

            self.captureSession.commitConfiguration()
            DispatchQueue.main.async { self.isUsingFrontCamera = wantFront }
        }
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        captureCompletion = completion
        let settings = AVCapturePhotoSettings()
        if let device = currentDevice, device.hasFlash {
            settings.flashMode = flashEnabled ? .on : .off
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func configureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            captureSession.commitConfiguration()
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
            currentDevice = device
        }

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .balanced
        }

        captureSession.commitConfiguration()
    }
}

extension FilmCameraEngine: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              var image = UIImage(data: data) else {
            DispatchQueue.main.async { self.captureCompletion?(nil) }
            return
        }

        if isUsingFrontCamera {
            image = image.horizontallyFlipped()
        }

        DispatchQueue.main.async { self.captureCompletion?(image) }
    }
}

// =======================================================
// MARK: - Live Preview UIView
// =======================================================

struct FilmPreviewRepresentable: UIViewRepresentable {
    @ObservedObject var camera: FilmCameraEngine

    func makeUIView(context: Context) -> FilmPreviewUIView {
        let view = FilmPreviewUIView()
        view.attachSession(camera.captureSession)
        return view
    }

    func updateUIView(_ uiView: FilmPreviewUIView, context: Context) {}
}

final class FilmPreviewUIView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    func attachSession(_ session: AVCaptureSession) {
        guard let layer = self.layer as? AVCaptureVideoPreviewLayer else { return }
        layer.session = session
        layer.videoGravity = .resizeAspectFill
        self.previewLayer = layer
    }
}
