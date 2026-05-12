# Frigate Apple Silicon Detector

Ứng dụng macOS native để chạy detector ONNX cho Frigate trên Apple Silicon. App được đóng gói sẵn runtime, thư viện Python cần thiết và model `yolov8n.onnx`, nên người dùng tải về không cần cài Python, venv hay dependencies của repo.

## Sử dụng app macOS

1. Tải file `FrigateDetector.app.zip` trong mục GitHub Releases.
2. Giải nén file zip.
3. Mở `FrigateDetector.app`.
   - Nếu macOS chặn lần đầu, xem phần **Mở app khi macOS chặn** bên dưới.
4. Trong app:
   - `Model`: mặc định dùng model `yolov8n.onnx` được đóng gói sẵn trong app.
   - `Host`: dùng `*` để cho phép Frigate kết nối từ máy/container khác.
   - `Port`: mặc định `5555`.
   - Bấm `Bắt đầu`.
5. Chờ khoảng 1 phút để runtime và model khởi động hoàn toàn.
6. Cấu hình Frigate trỏ tới endpoint TCP của máy Mac, ví dụ:

```yaml
detectors:
  apple_silicon:
    type: zmq
    endpoint: tcp://192.168.2.2:5555
```

Thay `192.168.2.2` bằng IP LAN của máy Mac đang chạy app.

## Mở app khi macOS chặn

App release hiện tại chưa được notarize chính thức qua Apple, nên macOS có thể chặn lần mở đầu tiên với thông báo kiểu:

```text
"FrigateDetector" đã bị chặn để bảo vệ máy Mac của bạn.
```

Nếu gặp trường hợp này:

1. Mở `System Settings`.
2. Vào `Quyền riêng tư & Bảo mật` (`Privacy & Security`).
3. Kéo xuống phần `Bảo mật` (`Security`).
4. Ở dòng macOS báo `FrigateDetector` bị chặn, bấm `Vẫn mở` (`Open Anyway`).
5. Xác nhận lại nếu macOS hỏi thêm.
6. Mở lại `FrigateDetector.app`.

Bạn nên tự đọc code, tự kiểm tra release và tự chịu trách nhiệm khi chạy app trên máy của mình. App cần mở endpoint TCP để Frigate kết nối, vì vậy hãy kiểm tra firewall, mạng nội bộ và quyền truy cập trước khi dùng lâu dài.

## App lưu dữ liệu ở đâu?

App không ghi vào thư mục hệ thống Python hay venv của máy host. Dữ liệu runtime được lưu tại:

```text
~/Library/Application Support/FrigateDetector
```

Log cũng được stream trực tiếp trong app và ghi ra:

```text
~/Library/Application Support/FrigateDetector/Logs/FrigateDetector.log
```

## Build app từ source

Yêu cầu trên máy build:

- macOS Apple Silicon
- Xcode Command Line Tools
- `uv` hoặc Python 3.11+

Build app:

```bash
make app
```

App sau khi build nằm tại:

```text
macos/FrigateDetector.app
```

Tạo file zip để release:

```bash
cd macos
ditto -c -k --sequesterRsrc --keepParent FrigateDetector.app FrigateDetector.app.zip
```

## Chạy detector bằng dòng lệnh

Bạn vẫn có thể chạy detector trực tiếp bằng Makefile:

```bash
make install
make run MODEL=yolo/yolov8n.onnx ENDPOINT=tcp://*:5555
```

Hoặc dùng model do Frigate truyền sang:

```bash
make run MODEL=AUTO ENDPOINT=tcp://*:5555
```

## Thành phần chính

- `macos/App/Sources/FrigateDetectorApp.swift`: giao diện macOS native.
- `detector/zmq_onnx_client.py`: ZMQ server nhận tensor từ Frigate và chạy ONNX Runtime.
- `detector/model_util.py`: hậu xử lý output model.
- `yolo/yolov8n.onnx`: model mặc định được bundle vào app release.
- `macos/scripts/build_app.sh`: script build `.app`, đóng gói detector runtime bằng PyInstaller.

## Ghi chú release

Build hiện tại được ad-hoc signed để chạy nội bộ. Nếu muốn phát hành public mượt hơn, nên ký bằng `Developer ID Application` và notarize bằng Apple Developer account trước khi upload GitHub Release.
