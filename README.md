# Bên Nhau

Ứng dụng Flutter (iOS + Android) để hai người chia sẻ vị trí cho nhau theo thời gian thực.

## Cách dùng

1. Người thứ nhất nhập tên, bấm **Tạo mã kết nối mới**, rồi gửi mã (nút chìa khoá → *Gửi mã*).
2. Người thứ hai nhập tên và mã đó, bấm **Kết nối**.
3. Cả hai thấy nhau trên bản đồ, kèm khoảng cách và thời điểm cập nhật. Công tắc
   **Chia sẻ vị trí của tôi** để tạm dừng bất cứ lúc nào.

## Cách hoạt động

- Không cần tài khoản hay server riêng: vị trí được chuyển qua MQTT broker công cộng
  (`broker.emqx.io`, TLS) — đổi ở `lib/services/sync_service.dart`.
- Mọi dữ liệu được mã hoá đầu-cuối bằng AES-256-GCM, khoá suy ra từ mã kết nối
  (`lib/services/pairing.dart`). Broker chỉ thấy dữ liệu đã mã hoá; ai có mã thì xem được vị trí,
  nên chỉ gửi mã cho đúng người.
- Bản đồ: OpenStreetMap qua `flutter_map` (không cần API key).

## Chạy

```bash
flutter run
```

Thử với một máy: giả lập người còn lại bằng

```bash
dart run tool/fake_partner.dart XXXX-XXXX-XXXX 10.7797 106.6990
```

Logo: `assets/logo/logo.svg` (nguồn) và `logo.png`; tạo lại icon bằng `dart run flutter_launcher_icons`.
