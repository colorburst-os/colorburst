# colorburst

*[English](README.md)*

colorburst là một hệ điều hành tự do dành cho máy tính cá nhân. Bạn có thể cài
đặt, sử dụng, sao chép và chỉnh sửa nó, không mất phí.

Hệ thống được xây dựng từ mã nguồn của **ChromiumOS** — phần mã nguồn mở Google
phát hành, cũng là nền tảng của ChromeOS chạy trên Chromebook. colorburst không
phải là ChromeOS và không liên kết với Google.

> **Đây là bản thử nghiệm.** Dự án đang ở giai đoạn đầu, nên đừng kỳ vọng mọi
> thứ chạy trơn tru. Nhiều chỗ trong giao diện vẫn tự xưng là "Chrome" hoặc
> "Chromium" — phần thương hiệu chưa thay hết, không phải cố ý.

## Điểm khác biệt chính

- **Tài khoản nằm trên máy.** Bạn tự tạo trong lần khởi động đầu tiên. Không
  cần tài khoản Google, không cần mạng để đăng nhập.
- **Không có dịch vụ Google.** Không có gì được gửi đi đâu để đăng nhập hay để
  dùng máy.
- **Giao diện tiếng Việt** và **bộ gõ tiếng Việt có sẵn** — Telex (mặc định),
  VNI và VIQR, không cần cài thêm. Chuyển bằng biểu tượng **VI** ở góc dưới bên
  phải, hoặc Ctrl + Space.
- **Tự cập nhật** qua máy chủ cập nhật của colorburst.

## Dành cho ai

Người dùng máy tính chủ yếu để lướt web. Không có gì phải học thêm, cũng không
có gì để cấu hình. Chạy được trên máy để bàn hoặc laptop sản xuất trong khoảng
**10 năm trở lại đây**.

## Dùng thử từ USB

Cách này chạy trên máy thật mà chưa đụng đến ổ cứng trong máy.

1. Tải `colorburst-<phiên bản>.zip` ở mục
   [Releases](https://github.com/colorburst-os/colorburst/releases). Cần một USB
   dung lượng từ **16 GB**.
2. Ghi tệp ảnh đĩa vào USB.

   **Windows / macOS:** [balenaEtcher](https://etcher.balena.io/) nhận thẳng
   tệp `.zip`.

   **Linux:**

   ```bash
   unzip colorburst-<phiên bản>.zip
   sudo dd if=colorburst-<phiên bản>.bin of=/dev/sdX bs=4M status=progress conv=fsync
   ```

   Thay `/dev/sdX` bằng USB của bạn. **Ghi nhầm ổ sẽ xoá sạch ổ đó** — kiểm tra
   kỹ bằng `lsblk`.
3. Khởi động máy từ USB (thường bấm F12, F2 hoặc Esc lúc mới bật máy). Có thể
   cần tắt **Secure Boot** trong BIOS/UEFI.

## Cài vào máy

Khởi động từ USB, rồi chọn mục cài đặt trên màn hình chào.

**Việc cài đặt sẽ xoá toàn bộ ổ đĩa được chọn.** Hãy sao lưu trước.

## Tài khoản

Ở màn hình chào, chọn **"Create a local account"**, đặt tên và mật khẩu.

Tài khoản đó chỉ nằm trên máy của bạn. Nếu quên mật khẩu thì không khôi phục
được — không có máy chủ nào giữ tài khoản để đặt lại giúp bạn.

## Tự biên dịch

Mọi thứ biên dịch trong Docker, không cài gì lên máy chủ. Công cụ và hướng dẫn
đầy đủ nằm ở
[chromiumos-devenv](https://github.com/colorburst-os/chromiumos-devenv).

Cần khoảng **200 GB ổ trống** và vài giờ cho lần biên dịch đầu.

## Hạn chế

- Chưa khôi phục được mật khẩu nếu quên.
- Nội dung có bản quyền số (DRM) — Netflix và tương tự chưa xem được.
- Bộ gõ tiếng Việt mới ở mức cơ bản; người quen gõ nhanh sẽ thấy còn vụng.
- Phần thương hiệu chưa thay hết: màn hình khởi động và vài chỗ vẫn là Chromium.

## Nguồn gốc và giấy phép

colorburst là một bản phân nhánh (fork) của ChromiumOS. Mã nguồn gốc thuộc về
các tác giả ChromiumOS và được phát hành theo giấy phép BSD 3 điều khoản; các
thành phần khác giữ nguyên giấy phép của chúng.

Dự án không liên hệ với Google. "Chrome", "ChromeOS" và "Chromebook" là thương
hiệu của Google.

## Về cái tên

Trên truyền hình analog màu (NTSC, PAL), mỗi dòng quét đều mở đầu bằng một đoạn
tín hiệu ngắn gọi là *colorburst* — vài chu kỳ của sóng mang màu, khoảng
3,58 MHz với NTSC. Bản thân nó không mang hình ảnh; nhiệm vụ duy nhất của nó là
cho bộ dao động trong máy thu một mốc pha để so. Không có đoạn tín hiệu đó, máy
thu vẫn hiện hình nhưng màu sẽ sai.

Một tín hiệu tham chiếu nhỏ, lặp lại đều đặn, để phần còn lại hiển thị đúng.
