import SwiftUI
import AVFoundation
import CoreImage

// =======================================================
// MARK: - Camera Preset
// =======================================================

enum CameraPreset: String, CaseIterable, Identifiable {
    case plain
    case fujiCCD

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .plain: return "PLAIN"
        case .fujiCCD: return "FUJI"
        }
    }

    var appliesFilmFilter: Bool { self == .fujiCCD }
    var showsFilmFrame: Bool { self == .fujiCCD }
}

// =======================================================
// MARK: - Film Camera View
// Skeuomorphic film camera — 4:3 viewfinder with film
// frame borders, textured camera body, Dazz/NOMO inspired.
// =======================================================

struct FilmCameraView: View {
    let onCapture: (UIImage) -> Void
    let onDismiss: () -> Void
    let availablePresets: [CameraPreset]

    @StateObject private var camera = FilmCameraEngine()
    @State private var selectedPreset: CameraPreset
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

    init(
        onCapture: @escaping (UIImage) -> Void,
        onDismiss: @escaping () -> Void,
        availablePresets: [CameraPreset] = [.plain],
        initialPreset: CameraPreset = .plain
    ) {
        self.onCapture = onCapture
        self.onDismiss = onDismiss
        self.availablePresets = availablePresets
        let effective = availablePresets.contains(initialPreset) ? initialPreset : (availablePresets.first ?? .plain)
        self._selectedPreset = State(initialValue: effective)
    }

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
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            camera.startSession()
        }
        .onDisappear {
            camera.stopSession()
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
    }

    // =====================================================
    // MARK: - Camera Body
    // =====================================================

    private func cameraBody(geo: GeometryProxy) -> some View {
        let safeTop = geo.safeAreaInsets.top
        let safeBot = geo.safeAreaInsets.bottom
        let screenW = geo.size.width
        let viewfinderPadH: CGFloat = 2
        let viewfinderW = screenW - viewfinderPadH * 2
        let viewfinderH = viewfinderW * (4.0 / 3.0)

        return VStack(spacing: 0) {
            topCameraBody(safeTop: safeTop)

            ZStack {
                FilmPreviewRepresentable(camera: camera)
                    .frame(width: viewfinderW, height: viewfinderH)
                    .clipped()

                Color(red: 0.88, green: 0.95, blue: 1.0).opacity(0.04)
                    .frame(width: viewfinderW, height: viewfinderH)
                    .allowsHitTesting(false)

                if selectedPreset.showsFilmFrame {
                    filmFrameBorder(width: viewfinderW, height: viewfinderH)
                }
            }
            .frame(width: viewfinderW, height: viewfinderH)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.black.opacity(0.8), lineWidth: 1.5)
            )
            .padding(.horizontal, viewfinderPadH)

            bottomCameraBody(safeBot: safeBot)
        }
    }

    // =====================================================
    // MARK: - Top Camera Body
    // =====================================================

    private func topCameraBody(safeTop: CGFloat) -> some View {
        VStack(spacing: 0) {
            bodyColor.frame(height: safeTop).ignoresSafeArea()

            HStack(spacing: 0) {
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
    // MARK: - Film Frame Border
    // =====================================================

    private func filmFrameBorder(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    filmPerforations(count: 4, vertical: false)
                        .padding(.leading, 8)
                    Spacer()
                    Text("\(filmCounter)A")
                        .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                        .foregroundColor(amber.opacity(0.6))
                        .padding(.trailing, 12)
                }
                .frame(height: 18)
                .background(Color.black.opacity(0.55))

                Spacer()

                HStack(alignment: .center) {
                    Text("FUJI  CCD  04")
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundColor(amber.opacity(0.45))
                        .padding(.leading, 12)

                    Spacer()

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

    // =====================================================
    // MARK: - Preset Strip (NOMO-style camera row)
    // =====================================================

    private var presetStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(availablePresets) { preset in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { selectedPreset = preset }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(spacing: 6) {
                            presetIcon(for: preset)
                            Text(preset.displayLabel)
                                .font(.system(size: 8, weight: selectedPreset == preset ? .bold : .regular,
                                              design: .monospaced))
                                .tracking(1.5)
                                .foregroundColor(selectedPreset == preset ? amber : .white.opacity(0.28))
                            // Selection dot
                            Circle()
                                .fill(selectedPreset == preset ? amber : Color.clear)
                                .frame(width: 3, height: 3)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 32)
        }
        .frame(height: 68)
    }

    @ViewBuilder
    private func presetIcon(for preset: CameraPreset) -> some View {
        let isSelected = selectedPreset == preset
        if preset == .plain {
            // Plain: clean SF Symbol camera, no skeuomorphic chrome
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color(white: 0.18) : Color(white: 0.10))
                    .frame(width: 40, height: 30)
                Image(systemName: "camera")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(isSelected ? .white.opacity(0.9) : .white.opacity(0.25))
            }
        } else {
            // Film camera — scaled-down version of filmCameraCenterDrop
            ZStack {
                // Body
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.18, green: 0.18, blue: 0.20),
                                 Color(red: 0.10, green: 0.10, blue: 0.12)],
                        startPoint: .top, endPoint: .bottom))
                    .frame(width: 40, height: 30)

                // Chrome top edge
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color(white: 0.35), Color(white: 0.22)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: 40, height: 1)
                    .offset(y: -10)

                // Viewfinder bump (top-left)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color(red: 0.14, green: 0.14, blue: 0.16))
                    .frame(width: 10, height: 4)
                    .offset(x: -10, y: -13)

                // Amber flash (top-right)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(red: 0.95, green: 0.80, blue: 0.4).opacity(0.75))
                    .frame(width: 5, height: 5)
                    .offset(x: 13, y: -8)

                // Lens
                Circle()
                    .fill(Color(red: 0.06, green: 0.06, blue: 0.08))
                    .frame(width: 16, height: 16)
                Circle()
                    .stroke(Color(white: 0.30), lineWidth: 1)
                    .frame(width: 16, height: 16)
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(red: 0.2, green: 0.25, blue: 0.4),
                                 Color(red: 0.06, green: 0.08, blue: 0.14)],
                        center: .center, startRadius: 1, endRadius: 7))
                    .frame(width: 11, height: 11)
                Circle()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 3, height: 3)
                    .offset(x: -2.5, y: -2.5)
            }
            .frame(width: 40, height: 30)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? amber.opacity(0.7) : Color.clear, lineWidth: 1)
            )
        }
    }

    private func bottomCameraBody(safeBot: CGFloat) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(chrome.opacity(0.3))
                .frame(height: 1)

            HStack(alignment: .center) {
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

                shutterButton

                Spacer()

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

            // Camera selector strip — always shown, scrollable
            Rectangle()
                .fill(chrome.opacity(0.12))
                .frame(height: 0.5)

            presetStrip
                .background(bodyColor)

            // Safe area leatherette
            Rectangle()
                .fill(Color(red: 0.07, green: 0.07, blue: 0.08))
                .frame(height: safeBot + 4)
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
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [chromeLight, chrome, chromeLight.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                Circle()
                    .fill(bodyColor)
                    .frame(width: 64, height: 64)

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

        return ZStack {
            bodyColor.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 0) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: photoW, height: photoH)
                        .clipped()
                        .padding(.top, 12)
                        .padding(.horizontal, 12)

                    if selectedPreset.showsFilmFrame {
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
                    } else {
                        Spacer().frame(height: 16)
                    }
                }
                .frame(width: frameW)
                .background(
                    selectedPreset.showsFilmFrame
                        ? Color(red: 0.97, green: 0.96, blue: 0.94)
                        : Color.white
                )
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 8)

                Spacer()

                HStack(spacing: 0) {
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

        withAnimation(.easeIn(duration: 0.06)) { shutterScale = 0.88 }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5).delay(0.06)) { shutterScale = 1.0 }

        withAnimation(.easeIn(duration: 0.03)) { shutterFlash = true }
        withAnimation(.easeOut(duration: 0.12).delay(0.05)) { shutterFlash = false }

        camera.capturePhoto { image in
            guard let image else { return }
            let processed = self.selectedPreset.appliesFilmFilter
                ? FilmFilterEngine.applyToCapture(image)
                : image
            if self.selectedPreset.showsFilmFrame {
                self.filmCounter = min(self.filmCounter + 1, 36)
            }
            self.capturedImage = processed
            self.showReview = true
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
    @Published var isSessionReady = false

    private var currentDevice: AVCaptureDevice?
    private var photoOutput = AVCapturePhotoOutput()
    private var captureCompletion: ((UIImage?) -> Void)?
    private let sessionQueue = DispatchQueue(label: "film.camera.session")

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureSession()
            self.captureSession.startRunning()
            DispatchQueue.main.async { self.isSessionReady = self.captureSession.isRunning }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
            DispatchQueue.main.async { self?.isSessionReady = false }
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
        // Read device orientation on the calling (main) thread before dispatching.
        let deviceOrientation = UIDevice.current.orientation
        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.captureCompletion = completion
            let settings = AVCapturePhotoSettings()
            if let device = self.currentDevice, device.hasFlash {
                settings.flashMode = self.flashEnabled ? .on : .off
            }
            // Bake the correct orientation into the captured pixels.
            // UIDeviceOrientation.landscapeLeft/Right are swapped vs AVCaptureVideoOrientation by convention.
            if let connection = self.photoOutput.connection(with: .video) {
                if #available(iOS 17.0, *) {
                    // videoOrientation deprecated in iOS 17; use videoRotationAngle.
                    // angle=0 → sensor native (landscape), 90 → portrait, 180 → landscape flipped, 270 → portrait UD
                    let angle: CGFloat
                    switch deviceOrientation {
                    case .landscapeLeft:       angle = 0
                    case .landscapeRight:      angle = 180
                    case .portraitUpsideDown:  angle = 270
                    default:                   angle = 90
                    }
                    if connection.isVideoRotationAngleSupported(angle) {
                        connection.videoRotationAngle = angle
                    }
                } else {
                    if connection.isVideoOrientationSupported {
                        switch deviceOrientation {
                        case .landscapeLeft:       connection.videoOrientation = .landscapeRight
                        case .landscapeRight:      connection.videoOrientation = .landscapeLeft
                        case .portraitUpsideDown:  connection.videoOrientation = .portraitUpsideDown
                        default:                   connection.videoOrientation = .portrait
                        }
                    }
                }
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
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
